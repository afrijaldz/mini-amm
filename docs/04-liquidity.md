# 04 · Liquidity

← [03 Math](03-math.md) · [Index](README.md) · [05 Multi-hop and flash swaps](05-multihop-and-flash-swaps.md) →

A pool can only swap what LPs deposited. LPs put in both tokens, get **shares**, and later burn
the shares for their fraction of whatever the pool holds then.

## Adding liquidity

### Through the router

`router.addLiquidity(tokenA, tokenB, amountA, amountB, to)` (`src/MiniRouter.sol:57-68`):

1. Create the pair through the factory if it does not exist.
2. `transferFrom` both amounts from the caller **to the pair**.
3. Call `pair.mint(to)`.

All three happen in one transaction, so nobody can step in between (compare
[06 Security](06-security.md), "Tokens sent in a separate transaction").

The router deposits **exactly** the amounts given. It does not trim them to the pool ratio — see
"Depositing off the ratio" below.

### `pair.mint(to)`

`src/MiniPair.sol:58-77`:

1. Read both balances; `amount = balance − reserve` is what arrived since the last update.
2. Compute shares (formulas in [03 Math](03-math.md#lp-shares)).
3. `require(shares > 0)` → else `MiniPair: INSUFFICIENT_LIQUIDITY_MINTED`.
4. Credit `sharesOf[to]` and `totalShares`, `_update` the reserves, emit `Mint`.

`mint` does not care who sent the tokens; whoever calls `mint` gets shares for every token that is
in the pair but not yet in the reserves.

### Depositing off the ratio

For later deposits the pair takes the **smaller** of the two share counts. If you deposit more of
one token than the pool ratio, the extra stays in the pair without shares — it is a gift to all
current LPs. Example in the WETH/USDC pool (2,000 USDC per WETH): depositing 1 WETH + 3,000 USDC
mints shares for 1 WETH + 2,000 USDC; the other 1,000 USDC is added to the pool and split across all shares, so the depositor gets back only its small fraction of it.

Uniswap's router avoids this by computing the optimal amounts first; `MiniRouter` does not
(see [10 Differences](10-differences-from-uniswap-v2.md)).

## Removing liquidity

`pair.burn(shares, to)` (`src/MiniPair.sol:80-95`). The LP calls the pair directly; the router has
no remove function.

1. `require(sharesOf[msg.sender] >= shares)` → else `MiniPair: INSUFFICIENT_SHARES`.
2. `amount = shares × balance / totalShares` for each token — **balance**, not reserve, so tokens
   sent to the pair without `mint` are paid out too.
3. `require(amount0 > 0 && amount1 > 0)` → else `MiniPair: INSUFFICIENT_LIQUIDITY_BURNED`.
4. Reduce shares, transfer both tokens to `to`, `_update`, emit `Burn`.

## How LPs earn

There is no fee transfer to LPs and no claim function. The 0.3% fee of every swap simply stays in
the pair (see [03 Math](03-math.md#the-invariant)), so every share is backed by more tokens over
time. An LP earns by burning shares later.

`test_09_RoundTripFeesStayWithLP` shows it end to end:

| | WETH | USDC |
| --- | ---: | ---: |
| LP deposited | 1,000 | 2,000,000 |
| Bob's loss after 5 round trips of 10,000 USDC | — | 294.5530 |
| LP withdraws (burns all shares) | 1,000.0000 | 2,000,294.5530 |

The WETH side is exactly unchanged because every WETH Bob took he sold back; the whole fee ended
up on the USDC side.

---

← [03 Math](03-math.md) · [Index](README.md) · [05 Multi-hop and flash swaps](05-multihop-and-flash-swaps.md) →
