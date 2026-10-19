// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {Token} from "../src/Token.sol";
import {MiniFactory} from "../src/MiniFactory.sol";
import {MiniPair, IMiniCallee} from "../src/MiniPair.sol";
import {MiniRouter} from "../src/MiniRouter.sol";

/// Borrows WETH from the pair and pays it back inside the callback (flash swap).
contract FlashBorrower is IMiniCallee {
    MiniPair public pair;
    Token public weth;
    uint256 public repayAmount;
    uint256 public balanceDuringCall;

    constructor(MiniPair _pair, Token _weth) {
        pair = _pair;
        weth = _weth;
    }

    function borrow(uint256 amount, uint256 _repayAmount) external {
        repayAmount = _repayAmount;
        (uint256 amount0Out, uint256 amount1Out) =
            pair.token0() == address(weth) ? (amount, uint256(0)) : (uint256(0), amount);
        pair.swap(amount0Out, amount1Out, address(this), "flash");
    }

    function miniCall(address, uint256, uint256, bytes calldata) external {
        require(msg.sender == address(pair), "FlashBorrower: not the pair");
        // The borrowed WETH is here now. A real bot would arbitrage or liquidate with it.
        balanceDuringCall = weth.balanceOf(address(this));
        weth.transfer(address(pair), repayAmount);
    }
}

