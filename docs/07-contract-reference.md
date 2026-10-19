# 07 · Contract reference

← [06 Security](06-security.md) · [Index](README.md) · [08 Tests](08-tests.md) →

Every external and public function. Amounts are in the token's smallest unit (all tokens here have
18 decimals).

## `MiniPair` — `src/MiniPair.sol`

### `constructor(address tokenA, address tokenB)`

Sorts the two addresses: the smaller becomes `token0`. Called by `MiniFactory.createPair`.

### `getReserves() → (uint256 reserve0, uint256 reserve1)`

The reserves recorded by the last `mint`, `burn`, or `swap`.

### `mint(address to) → uint256 shares`

Mints shares for the tokens that arrived since the last update (`balance − reserve`). Send both
tokens to the pair first, in the same transaction.

| | |
| --- | --- |
| Modifier | `lock` |
| Reverts | `MiniPair: LOCKED`, `MiniPair: INSUFFICIENT_LIQUIDITY_MINTED` (0 shares), arithmetic underflow if a balance is below its reserve |
| Events | `Sync(reserve0, reserve1)`, `Mint(to, amount0, amount1, shares)` |

### `burn(uint256 shares, address to) → (uint256 amount0, uint256 amount1)`

Burns `shares` of `msg.sender` and sends `shares × balance / totalShares` of each token to `to`.

| | |
| --- | --- |
| Modifier | `lock` |
| Reverts | `MiniPair: LOCKED`, `MiniPair: INSUFFICIENT_SHARES`, `MiniPair: INSUFFICIENT_LIQUIDITY_BURNED` (an amount rounds to 0), `MiniPair: TRANSFER_FAILED` |
| Events | `Transfer` × 2 (tokens), `Sync`, `Burn(msg.sender, to, amount0, amount1, shares)` |

### `swap(uint256 amount0Out, uint256 amount1Out, address to, bytes data)`

Sends the requested output to `to`, optionally calls `IMiniCallee(to).miniCall(msg.sender,
amount0Out, amount1Out, data)` when `data` is not empty, then measures the input and checks `K`.

| Parameter | Meaning |
| --- | --- |
| `amount0Out`, `amount1Out` | how much of each token to send out; usually one is 0 |
| `to` | receiver of the output; also the callback target for a flash swap |
| `data` | empty for a normal swap; any non-empty bytes trigger the callback |

| Revert | When |
| --- | --- |
| `MiniPair: LOCKED` | called again while a `mint`/`burn`/`swap` is running |
| `MiniPair: INSUFFICIENT_OUTPUT_AMOUNT` | both outputs are 0 |
| `MiniPair: INSUFFICIENT_LIQUIDITY` | an output is ≥ its reserve |
| `MiniPair: INVALID_TO` | `to` is `token0` or `token1` |
| `MiniPair: TRANSFER_FAILED` | a token transfer returned `false` |
| `MiniPair: INSUFFICIENT_INPUT_AMOUNT` | nothing arrived |
| `MiniPair: K` | the input is too small for the output, after the 0.3% fee |

Events: `Transfer` (output), `Sync`, `Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to)`.

### Public state

`token0()`, `token1()`, `reserve0()`, `reserve1()`, `totalShares()`, `sharesOf(address)`.

### `IMiniCallee.miniCall(address sender, uint256 amount0, uint256 amount1, bytes data)`

Implemented by flash swap receivers. Must pay the pair back before returning. See
[05 Multi-hop and flash swaps](05-multihop-and-flash-swaps.md#the-receiver).

## `MiniFactory` — `src/MiniFactory.sol`

### `createPair(address tokenA, address tokenB) → address pair`

Deploys a `MiniPair` and stores it under both `getPair[tokenA][tokenB]` and `getPair[tokenB][tokenA]`.

| | |
| --- | --- |
| Reverts | `MiniFactory: IDENTICAL_ADDRESSES`, `MiniFactory: PAIR_EXISTS` |
| Events | `PairCreated(token0, token1, pair)` |

Anyone can call it. `MiniRouter.addLiquidity` calls it when the pair is missing.

### Public state

`getPair(address, address) → address` (zero address if none), `allPairs(uint256) → address`.

## `MiniRouter` — `src/MiniRouter.sol`

### `getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) → uint256` (pure)

`amountIn × 997 × reserveOut / (reserveIn × 1000 + amountIn × 997)`.
Reverts `MiniRouter: INSUFFICIENT_INPUT_AMOUNT` (0 input) or `MiniRouter: INSUFFICIENT_LIQUIDITY`
(a reserve is 0).

### `getAmountsOut(uint256 amountIn, address[] path) → uint256[] amounts` (view)

`amounts[0] = amountIn`, `amounts[i + 1]` = output of hop `i` from current reserves.
Reverts `MiniRouter: INVALID_PATH` (fewer than 2 tokens), `MiniRouter: NO_PAIR`.

### `getReserves(address tokenA, address tokenB) → (uint256 reserveA, uint256 reserveB)` (view)

The pair's reserves in the order of the arguments, not token0/token1. Reverts `MiniRouter: NO_PAIR`.

### `addLiquidity(address tokenA, address tokenB, uint256 amountA, uint256 amountB, address to) → uint256 shares`

Creates the pair if needed, `transferFrom`s both amounts from the caller to the pair, calls
`pair.mint(to)`. The amounts are used as given.

Requires approvals of both tokens to the router. Reverts with the token's errors, `MiniRouter:
TRANSFER_FROM_FAILED`, or the pair's `mint` errors.

### `swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, address[] path, address to, uint256 deadline) → uint256[] amounts`

| Parameter | Meaning |
| --- | --- |
| `amountIn` | exact amount of `path[0]` to sell |
| `amountOutMin` | minimum of the last token to receive, computed off-chain |
| `path` | tokens to go through; a pair must exist for each neighbour |
| `to` | receiver of the last token |
| `deadline` | last `block.timestamp` at which the swap may run |

| Revert | When |
| --- | --- |
| `MiniRouter: EXPIRED` | `block.timestamp > deadline` |
| `MiniRouter: INVALID_PATH`, `MiniRouter: NO_PAIR` | bad path |
| `MiniRouter: INSUFFICIENT_OUTPUT_AMOUNT` | computed output < `amountOutMin` |
| `Token: allowance`, `Token: balance` | the caller did not approve enough or does not have the tokens |
| any `MiniPair` error | from a hop |

Returns the amount of every hop, the same shape as `getAmountsOut`.

## `Token` — `src/Token.sol`

Standard ERC-20 surface: `name`, `symbol`, `decimals` (18), `totalSupply`, `balanceOf`,
`allowance`, `approve`, `transfer`, `transferFrom`, events `Transfer` and `Approval`.

| Detail | Behaviour |
| --- | --- |
| `mint(address to, uint256 amount)` | anyone can mint; emits `Transfer(0x0, to, amount)` |
| `transferFrom` with allowance `type(uint256).max` | the allowance is not reduced |
| Errors | `Token: allowance`, `Token: balance` |

---

← [06 Security](06-security.md) · [Index](README.md) · [08 Tests](08-tests.md) →
