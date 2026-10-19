# 10 · Differences from Uniswap v2

← [09 Local playground](09-local-playground.md) · [Index](README.md) · [11 Exercises](11-exercises.md) →

`mini-amm` keeps the swap rules of Uniswap v2 — the same `getAmountOut`, the same `K` check, the
same error names — and leaves out the rest. Use this table when you read the real code
(`v2-core`: `UniswapV2Pair.sol`, `UniswapV2Factory.sol`; `v2-periphery`: `UniswapV2Router02.sol`,
`UniswapV2Library.sol`).

## Same as v2

| Part | Detail |
| --- | --- |
| Fee | 0.3%, taken from the input inside the `K` check (`× 1000 − in × 3`) |
| `getAmountOut` | identical formula and rounding |
| Swap shape | `swap(amount0Out, amount1Out, to, data)`: send first, callback if `data`, measure input from balances, check `K` |
| Token order | `token0 < token1` by address |
| First-deposit shares | `√(amount0 × amount1)` |
| Later shares / burn | proportional, `min` of the two sides on deposit |
| Router safety | `deadline` (`EXPIRED`), `amountOutMin` (`INSUFFICIENT_OUTPUT_AMOUNT`) |
| Multi-hop | each pair sends to the next pair |
| Re-entrancy | `lock` on `mint`, `burn`, `swap` |

## Different

| Part | Uniswap v2 | mini-amm | Consequence |
| --- | --- | --- | --- |
| LP shares | an ERC-20 token per pair (`UNI-V2`), transferable, with `permit` | `sharesOf` mapping, not transferable | LP positions cannot be moved or used elsewhere |
| `MINIMUM_LIQUIDITY` | first 1,000 shares minted to `address(0)` | none | first-depositor inflation is cheap ([06 Security](06-security.md#first-depositor-share-inflation)) |
| Reserve storage | `uint112` × 2 + `uint32` timestamp in one slot | two `uint256` slots | more gas per swap; more overflow headroom |
| Reserves in `swap` | copied to local variables at the start | read from storage after the callback | relies on `lock` alone ([06 Security](06-security.md#why-lock-matters-here)) |
| Price oracle | `price0CumulativeLast` / `price1CumulativeLast` (TWAP) | none | no manipulation-resistant price |
| Protocol fee | `feeTo` gets 1/6 of the fee as LP tokens (`_mintFee`, `kLast`) | none | all fees go to LPs |
| `skim` / `sync` | present | absent | stray tokens can only leave through `mint`, `burn`, or `swap` |
| Pair address | `CREATE2`, computed off-chain by `pairFor` | `new MiniPair`, read from `factory.getPair` | the router makes an extra call per hop |
| Token transfers | low-level call, accepts tokens without a return value | `require(token.transfer(...))` | tokens like USDT on Ethereum would revert |
| Callback name | `uniswapV2Call` | `miniCall` | — |
| `addLiquidity` | computes optimal amounts with `amountAMin` / `amountBMin`, creates pair via `CREATE2` | uses the exact amounts | off-ratio deposits donate the excess ([04 Liquidity](04-liquidity.md#depositing-off-the-ratio)) |
| `removeLiquidity` in router | yes, with minimums and `permit` | LP calls `pair.burn` directly | no slippage check on withdrawal |
| Swap functions in router | 9, incl. exact-output, ETH in/out, fee-on-transfer variants | `swapExactTokensForTokens` only | exercise 2 adds exact output |
| Native ETH | router wraps/unwraps through WETH | ERC-20 only | — |

## Beyond v2

The same mental model carries forward:

| Version | What changes on top of v2 |
| --- | --- |
| Uniswap v3 | liquidity per price range (ticks); price stored as `sqrtPriceX96`; payment in `uniswapV3SwapCallback` |
| Uniswap v4 | all pools in one `PoolManager`; hooks; balances settled once at the end (flash accounting) |
| PancakeSwap v2 | a v2 fork with a 0.25% fee (`9975 / 10000`) — exercise 1 |

---

← [09 Local playground](09-local-playground.md) · [Index](README.md) · [11 Exercises](11-exercises.md) →
