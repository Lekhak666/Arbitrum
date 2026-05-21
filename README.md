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