contract SwapTest is Test {
    Token usdc;
    Token weth;
    Token pepe;
    MiniFactory factory;
    MiniRouter router;
    MiniPair pair; // WETH/USDC

    address lp = makeAddr("lp");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address attacker = makeAddr("attacker");

    function setUp() public {
        // All tokens use 18 decimals to keep the numbers readable (real USDC has 6).
        usdc = new Token("USD Coin", "USDC");
        weth = new Token("Wrapped Ether", "WETH");
        pepe = new Token("Pepe", "PEPE");
        factory = new MiniFactory();
        router = new MiniRouter(factory);

        // The LP opens two pools: 1,000 WETH + 2,000,000 USDC (2,000 USDC per WETH)
        // and 1,000,000 PEPE + 100 WETH (10,000 PEPE per WETH).
        usdc.mint(lp, 2_000_000e18);
        weth.mint(lp, 1_100e18);
        pepe.mint(lp, 1_000_000e18);
        vm.startPrank(lp);
        usdc.approve(address(router), type(uint256).max);
        weth.approve(address(router), type(uint256).max);
        pepe.approve(address(router), type(uint256).max);
        router.addLiquidity(address(weth), address(usdc), 1_000e18, 2_000_000e18, lp);
        router.addLiquidity(address(pepe), address(weth), 1_000_000e18, 100e18, lp);
        vm.stopPrank();

        pair = MiniPair(factory.getPair(address(weth), address(usdc)));
        usdc.mint(alice, 10_000e18);
    }

    // ------------------------------------------------------------------ 1. the normal flow

    function test_01_SwapStepByStep() public {
        address[] memory path = _path(address(usdc), address(weth));
        (uint256 wethBefore, uint256 usdcBefore) = router.getReserves(address(weth), address(usdc));
        console2.log("reserves before   :", _fmt(wethBefore), "WETH /", string.concat(_fmt(usdcBefore), " USDC"));
        console2.log("spot price        :", _fmt(usdcBefore * 1e18 / wethBefore), "USDC per WETH");

        // 0. Quote off-chain (eth_call, no transaction) and set a 0.5% slippage limit.
        uint256 quote = router.getAmountsOut(1_000e18, path)[1];
        uint256 minOut = quote * 995 / 1000;
        console2.log("quote             :", _fmt(quote), "WETH for 1,000 USDC");
        console2.log("amountOutMin      :", _fmt(minOut), "WETH (quote - 0.5%)");

        vm.startPrank(alice);
        // 1. approve: allow the router to pull Alice's USDC.
        usdc.approve(address(router), 1_000e18);
        // 2. swap: router checks deadline + amountOutMin, moves USDC into the pair, calls pair.swap.
        uint256[] memory amounts =
            router.swapExactTokensForTokens(1_000e18, minOut, path, alice, block.timestamp + 20 minutes);
        vm.stopPrank();

        (uint256 wethAfter, uint256 usdcAfter) = router.getReserves(address(weth), address(usdc));
        console2.log("received          :", _fmt(amounts[1]), "WETH");
        console2.log("effective price   :", _fmt(1_000e18 * 1e18 / amounts[1]), "USDC per WETH");
        console2.log("reserves after    :", _fmt(wethAfter), "WETH /", string.concat(_fmt(usdcAfter), " USDC"));
        console2.log("new spot price    :", _fmt(usdcAfter * 1e18 / wethAfter), "USDC per WETH");

        assertEq(amounts[1], quote, "nothing moved the pool between quote and swap");
        assertEq(weth.balanceOf(alice), quote);
        assertEq(usdc.balanceOf(alice), 9_000e18);
        assertEq(usdcAfter, usdcBefore + 1_000e18);
        assertEq(wethAfter, wethBefore - quote);
        assertGt(wethAfter * usdcAfter, wethBefore * usdcBefore, "the fee stays in the pool, so k grows");
        assertEq(usdc.balanceOf(address(router)), 0, "router never holds tokens");
        assertEq(weth.balanceOf(address(router)), 0, "router never holds tokens");
    }

    // ------------------------------------------------------------------ 2. router safety checks

    function test_02_SwapWithoutApproveReverts() public {
        vm.prank(alice);
        vm.expectRevert(bytes("Token: allowance"));
        router.swapExactTokensForTokens(1_000e18, 0, _path(address(usdc), address(weth)), alice, block.timestamp);
    }

    function test_03_DeadlineReverts() public {
        vm.warp(1_000_000);
        vm.startPrank(alice);
        usdc.approve(address(router), 1_000e18);
        vm.expectRevert(bytes("MiniRouter: EXPIRED"));
        router.swapExactTokensForTokens(1_000e18, 0, _path(address(usdc), address(weth)), alice, block.timestamp - 1);
        vm.stopPrank();
    }

    function test_04_MinOutRevertsWhenPriceMovesFirst() public {
        address[] memory path = _path(address(usdc), address(weth));
        uint256 quote = router.getAmountsOut(1_000e18, path)[1];
        uint256 minOut = quote * 995 / 1000;

        // Bob's big buy lands before Alice's transaction and pushes the WETH price up.
        usdc.mint(bob, 50_000e18);
        _swap(bob, 50_000e18, 0, path);

        console2.log("quote when Alice signed:", _fmt(quote), "WETH");
        console2.log("output at execution    :", _fmt(router.getAmountsOut(1_000e18, path)[1]), "WETH");

        vm.startPrank(alice);
        usdc.approve(address(router), 1_000e18);
        vm.expectRevert(bytes("MiniRouter: INSUFFICIENT_OUTPUT_AMOUNT"));
        router.swapExactTokensForTokens(1_000e18, minOut, path, alice, block.timestamp);
        vm.stopPrank();
    }

    // ------------------------------------------------------------------ 3. the pair itself

    function test_05_SwapDirectlyOnPairWithoutRouter() public {
        (uint256 reserveWeth, uint256 reserveUsdc) = router.getReserves(address(weth), address(usdc));
        uint256 amountOut = router.getAmountOut(1_000e18, reserveUsdc, reserveWeth);

        vm.startPrank(alice);
        usdc.transfer(address(pair), 1_000e18); // pay first
        (uint256 amount0Out, uint256 amount1Out) = _wethOut(amountOut);
        pair.swap(amount0Out, amount1Out, alice, ""); // then ask for the output
        vm.stopPrank();

        assertEq(weth.balanceOf(alice), amountOut, "the router is optional");
    }

    function test_06_AskingOneWeiMoreRevertsK() public {
        (uint256 reserveWeth, uint256 reserveUsdc) = router.getReserves(address(weth), address(usdc));
        uint256 amountOut = router.getAmountOut(1_000e18, reserveUsdc, reserveWeth);

        vm.startPrank(alice);
        usdc.transfer(address(pair), 1_000e18);
        (uint256 amount0Out, uint256 amount1Out) = _wethOut(amountOut + 1);
        vm.expectRevert(bytes("MiniPair: K"));
        pair.swap(amount0Out, amount1Out, alice, "");
        vm.stopPrank();
    }

    function test_07_TokensSentWithoutSwapCanBeTakenByAnyone() public {
        (uint256 reserveWeth, uint256 reserveUsdc) = router.getReserves(address(weth), address(usdc));
        uint256 amountOut = router.getAmountOut(1_000e18, reserveUsdc, reserveWeth);

        // Transaction 1: Alice sends USDC to the pair and stops there.
        vm.prank(alice);
        usdc.transfer(address(pair), 1_000e18);

        // Transaction 2: Bob pays nothing and claims the output. The pair only sees "the balance went up".
        (uint256 amount0Out, uint256 amount1Out) = _wethOut(amountOut);
        vm.prank(bob);
        pair.swap(amount0Out, amount1Out, bob, "");

        assertEq(weth.balanceOf(bob), amountOut, "Bob took Alice's swap");
        assertEq(weth.balanceOf(alice), 0);
    }

    // ------------------------------------------------------------------ 4. price impact and fees

    function test_08_PriceImpact() public {
        address[] memory path = _path(address(weth), address(usdc));
        (uint256 reserveWeth, uint256 reserveUsdc) = router.getReserves(address(weth), address(usdc));
        uint256 spot = reserveUsdc * 1e18 / reserveWeth;
        weth.mint(bob, 500e18);

        uint256[4] memory sizes = [uint256(1e18), 10e18, 100e18, 500e18];
        uint256 lastImpactBps;
        for (uint256 i = 0; i < sizes.length; i++) {
            uint256 snapshot = vm.snapshotState();

            uint256 quote = router.getAmountsOut(sizes[i], path)[1];
            uint256 received = _swap(bob, sizes[i], 0, path);
            uint256 price = received * 1e18 / sizes[i];
            uint256 impactBps = (spot - price) * 10_000 / spot;
            console2.log(
                string.concat(
                    "sell ",
                    _fmt(sizes[i]),
                    " WETH -> ",
                    _fmt(received),
                    " USDC | price ",
                    _fmt(price),
                    " | impact ",
                    _bps(impactBps)
                )
            );

            assertEq(received, quote);
            assertGt(impactBps, lastImpactBps, "bigger trade, worse price");
            lastImpactBps = impactBps;
            vm.revertToState(snapshot);
        }
    }

    function test_09_RoundTripFeesStayWithLP() public {
        usdc.mint(bob, 10_000e18);
        for (uint256 i = 0; i < 5; i++) {
            uint256 wethReceived = _swap(bob, usdc.balanceOf(bob), 0, _path(address(usdc), address(weth)));
            _swap(bob, wethReceived, 0, _path(address(weth), address(usdc)));
        }
        uint256 bobLoss = 10_000e18 - usdc.balanceOf(bob);
        console2.log("Bob after 5 round trips:", _fmt(usdc.balanceOf(bob)), "USDC, lost", _fmt(bobLoss));

        // The LP owns every share of the pair, so burning them returns the whole pool.
        uint256 shares = pair.sharesOf(lp);
        vm.prank(lp);
        (uint256 amount0, uint256 amount1) = pair.burn(shares, lp);
        (uint256 wethOut, uint256 usdcOut) = pair.token0() == address(weth) ? (amount0, amount1) : (amount1, amount0);
        console2.log("LP withdraws:", _fmt(wethOut), "WETH +", string.concat(_fmt(usdcOut), " USDC"));

        assertEq(wethOut, 1_000e18, "every WETH Bob took came back");
        assertEq(usdcOut, 2_000_000e18 + bobLoss, "what Bob lost is exactly what the LP earned");
    }

    // ------------------------------------------------------------------ 5. routing

    function test_10_MultiHop() public {
        address[] memory path = new address[](3);
        path[0] = address(usdc);
        path[1] = address(weth);
        path[2] = address(pepe);
        MiniPair pepePair = MiniPair(factory.getPair(address(pepe), address(weth)));
        (uint256 pepePoolWethBefore,) = router.getReserves(address(weth), address(pepe));

        vm.startPrank(alice);
        usdc.approve(address(router), 1_000e18);
        uint256[] memory amounts = router.swapExactTokensForTokens(1_000e18, 0, path, alice, block.timestamp);
        vm.stopPrank();

        console2.log("hop 1:", _fmt(amounts[0]), "USDC -> WETH", _fmt(amounts[1]));
        console2.log("hop 2:", _fmt(amounts[1]), "WETH -> PEPE", _fmt(amounts[2]));

        (uint256 pepePoolWethAfter,) = router.getReserves(address(weth), address(pepe));
        assertEq(pepePoolWethAfter, pepePoolWethBefore + amounts[1], "hop 1 output went straight into pair 2");
        assertEq(pepe.balanceOf(alice), amounts[2]);
        assertEq(weth.balanceOf(alice), 0, "Alice never held the WETH in the middle");
        assertEq(weth.balanceOf(address(router)), 0);
        assertEq(weth.balanceOf(address(pepePair)), pepePoolWethAfter);
    }

    // ------------------------------------------------------------------ 6. flash swap

    function test_11_FlashSwapPaysBackWithFee() public {
        FlashBorrower borrower = new FlashBorrower(pair, weth);
        weth.mint(address(borrower), 1e18); // enough to cover the fee
        uint256 borrowed = 100e18;
        uint256 repay = borrowed * 1000 / 997 + 1;

        borrower.borrow(100e18, repay);

        console2.log("held during callback:", _fmt(borrower.balanceDuringCall()), "WETH");
        console2.log("repaid              :", _fmt(repay), "WETH (fee", string.concat(_fmt(repay - borrowed), ")"));
        assertEq(borrower.balanceDuringCall(), borrowed + 1e18);
        assertEq(weth.balanceOf(address(borrower)), 101e18 - repay);
    }

    function test_12_FlashSwapWithoutFeeReverts() public {
        FlashBorrower borrower = new FlashBorrower(pair, weth);
        vm.expectRevert(bytes("MiniPair: K"));
        borrower.borrow(100e18, 100e18);
    }

    // ------------------------------------------------------------------ 7. sandwich

    function test_13_Sandwich() public {
        address[] memory buy = _path(address(usdc), address(weth));
        address[] memory sell = _path(address(weth), address(usdc));
        uint256 quote = router.getAmountsOut(10_000e18, buy)[1];
        usdc.mint(attacker, 200_000e18);
        uint256 snapshot = vm.snapshotState();

        // A: Alice signs with amountOutMin = 0.
        uint256 front = _swap(attacker, 200_000e18, 0, buy);
        uint256 victimGot = _swap(alice, 10_000e18, 0, buy);
        uint256 back = _swap(attacker, front, 0, sell);
        console2.log("no attack, Alice would get:", _fmt(quote), "WETH");
        console2.log("sandwiched, Alice got     :", _fmt(victimGot), "WETH");
        console2.log("attacker profit           :", _fmt(back - 200_000e18), "USDC");
        assertLt(victimGot, quote);
        assertGt(back, 200_000e18);

        // B: same attack, but Alice signed with 0.5% slippage. Her transaction reverts instead.
        vm.revertToState(snapshot);
        _swap(attacker, 200_000e18, 0, buy);
        vm.startPrank(alice);
        usdc.approve(address(router), 10_000e18);
        vm.expectRevert(bytes("MiniRouter: INSUFFICIENT_OUTPUT_AMOUNT"));
        router.swapExactTokensForTokens(10_000e18, quote * 995 / 1000, buy, alice, block.timestamp);
        vm.stopPrank();
    }

    // ------------------------------------------------------------------ helpers

    function _swap(address who, uint256 amountIn, uint256 minOut, address[] memory path) internal returns (uint256) {
        vm.startPrank(who);
        Token(path[0]).approve(address(router), amountIn);
        uint256[] memory amounts = router.swapExactTokensForTokens(amountIn, minOut, path, who, block.timestamp);
        vm.stopPrank();
        return amounts[amounts.length - 1];
    }

    function _path(address a, address b) internal pure returns (address[] memory path) {
        path = new address[](2);
        path[0] = a;
        path[1] = b;
    }

    /// pair.swap takes (amount0Out, amount1Out); which one is WETH depends on the address order.
    function _wethOut(uint256 amount) internal view returns (uint256, uint256) {
        return pair.token0() == address(weth) ? (amount, uint256(0)) : (uint256(0), amount);
    }

    /// 18-decimal amount as "1234.5678".
    function _fmt(uint256 wad) internal pure returns (string memory) {
        uint256 frac = (wad % 1e18) / 1e14;
        string memory pad = frac < 10 ? "000" : frac < 100 ? "00" : frac < 1000 ? "0" : "";
        return string.concat(vm.toString(wad / 1e18), ".", pad, vm.toString(frac));
    }

    /// Basis points as "12.34%".
    function _bps(uint256 bps) internal pure returns (string memory) {
        string memory pad = bps % 100 < 10 ? "0" : "";
        return string.concat(vm.toString(bps / 100), ".", pad, vm.toString(bps % 100), "%");
    }
}
