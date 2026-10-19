# 09 · Local playground

← [08 Tests](08-tests.md) · [Index](README.md) · [10 Differences from Uniswap v2](10-differences-from-uniswap-v2.md) →

Deploy the WETH/USDC pool to a local anvil node and swap by hand, the way a wallet would.

## 1. Start anvil

```bash
anvil
```

It prints ten test accounts and their private keys. The steps below use account `(0)`.

## 2. Deploy

```bash
export PRIVATE_KEY=<private key (0) from the anvil output>
forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
```

`script/Deploy.s.sol` deploys `USDC`, `WETH`, the factory, and the router; mints 2,010,000 USDC and
1,000 WETH to the deployer; adds 1,000 WETH + 2,000,000 USDC of liquidity. The deployer is the LP
and keeps 10,000 USDC to swap with.

On a fresh anvil the addresses are always the same (they depend only on the deployer and its
nonce):

```bash
RPC=http://127.0.0.1:8545
ME=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
USDC=0x5FbDB2315678afecb367f032d93F642f64180aa3
WETH=0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
FACTORY=0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
ROUTER=0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9
PAIR=0x75537828f2ce51be7289709686A69CbFDbB714F1
```

Restarting anvil resets the chain; deploy again.

## 3. Read the pool

```bash
cast call $PAIR 'token0()(address)' --rpc-url $RPC                  # USDC
cast call $PAIR 'getReserves()(uint256,uint256)' --rpc-url $RPC     # 2000000e18, 1000e18
cast call $PAIR 'sharesOf(address)(uint256)' $ME --rpc-url $RPC
```

Here USDC has the smaller address, so `reserve0` is USDC.

## 4. Quote

```bash
cast call $ROUTER 'getAmountsOut(uint256,address[])(uint256[])' 1000ether "[$USDC,$WETH]" --rpc-url $RPC
# [1000000000000000000000, 498251621566649025]   → 0.4982 WETH
```

`1000ether` is `cast` shorthand for `1000 × 10^18`.

## 5. Approve and swap

```bash
cast send $USDC 'approve(address,uint256)' $ROUTER 1000ether --private-key $PRIVATE_KEY --rpc-url $RPC

DEADLINE=$(( $(cast block --field timestamp --rpc-url $RPC) + 1200 ))
cast send $ROUTER 'swapExactTokensForTokens(uint256,uint256,address[],address,uint256)' \
  1000ether 0.4957ether "[$USDC,$WETH]" $ME $DEADLINE \
  --private-key $PRIVATE_KEY --rpc-url $RPC

cast call $WETH 'balanceOf(address)(uint256)' $ME --rpc-url $RPC   # 498251621566649025
```

## 6. Look inside the transaction

```bash
cast run <tx hash> --rpc-url $RPC
```

The trace shows the router and pair calls in order:

```
MiniRouter::swapExactTokensForTokens(...)
├─ MiniFactory::getPair            [staticcall]
├─ MiniPair::getReserves           [staticcall]
├─ MiniPair::token0                [staticcall]
├─ USDC::transferFrom(me → pair, 1000e18)
├─ MiniPair::swap(0, 498251621566649025, me, 0x)
│  ├─ WETH::transfer(pair → me, 0.4982e18)
│  ├─ USDC::balanceOf(pair) → 2001000e18
│  ├─ WETH::balanceOf(pair) → 999.5017e18
│  ├─ emit Sync(...)
│  └─ emit Swap(...)
```

The logs in the receipt, with their topic hashes:

| Emitter | Event | `topics[0]` |
| --- | --- | --- |
| USDC | `Transfer(address,address,uint256)` | `0xddf252ad…` |
| WETH | `Transfer(address,address,uint256)` | `0xddf252ad…` |
| pair | `Sync(uint256,uint256)` | `0xcf2aa508…` |
| pair | `Swap(address,uint256,uint256,uint256,uint256,address)` | `0xd78ad95f…` |

```bash
cast receipt <tx hash> --rpc-url $RPC
cast sig-event 'Swap(address,uint256,uint256,uint256,uint256,address)'
```

## 7. Try a failure

```bash
# amountOutMin above the quote → MiniRouter: INSUFFICIENT_OUTPUT_AMOUNT
cast send $ROUTER 'swapExactTokensForTokens(uint256,uint256,address[],address,uint256)' \
  100ether 1ether "[$USDC,$WETH]" $ME $DEADLINE --private-key $PRIVATE_KEY --rpc-url $RPC

# deadline in the past → MiniRouter: EXPIRED
cast send $ROUTER 'swapExactTokensForTokens(uint256,uint256,address[],address,uint256)' \
  100ether 0 "[$USDC,$WETH]" $ME 1 --private-key $PRIVATE_KEY --rpc-url $RPC
```

Both checks run before the router pulls any tokens, so neither needs an allowance.

---

← [08 Tests](08-tests.md) · [Index](README.md) · [10 Differences from Uniswap v2](10-differences-from-uniswap-v2.md) →
