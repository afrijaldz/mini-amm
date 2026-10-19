# 03 · Math

← [02 Swap lifecycle](02-swap-lifecycle.md) · [Index](README.md) · [04 Liquidity](04-liquidity.md) →

Notation: `x` = reserve of the input token, `y` = reserve of the output token, `Δx` = amount in,
`Δy` = amount out, fee `f = 0.3%`.

## The invariant

The pool accepts a trade only if the product of the reserves does not go down, **counting only
99.7% of the input**:

```
(x + 0.997·Δx) · (y − Δy) ≥ x · y
```

The other 0.3% of the input still enters the pool, it just does not count toward the check. So
after every swap the real product `(x + Δx)(y − Δy)` is larger than `x·y`. That surplus is the fee.

## `getAmountOut`

Solve the invariant for the largest `Δy` (equality):

```
Δy = 0.997·Δx · y / (x + 0.997·Δx)
```

Multiply top and bottom by 1000 to stay in integers — this is `src/MiniRouter.sol:31-32`:

```
amountOut = (Δx × 997 × y) / (x × 1000 + Δx × 997)
```

Integer division rounds **down**, so the user gets at most the exact value and the pool keeps the
dust. Rounding down is what makes the router's quote always pass the pair's check.

## The `K` check in the pair

The pair does not receive `Δx` as a parameter; it measures it (`src/MiniPair.sol:114-115`):

```
amountIn = balance − (reserve − amountOut)
```

Then checks (`src/MiniPair.sol:119-121`), all multiplied by 1000 to avoid decimals:

```
(balance0 × 1000 − amount0In × 3) × (balance1 × 1000 − amount1In × 3) ≥ reserve0 × reserve1 × 1000²
```

Divide both sides by 1000² and it is the invariant above: `balance × 1000 − in × 3` is
`(balance − 0.003·in) × 1000`. The check is written per token, so it works for either direction and
even when both tokens come in at once.

`test_06` asks for `amountOut + 1` — one wei more than the formula — and the pair reverts with
`MiniPair: K`.

## Spot price, effective price, price impact

| | Formula | Example (1,000 WETH / 2,000,000 USDC) |
| --- | --- | --- |
| Spot price | `y / x` | 2,000 USDC per WETH |
| Effective price (selling `Δx` WETH) | `Δy / Δx` | depends on size |
| Price impact | `1 − effective / spot` | depends on size |

Put `getAmountOut` into the ratio:

```
effective / spot = 0.997 / (1 + 0.997·Δx / x)
```

Price impact depends only on **`Δx / x`** — the trade size relative to the input reserve — plus the
fee. That is why pool depth matters more than the token's price. `test_08`:

| Sell WETH | `Δx / x` | Received USDC | Effective price | Impact |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 0.1% | 1,992.01 | 1,992.01 | 0.39% |
| 10 | 1% | 19,743.16 | 1,974.32 | 1.28% |
| 100 | 10% | 181,322.18 | 1,813.22 | 9.33% |
| 500 | 50% | 665,332.00 | 1,330.66 | 33.46% |

For a tiny trade the impact approaches the fee (0.3%). The test prints impact in basis points
rounded down.

## How much a trader pays in fees

A swap's cost to the trader = fee + price impact. The fee part goes to the LPs; the price-impact
part is not lost — it moves the price, and the next trader in the other direction gets it back.
`test_09` makes this exact: Bob swaps 10,000 USDC → WETH → USDC five times and ends with
9,705.4469 USDC. The LP withdraws exactly 1,000 WETH (unchanged) plus 2,000,294.5530 USDC — the
294.5530 Bob lost, to the wei.

## Flash swap repayment

Borrow `B` of token0 and repay `R` of the same token inside the callback. After the callback
`balance0 = reserve0 − B + R`, so `amount0In = R`, and token1 does not move. The check becomes:

```
(reserve0 − B + R) × 1000 − 3R ≥ reserve0 × 1000
→ 997·R ≥ 1000·B
→ R ≥ B × 1000 / 997
```

For `B = 100` WETH: `R ≥ 100.3009` WETH. The fee is about 0.3009% of the amount borrowed, not
0.3%, because the fee is charged on the repayment, which already includes the fee. `test_11`
repays `100e18 × 1000 / 997 + 1` (the `+ 1` covers rounding); `test_12` repays exactly 100 and
reverts.

## LP shares

| Case | Shares minted | Code |
| --- | --- | --- |
| First deposit | `√(amount0 × amount1)` | `src/MiniPair.sol:65` |
| Later deposits | `min(amount0 × totalShares / reserve0, amount1 × totalShares / reserve1)` | `src/MiniPair.sol:67-69` |
| Burn | `amount = shares × balance / totalShares`, per token | `src/MiniPair.sol:84-85` |

The square root makes the first share count independent of which token is token0 and of the price.
In the tests the WETH/USDC pool starts with `√(1,000e18 × 2,000,000e18) = 44,721.36e18` shares.
See [04 Liquidity](04-liquidity.md).

## Overflow headroom

The largest product is in the `K` check: `reserve0 × reserve1 × 1000²`. With reserves of
`2e24 × 1e21` that is `2e51`, far below `uint256` (~`1.16e77`). Solidity 0.8 reverts on overflow,
so extreme reserves would revert rather than wrap. Uniswap v2 stores reserves as `uint112` for the
same reason (and to pack storage).

---

← [02 Swap lifecycle](02-swap-lifecycle.md) · [Index](README.md) · [04 Liquidity](04-liquidity.md) →
