# mini-amm documentation

`mini-amm` is a cut-down Uniswap v2 written from scratch to learn how a token swap works.
These pages explain the design, the math, every function, and what each test proves.

## Reading order

| No | Page | What it covers |
| ---: | --- | --- |
| 01 | [Architecture](01-architecture.md) | the four contracts, who calls whom, state, token ordering |
| 02 | [Swap lifecycle](02-swap-lifecycle.md) | one swap from quote to `Swap` event, with line references |
| 03 | [Math](03-math.md) | `getAmountOut`, the `K` check, fees, price impact, rounding |
| 04 | [Liquidity](04-liquidity.md) | `mint`, `burn`, share math, how LPs earn the fee |
| 05 | [Multi-hop and flash swaps](05-multihop-and-flash-swaps.md) | routing through several pairs, borrowing inside one call |
| 06 | [Security notes](06-security.md) | what protects users and the pool, and what does not |
| 07 | [Contract reference](07-contract-reference.md) | every public function: parameters, returns, reverts, events |
| 08 | [Tests](08-tests.md) | every test: setup, steps, result |
| 09 | [Local playground](09-local-playground.md) | deploy to anvil and swap by hand with `cast` |
| 10 | [Differences from Uniswap v2](10-differences-from-uniswap-v2.md) | what was cut and why it matters |
| 11 | [Exercises](11-exercises.md) | five tasks with hints |

## Quick start

```bash
forge test -vv                    # all 13 tests with logs
forge test --mt test_01 -vvvv     # one swap with the full call trace
```

## Words used in these pages

| Term | Meaning |
| --- | --- |
| **pair / pool** | one `MiniPair` contract holding two tokens |
| **reserve** | the token amount the pair last recorded (`reserve0`, `reserve1`); equals its balance after every call |
| **token0 / token1** | the two tokens sorted by address; token0 has the smaller address |
| **k** | `reserve0 × reserve1`; a swap may never lower it (after the fee) |
| **spot price** | `reserveOut / reserveIn`, the price for an infinitely small trade |
| **effective price** | `amountIn / amountOut` of a real trade |
| **price impact** | how much worse the effective price is than the spot price |
| **slippage** | the change between the quote and the execution, caused by other transactions in between |
| **LP** | liquidity provider, the account that deposited both tokens and holds shares |
| **share** | a claim on a fraction of the pair's balances (`sharesOf[account] / totalShares`) |
| **path** | the list of tokens a multi-hop swap goes through, e.g. `[USDC, WETH, PEPE]` |
| **flash swap** | receive the output first, pay inside the callback of the same call |
