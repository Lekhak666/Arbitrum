Flow:

```
User signs intent
   ↓
Commit submitted on-chain
   ↓
Reveal full intent
   ↓
Deposit ERC20 funds
   ↓
Solver watches price
   ↓
Condition met
   ↓
Solver executes on-chain swap through DEX router
   ↓
Funds sent to user
```

Local chain testing:

```
Anvil
   ↓
Deploy MockRouter
   ↓
Deploy IntentRegistry
   ↓
Test submit
   ↓
Test reveal
   ↓
Test deposit
   ↓
Trigger execute
   ↓
Verify state changes
   ↓
Only then touch testnet
```

Flow of the code:

- `IntentRegistry` contract:
  - `submitIntent`: User submits intent with parameters (tokenIn, tokenOut, amountIn, minAmountOut, deadline).
  - `revealIntent`: User reveals the full intent details on-chain.
  - `depositFunds`: User deposits the specified ERC20 tokens into the contract.
  - `executeIntent`: Solver executes the swap when conditions are met, interacting with the DEX router.
- `IRouter` interface: Defines the function for swapping tokens on a DEX.
- `IERC20` interface: Standard ERC20 functions for token interactions.
- `IOracle` interface: Function to get price data for token pairs.
- Mock contracts for testing:
- `MockRouter`: Simulates a DEX router for testing swap execution.
- `MockERC20`: Simulates an ERC20 token for testing deposits and transfers.
- `DeployIntentRegistryTest`: Unit tests for the `IntentRegistry` contract, covering the full flow from intent submission to execution.

1. constructor(\_router)

```
constructor(_router)
    │
    ├─ set ROUTER = _router
    │
    ├─ set contractOwner = msg.sender
    │
    └─ contract initialized
```

2. registerPool(tokenA, tokenB, pool)

```
registerPool(tokenA, tokenB, pool)
    │
    ├─ [Guard] msg.sender == contractOwner?
    │        └─ no → revert NotContractOwner
    │
    ├─ tokenPairPool[tokenA][tokenB] = pool
    │
    ├─ tokenPairPool[tokenB][tokenA] = pool
    │
    └─ emit PoolRegistered
```

3. submitIntent(commitmentHash, expiry)

```
submitIntent(commitmentHash, expiry)
    │
    ├─ [Guard] expiry > block.timestamp?
    │        └─ no → revert ExpiryPassed
    │
    ├─ create TradeIntent
    │      • user = msg.sender
    │      • commitmentHash stored
    │      • expiry stored
    │      • placeholders for hidden fields
    │
    ├─ store at intents[nextIntentId]
    │
    ├─ emit IntentSubmitted
    │
    └─ nextIntentId++
```

4. revealIntent(...)

```
revealIntent(...)
    │
    ├─ load intent
    │
    ├─ [Guard] msg.sender == intent.user?
    │        └─ no → revert NotIntentOwner
    │
    ├─ [Guard] already revealed?
    │        └─ yes → revert AlreadyRevealed
    │
    ├─ recompute hash from:
    │      user
    │      tokenIn
    │      tokenOut
    │      amountIn
    │      targetPrice
    │      minAmountOut
    │      greaterThan
    │      stored expiry
    │      secret
    │
    ├─ [Check] matches stored commitmentHash?
    │        └─ no → revert RevealHashMismatch
    │
    ├─ write revealed values into storage
    │
    ├─ intent.revealed = true
    │
    └─ emit IntentRevealed
```

5. depositIntentFunds(id)

```
depositIntentFunds(id)
    │
    ├─ load intent
    │
    ├─ [Guard] msg.sender == intent.user?
    │        └─ no → revert NotIntentOwner
    │
    ├─ [Guard] already deposited?
    │        └─ yes → revert AlreadyDeposited
    │
    ├─ intent.deposited = true
    │
    ├─ transferFrom(
    │      user → contract,
    │      amountIn
    │  )
    │
    ├─ [Check] transfer success?
    │        └─ no → revert TransferInDepositIntentFailed
    │
    └─ emit FundsDeposited
```

6. executeIntent(intentId)

```
executeIntent(intentId)
    │
    ├─ [Guard] revealed? executed? expired?
    │
    ├─ [Oracle] fetch TWAP tick → currentPrice
    │
    ├─ [Check] currentPrice meets greaterThan/lessThan condition?
    │
    ├─ [Effect] intent.executed = true
    │
    ├─ [Interact] approve ROUTER
    │
    ├─ swapExactTokensForTokens
    │
    ├─ revoke approval
    │
    └─ emit IntentExecuted
```

7. cancelIntent(intentId)

```
cancelIntent(intentId)
    │
    ├─ load intent
    │
    ├─ [Guard] msg.sender == owner?
    │        └─ no → revert NotIntentOwner
    │
    ├─ [Guard] already cancelled?
    │        └─ yes → revert AlreadyCancelled
    │
    ├─ [Guard] already executed?
    │        └─ yes → revert IntentAlreadyExecuted
    │
    ├─ [Check]
    │   deposited && not expired?
    │        └─ yes → revert NotYetExpired
    │
    ├─ intent.cancelled = true
    │
    ├─ deposited?
    │      ├─ yes → transfer funds back
    │      │       └─ fail → revert CancelTransferFailed
    │      │
    │      └─ no → skip refund
    │
    └─ emit IntentCancelled
```

8. getIntent(intentId)

```
getIntent(intentId)
    │
    ├─ read intents[intentId]
    │
    └─ return TradeIntent
```

Flow from a bird's eye view:

```
Owner deploys a Uniswap V3 pool for TokenA/TokenB
        ↓
Owner call registerPool(TokenA, TokenB, poolAddress)
        ↓
User reveals intent with tokenIn=TokenA, tokenOut=TokenB
        ↓
executeIntent looks up tokenPairPool[TokenA][TokenB] → finds your pool → works
```
