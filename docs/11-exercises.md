# 11 · Exercises

← [10 Differences from Uniswap v2](10-differences-from-uniswap-v2.md) · [Index](README.md)

Each exercise changes the code and adds or changes a test. Keep `forge test` green, except where
the exercise asks you to make something break on purpose. Work on a copy of the file or undo the
change afterwards so the docs keep matching the code.

## 1. PancakeSwap fee (0.25%)

Change the fee to 0.25% — `9975 / 10000` instead of `997 / 1000`.

- Where: `MiniRouter.getAmountOut` (`src/MiniRouter.sol:31-32`) and the `K` check in
  `MiniPair.swap` (`src/MiniPair.sol:119-121`).
- First change **only the router**. Run `test_01`. Why does it fail, and with which error?
- Then change the pair too. Which logged numbers in `test_08` change, and by how much?
- Hint: in the pair, `× 1000 − in × 3` becomes `× 10000 − in × 25`, and the right side becomes
  `× 10000²`.

## 2. Exact output swap

Add the "I want exactly N tokens out" direction.

- `getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) → uint256`
- `getAmountsIn(uint256 amountOut, address[] path) → uint256[]` (walk the path backwards)
- `swapTokensForExactTokens(uint256 amountOut, uint256 amountInMax, address[] path, address to, uint256 deadline)`
- Hint: solve `Δy = 997·Δx·y / (1000·x + 997·Δx)` for `Δx`, then **round up** (`+ 1`) — rounding
  down would leave the pair short and fail `K`.
- Test: the user receives exactly `amountOut`; `amountInMax` below the required input reverts.

## 3. A pair that trusts the caller

Change `swap` to take `amountIn` as a parameter and use it instead of measuring
`balance − (reserve − out)`.

- Write a test where the caller passes a large `amountIn` but sends nothing.
- What does the pair lose? Which line in [06 Security](06-security.md#what-protects-the-pool)
  explains why the real design measures balances?

## 4. Remove the lock

Delete the `lock` modifier from `swap`, `mint`, and `burn`.

- Write a flash borrower whose `miniCall` calls `pair.swap` again, or `pair.mint`, before paying.
- Can it leave the pair with less `k` than before? Follow the values of `reserve0` / `reserve1`
  that the outer `swap` reads at `src/MiniPair.sol:114-121`.
- Compare with Uniswap v2's `swap`, which reads `getReserves()` into local variables at the start.

## 5. Break-even sandwich

In `test_13_Sandwich`, Alice uses 0.5% slippage on a 10,000 USDC buy.

- Find the largest front-run (in USDC) that still lets her swap go through.
- What is the attacker's profit at that size? How close does Alice get to her `amountOutMin`?
- Repeat with slippage 0.1% and 2%. How does the attacker's maximum profit scale?
- Hint: loop over front-run sizes with `vm.snapshotState` / `vm.revertToState`, and use
  `try router.swapExactTokensForTokens(...)` from a helper contract — or bisect by hand.

---

← [10 Differences from Uniswap v2](10-differences-from-uniswap-v2.md) · [Index](README.md)
