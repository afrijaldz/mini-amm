# mini-amm

A cut-down Uniswap v2 written from scratch, to learn how a token swap works end to end.
Everything runs locally — no RPC, no fork.

Full documentation — architecture, swap lifecycle, math, security, every function and test — is in
[`docs/`](docs/README.md).

| File | What it is |
| --- | --- |
| `src/Token.sol` | minimal ERC-20 with an open `mint` (practice only) |
| `src/MiniPair.sol` | the pool: holds the reserves, `mint`/`burn` liquidity, `swap` with the `x·y=k` check |
| `src/MiniFactory.sol` | one pair per token pair |
| `src/MiniRouter.sol` | quotes, `addLiquidity`, `swapExactTokensForTokens` with `deadline` and `amountOutMin` |
| `test/Swap.t.sol` | 13 tests, one idea each |
| `script/Deploy.s.sol` | deploys the WETH/USDC pool to anvil for manual swaps with `cast` |

Compared with Uniswap v2, the pair has no LP ERC-20 (shares are a mapping), no `MINIMUM_LIQUIDITY`,
no TWAP oracle, no protocol fee, and the router does not rebalance `addLiquidity` amounts.
The swap logic and the error names match v2.

## Run the tests

```bash
forge test -vv                    # all tests with their logs
forge test --mt test_01 -vvvv     # one test with the full call trace
```

Setup in every test: pool of 1,000 WETH + 2,000,000 USDC (2,000 USDC per WETH), pool of
1,000,000 PEPE + 100 WETH, Alice has 10,000 USDC. All tokens use 18 decimals.

| Test | What it shows |
| --- | --- |
| `test_01_SwapStepByStep` | quote → approve → swap; output equals the quote; reserves move; `k` grows; the router holds nothing |
| `test_02_SwapWithoutApproveReverts` | no allowance, no swap |
| `test_03_DeadlineReverts` | `MiniRouter: EXPIRED` |
| `test_04_MinOutRevertsWhenPriceMovesFirst` | another trade lands first, `amountOutMin` stops the swap |
| `test_05_SwapDirectlyOnPairWithoutRouter` | send tokens to the pair, then call `pair.swap` — the router is optional |
| `test_06_AskingOneWeiMoreRevertsK` | the pair rejects anything that lowers `x·y` (after fee) |
| `test_07_TokensSentWithoutSwapCanBeTakenByAnyone` | transfer and swap in two transactions: someone else takes the output |
| `test_08_PriceImpact` | selling 1 / 10 / 100 / 500 WETH: impact 0.39% → 33.46% |
| `test_09_RoundTripFeesStayWithLP` | what a trader loses to fees is exactly what the LP withdraws extra |
| `test_10_MultiHop` | USDC → WETH → PEPE; pair 1 pays pair 2 directly |
| `test_11_FlashSwapPaysBackWithFee` | borrow 100 WETH inside one call, repay 100.3009 |
| `test_12_FlashSwapWithoutFeeReverts` | repaying without the fee fails the `K` check |
| `test_13_Sandwich` | without `amountOutMin` Alice gets 4.10 instead of 4.96 WETH; with 0.5% her swap reverts |

## Swap by hand on anvil

```bash
# terminal 1
anvil

# terminal 2 — use private key (0) from the anvil startup output
export PRIVATE_KEY=<anvil private key (0)>
forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
```

On a fresh anvil the addresses are always the same:

```bash
RPC=http://127.0.0.1:8545
ME=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
USDC=0x5FbDB2315678afecb367f032d93F642f64180aa3
WETH=0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
ROUTER=0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9
PAIR=0x75537828f2ce51be7289709686A69CbFDbB714F1

# 0. quote (eth_call, free)
cast call $PAIR 'getReserves()(uint256,uint256)' --rpc-url $RPC        # token0 = USDC here
cast call $ROUTER 'getAmountsOut(uint256,address[])(uint256[])' 1000ether "[$USDC,$WETH]" --rpc-url $RPC

# 1. approve
cast send $USDC 'approve(address,uint256)' $ROUTER 1000ether --private-key $PRIVATE_KEY --rpc-url $RPC

# 2. swap with 0.5% slippage and a 20-minute deadline
DEADLINE=$(( $(cast block --field timestamp --rpc-url $RPC) + 1200 ))
cast send $ROUTER 'swapExactTokensForTokens(uint256,uint256,address[],address,uint256)' \
  1000ether 0.4957ether "[$USDC,$WETH]" $ME $DEADLINE --private-key $PRIVATE_KEY --rpc-url $RPC

# 3. see what happened inside: transferFrom → pair.swap → transfer out → balanceOf → Sync → Swap
cast run <tx hash> --rpc-url $RPC
cast call $WETH 'balanceOf(address)(uint256)' $ME --rpc-url $RPC
```

The receipt has four logs in this order: `Transfer` USDC (you → pair), `Transfer` WETH
(pair → you), `Sync`, `Swap`.

## Exercises

1. **PancakeSwap fee.** Change the fee to 0.25% (`9975 / 10000`) in both `MiniPair.swap` and
   `MiniRouter.getAmountOut`. Which tests break, and why does changing only one of the two break
   `test_01`?
2. **Exact output.** Add `getAmountIn(amountOut, reserveIn, reserveOut)` and
   `swapTokensForExactTokens(amountOut, amountInMax, path, to, deadline)`. Hint: solve the
   `getAmountOut` formula for `amountIn` and round **up** (`+ 1`).
3. **Trusting the caller.** Change `swap` to take `amountIn` as a parameter instead of reading
   `balanceOf`. Write a test where the caller claims an input it never sent.
4. **Remove the lock.** Delete the `lock` modifier and write a flash borrower that calls `swap`
   again from `miniCall`. Can it get tokens out without paying?
5. **Break-even sandwich.** In `test_13`, find the largest front-run that still lets Alice's 0.5%
   swap go through, and the attacker's profit at that size.
