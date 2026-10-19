# 08 · Tests

← [07 Contract reference](07-contract-reference.md) · [Index](README.md) · [09 Local playground](09-local-playground.md) →

All tests are in `test/Swap.t.sol`. Each one shows one idea and prints its numbers with `-vv`.

```bash
forge test -vv                         # all, with logs
forge test --mt test_08 -vv            # one test
forge test --mt test_01 -vvvv          # one test with the full call trace
```

## Setup (`setUp`, `test/Swap.t.sol:49`)

| Item | Value |
| --- | --- |
| Tokens | `USDC`, `WETH`, `PEPE` — all 18 decimals (real USDC has 6) |
| WETH/USDC pool | 1,000 WETH + 2,000,000 USDC → 2,000 USDC per WETH, 44,721.36 shares to `lp` |
| PEPE/WETH pool | 1,000,000 PEPE + 100 WETH → 10,000 PEPE per WETH |
| Alice | 10,000 USDC |
| Others | `bob`, `attacker` get tokens inside the tests that need them |

Accounts are `makeAddr` labels, so traces show `alice`, `bob`, … instead of raw addresses.

## Results

These are the logged values from the last run (`forge test -vv`, 13 passed).

### Normal flow

| Test | Does | Asserts / logs |
| --- | --- | --- |
| `test_01_SwapStepByStep` | quote, approve, swap 1,000 USDC → WETH | received 0.4982 WETH = quote; effective price 2,007.0180; spot 2,000 → 2,001.9974; USDC reserve +1,000, WETH reserve −0.4982; `k` grows; router balances 0 |

### Router checks

| Test | Does | Expects |
| --- | --- | --- |
| `test_02_SwapWithoutApproveReverts` | swap with no allowance | `Token: allowance` |
| `test_03_DeadlineReverts` | `deadline = now − 1` | `MiniRouter: EXPIRED` |
| `test_04_MinOutRevertsWhenPriceMovesFirst` | Bob swaps 50,000 USDC first; Alice uses her old quote − 0.5% | quote 0.4982 → 0.4742 at execution; `MiniRouter: INSUFFICIENT_OUTPUT_AMOUNT` |

### The pair

| Test | Does | Expects |
| --- | --- | --- |
| `test_05_SwapDirectlyOnPairWithoutRouter` | `transfer` 1,000 USDC to the pair, then `pair.swap` | Alice gets exactly `getAmountOut` |
| `test_06_AskingOneWeiMoreRevertsK` | same, asking for 1 wei more | `MiniPair: K` |
| `test_07_TokensSentWithoutSwapCanBeTakenByAnyone` | Alice transfers, Bob calls `swap` | Bob gets the WETH, Alice gets nothing |

### Price impact and fees

| Test | Does | Logs |
| --- | --- | --- |
| `test_08_PriceImpact` | sells 1 / 10 / 100 / 500 WETH, each from the same state (`vm.snapshotState` / `vm.revertToState`) | impact 0.39% / 1.28% / 9.33% / 33.46%; each swap = its quote; impact strictly grows |
| `test_09_RoundTripFeesStayWithLP` | Bob swaps 10,000 USDC → WETH → USDC 5 times, then the LP burns all shares | Bob ends with 9,705.4469 USDC (−294.5530); LP gets 1,000 WETH + 2,000,294.5530 USDC — Bob's loss exactly |

### Routing

| Test | Does | Logs / asserts |
| --- | --- | --- |
| `test_10_MultiHop` | 1,000 USDC → WETH → PEPE | 0.4982 WETH in the middle, 4,943.0139 PEPE out; pair 2's WETH reserve rose by hop 1's output; Alice and router hold 0 WETH |

### Flash swaps

| Test | Does | Expects |
| --- | --- | --- |
| `test_11_FlashSwapPaysBackWithFee` | `FlashBorrower` borrows 100 WETH, repays `100e18 × 1000 / 997 + 1` | held 101 WETH during the callback; repaid 100.3009 (fee 0.3009) |
| `test_12_FlashSwapWithoutFeeReverts` | repays exactly 100 WETH | `MiniPair: K` |

### Sandwich

| Test | Does | Logs |
| --- | --- | --- |
| `test_13_Sandwich` | attacker buys with 200,000 USDC, Alice buys with 10,000 USDC, attacker sells; then the same with Alice's `amountOutMin = quote − 0.5%` | without protection Alice gets 4.1023 instead of 4.9602 WETH and the attacker makes +637.5836 USDC; with protection Alice's swap reverts |

## Helpers

| Helper | Line | Does |
| --- | --- | --- |
| `_swap(who, amountIn, minOut, path)` | 329 | prank as `who`, approve the router, swap, return the last amount |
| `_path(a, b)` | 337 | two-token path |
| `_wethOut(amount)` | 344 | `(amount0Out, amount1Out)` with WETH in the right slot |
| `_fmt(wad)` | 349 | 18-decimal amount as `1234.5678` |
| `_bps(bps)` | 356 | basis points as `12.34%` |
| `FlashBorrower` | top of file | flash swap receiver used by tests 11-12 |

## Foundry details used

| Cheatcode | Used for |
| --- | --- |
| `makeAddr` | labelled test accounts |
| `vm.prank` / `vm.startPrank` | act as a given account |
| `vm.expectRevert(bytes("..."))` | expect an exact revert string |
| `vm.warp` | set `block.timestamp` (deadline test) |
| `vm.snapshotState` / `vm.revertToState` | run several scenarios from the same pool state |

---

← [07 Contract reference](07-contract-reference.md) · [Index](README.md) · [09 Local playground](09-local-playground.md) →
