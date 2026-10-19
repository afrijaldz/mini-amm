# 06 · Security notes

← [05 Multi-hop and flash swaps](05-multihop-and-flash-swaps.md) · [Index](README.md) · [07 Contract reference](07-contract-reference.md) →

`mini-amm` is for learning. **Do not deploy it to a real network.** This page lists what protects
the user and the pool, and the known weak points.

## What protects the user

| Protection | Where | Stops | Test |
| --- | --- | --- | --- |
| `amountOutMin` | `src/MiniRouter.sol:80` | receiving less than you accepted — price moved, sandwich | `test_04`, `test_13` |
| `deadline` | `src/MiniRouter.sol:20-23` | a transaction held back and executed later at a worse price | `test_03` |
| one-transaction transfer + swap | `src/MiniRouter.sol:82-83` | someone else claiming the tokens you sent to the pair | `test_07` (shows the failure) |
| exact `approve` amount | the user's choice | a later bug or key leak in the router draining the whole balance | — |

### `amountOutMin` must be computed off-chain

Computing it inside the transaction from the same pool's reserves protects nothing: the reserves
are already moved by the attacker when your transaction runs. The wallet must quote **before**
signing. (The `swap` project next to this one measures the same effect against real Uniswap v2 on
a mainnet fork.)

### Sandwich

`test_13_Sandwich`: the attacker buys 200,000 USDC of WETH right before Alice's 10,000 USDC buy,
then sells right after.

| Alice's `amountOutMin` | Alice gets | Attacker |
| --- | ---: | ---: |
| 0 | 4.1023 WETH (instead of 4.9602, −17.3%) | +637.58 USDC |
| quote − 0.5% | transaction reverts | front-run without a victim (in the test it still holds the WETH; in practice attackers bundle the three transactions so the attack is not executed at all) |

Slippage tolerance is the most an attacker can take from you. Smaller is safer; too small and
normal price movement makes swaps fail.

## What protects the pool

| Protection | Where | Stops |
| --- | --- | --- |
| `K` check after measuring balances | `src/MiniPair.sol:112-121` | taking more than the formula allows, by any caller, in any order of transfers |
| measuring input from balances | `src/MiniPair.sol:114-115` | a caller claiming an input it never sent (there is no `amountIn` parameter to lie with) |
| `lock` modifier | `src/MiniPair.sol:41-46` | re-entering `swap`, `mint`, or `burn` from the flash swap callback |
| `to != token0 && to != token1` | `src/MiniPair.sol:102` | sending output to a token contract |
| Solidity 0.8 checked math | everywhere | silent overflow in the `K` product |

### Why `lock` matters here

`swap` reads `reserve0` / `reserve1` from **storage** after the callback (lines 114-121). A nested
call that changed the reserves during `miniCall` would change the numbers the outer check compares
against. `lock` makes any nested `swap`, `mint`, or `burn` revert with `MiniPair: LOCKED`.
Uniswap v2 has the same lock **and** copies the reserves into local variables at the start of
`swap`. Exploring what happens without the lock is exercise 4 in [11 Exercises](11-exercises.md).

## Known weak points

### Tokens sent in a separate transaction are up for grabs

The pair counts "balance − reserve" as input for whoever calls `swap` or `mint` next. If you send
tokens to the pair and stop, anyone can take them (`test_07`: Bob receives the WETH for Alice's
1,000 USDC). Always transfer and call in the same transaction — through the router or your own
contract.

### First-depositor share inflation

There is no `MINIMUM_LIQUIDITY`. Shares round down. An attacker can create a pool with a tiny
deposit (very few shares), then send a large amount directly to the pair. One share is now worth a
lot, and a later depositor whose deposit is not a whole multiple of a share's value loses the
remainder to rounding — or gets 0 shares and reverts with `INSUFFICIENT_LIQUIDITY_MINTED`.
Uniswap v2 locks the first 1,000 shares forever to make this expensive.

### Fee-on-transfer and rebasing tokens

The router quotes on the full `amountIn`, but a token that takes a fee on transfer delivers less to
the pair. The `K` check then fails and the swap reverts. Uniswap v2 has separate
`...SupportingFeeOnTransferTokens` functions that measure the pair's balance instead; `MiniRouter`
does not. Rebasing tokens change balances without transfers, which makes "balance − reserve"
meaningless.

### Tokens that do not return `bool`

`Token` returns `true`. Tokens such as USDT on Ethereum return nothing; `require(token.transfer(...))`
would revert when decoding. Uniswap uses a low-level call that accepts both.

### No price oracle

The pair has no TWAP accumulator. Its spot price can be moved inside one transaction (a flash swap
or a large swap), so reading `getReserves()` as a price in another contract is unsafe.

### `Token.mint` is open

Anyone can mint any amount. This is only for tests and the playground.

---

← [05 Multi-hop and flash swaps](05-multihop-and-flash-swaps.md) · [Index](README.md) · [07 Contract reference](07-contract-reference.md) →
