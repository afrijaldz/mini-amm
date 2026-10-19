// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {MiniFactory} from "./MiniFactory.sol";
import {MiniPair} from "./MiniPair.sol";

interface IERC20From {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// Helper in front of the pairs. Holds no funds. It adds the safety checks (deadline, amountOutMin)
/// and does "move tokens into the pair + call the pair" in one transaction.
contract MiniRouter {
    MiniFactory public immutable factory;

    constructor(MiniFactory _factory) {
        factory = _factory;
    }

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "MiniRouter: EXPIRED");
        _;
    }

    // ---------------------------------------------------------------- quotes

    /// Same formula as UniswapV2Library.getAmountOut: fee 0.3% taken from the input, then x·y=k.
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) public pure returns (uint256) {
        require(amountIn > 0, "MiniRouter: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "MiniRouter: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * 997;
        return amountInWithFee * reserveOut / (reserveIn * 1000 + amountInWithFee);
    }

    /// Output of every hop along `path`, read from the reserves at the moment of the call.
    function getAmountsOut(uint256 amountIn, address[] memory path) public view returns (uint256[] memory amounts) {
        require(path.length >= 2, "MiniRouter: INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i = 0; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    /// Reserves ordered as (tokenA side, tokenB side).
    function getReserves(address tokenA, address tokenB) public view returns (uint256 reserveA, uint256 reserveB) {
        MiniPair pair = _pair(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1) = pair.getReserves();
        (reserveA, reserveB) = tokenA == pair.token0() ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // ---------------------------------------------------------------- liquidity

    /// Deposits exactly the given amounts. Unlike Uniswap, it does not adjust them to the pool ratio:
    /// a deposit off the ratio gets shares for the smaller side and donates the rest.
    function addLiquidity(address tokenA, address tokenB, uint256 amountA, uint256 amountB, address to)
        external
        returns (uint256 shares)
    {
        if (factory.getPair(tokenA, tokenB) == address(0)) {
            factory.createPair(tokenA, tokenB);
        }
        MiniPair pair = _pair(tokenA, tokenB);
        _transferFrom(tokenA, msg.sender, address(pair), amountA);
        _transferFrom(tokenB, msg.sender, address(pair), amountB);
        shares = pair.mint(to);
    }

    // ---------------------------------------------------------------- swaps

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        amounts = getAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "MiniRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        // The input goes straight from the user to the first pair; the router never holds it.
        _transferFrom(path[0], msg.sender, address(_pair(path[0], path[1])), amountIn);
        _swap(amounts, path, to);
    }

    /// Calls `swap` on every pair along the path. Each pair sends its output straight to the next pair;
    /// only the last pair sends to `_to`.
    function _swap(uint256[] memory amounts, address[] calldata path, address _to) internal {
        for (uint256 i = 0; i < path.length - 1; i++) {
            address input = path[i];
            address output = path[i + 1];
            MiniPair pair = _pair(input, output);

            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) =
                input == pair.token0() ? (uint256(0), amountOut) : (amountOut, uint256(0));

            address to = i < path.length - 2 ? address(_pair(output, path[i + 2])) : _to;
            pair.swap(amount0Out, amount1Out, to, "");
        }
    }

    function _pair(address tokenA, address tokenB) internal view returns (MiniPair) {
        address pair = factory.getPair(tokenA, tokenB);
        require(pair != address(0), "MiniRouter: NO_PAIR");
        return MiniPair(pair);
    }

    function _transferFrom(address token, address from, address to, uint256 amount) internal {
        require(IERC20From(token).transferFrom(from, to, amount), "MiniRouter: TRANSFER_FROM_FAILED");
    }
}
