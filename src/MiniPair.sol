// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

/// Called on `to` during a flash swap (when `data` is not empty).
interface IMiniCallee {
    function miniCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}

/// A cut-down Uniswap v2 pair. Same swap rules, fewer features:
/// LP shares are a plain mapping (not an ERC-20), no MINIMUM_LIQUIDITY, no TWAP oracle, no protocol fee.
contract MiniPair {
    address public immutable token0;
    address public immutable token1;

    uint256 public reserve0;
    uint256 public reserve1;

    uint256 public totalShares;
    mapping(address => uint256) public sharesOf;

    bool private locked;

    event Mint(address indexed to, uint256 amount0, uint256 amount1, uint256 shares);
    event Burn(address indexed from, address indexed to, uint256 amount0, uint256 amount1, uint256 shares);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint256 reserve0, uint256 reserve1);

    /// Blocks re-entering the pair from a flash swap callback.
    modifier lock() {
        require(!locked, "MiniPair: LOCKED");
        locked = true;
        _;
        locked = false;
    }

    constructor(address tokenA, address tokenB) {
        // Sorted by address, like Uniswap: token0 is the smaller address.
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    function getReserves() external view returns (uint256, uint256) {
        return (reserve0, reserve1);
    }

    /// Send both tokens to the pair first, then call this. It counts what arrived since the last update.
    function mint(address to) external lock returns (uint256 shares) {
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - reserve0;
        uint256 amount1 = balance1 - reserve1;

        if (totalShares == 0) {
            shares = _sqrt(amount0 * amount1);
        } else {
            uint256 shares0 = amount0 * totalShares / reserve0;
            uint256 shares1 = amount1 * totalShares / reserve1;
            shares = shares0 < shares1 ? shares0 : shares1;
        }
        require(shares > 0, "MiniPair: INSUFFICIENT_LIQUIDITY_MINTED");

        sharesOf[to] += shares;
        totalShares += shares;
        _update(balance0, balance1);
        emit Mint(to, amount0, amount1, shares);
    }

    /// Burns the caller's shares and pays out its part of the current balances.
    function burn(uint256 shares, address to) external lock returns (uint256 amount0, uint256 amount1) {
        require(sharesOf[msg.sender] >= shares, "MiniPair: INSUFFICIENT_SHARES");
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        amount0 = shares * balance0 / totalShares;
        amount1 = shares * balance1 / totalShares;
        require(amount0 > 0 && amount1 > 0, "MiniPair: INSUFFICIENT_LIQUIDITY_BURNED");

        sharesOf[msg.sender] -= shares;
        totalShares -= shares;
        _safeTransfer(token0, to, amount0);
        _safeTransfer(token1, to, amount1);

        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)));
        emit Burn(msg.sender, to, amount0, amount1, shares);
    }

    /// The core of every swap. The caller says how much it wants OUT; the input must already be in
    /// the pair (or arrive during the flash swap callback). The pair sends first and checks after.
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external lock {
        require(amount0Out > 0 || amount1Out > 0, "MiniPair: INSUFFICIENT_OUTPUT_AMOUNT");
        require(amount0Out < reserve0 && amount1Out < reserve1, "MiniPair: INSUFFICIENT_LIQUIDITY");
        require(to != token0 && to != token1, "MiniPair: INVALID_TO");

        // 1. Send the output first (optimistic transfer).
        if (amount0Out > 0) _safeTransfer(token0, to, amount0Out);
        if (amount1Out > 0) _safeTransfer(token1, to, amount1Out);

        // 2. Flash swap: let the receiver use the tokens and pay back inside this same call.
        if (data.length > 0) IMiniCallee(to).miniCall(msg.sender, amount0Out, amount1Out, data);

        // 3. What came in = balance now − (old reserve − what went out).
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0In = balance0 > reserve0 - amount0Out ? balance0 - (reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > reserve1 - amount1Out ? balance1 - (reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, "MiniPair: INSUFFICIENT_INPUT_AMOUNT");

        // 4. x·y must not go down, after taking a 0.3% fee from the input side.
        uint256 balance0Adjusted = balance0 * 1000 - amount0In * 3;
        uint256 balance1Adjusted = balance1 * 1000 - amount1In * 3;
        require(balance0Adjusted * balance1Adjusted >= reserve0 * reserve1 * 1000 ** 2, "MiniPair: K");

        _update(balance0, balance1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    function _update(uint256 balance0, uint256 balance1) internal {
        reserve0 = balance0;
        reserve1 = balance1;
        emit Sync(balance0, balance1);
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        require(IERC20(token).transfer(to, amount), "MiniPair: TRANSFER_FAILED");
    }

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
