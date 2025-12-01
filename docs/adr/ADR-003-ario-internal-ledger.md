# ADR-003: ARIO Internal Ledger Pattern

## Status

Accepted

## Context

The ARNS Marketplace facilitates trading of ANT tokens for ARIO tokens. In a naive implementation, every ARIO transaction would require an external transfer via the ARIO token process:

1. User places bid → Transfer ARIO to marketplace
2. User gets outbid → Transfer ARIO back to user
3. User places new bid → Transfer ARIO to marketplace again
4. Auction settles → Transfer ARIO to seller

This creates severe inefficiencies:

- **High Message Costs**: Each transfer requires 2+ messages (Transfer + Credit-Notice/Debit-Notice)
- **Latency**: External transfers add round-trip delays
- **Complexity**: Intent tracking required for every ARIO movement
- **Poor UX**: Users wait for confirmations on routine operations
- **Gas Waste**: Unnecessary cross-process messages for internal accounting

Real-world example: An English auction with 10 bids would generate ~40 messages if using external transfers:
- Bid 1: Transfer in (2 messages)
- Bid 2: Transfer in + refund bid 1 (4 messages total)
- Bid 3: Transfer in + refund bid 2 (4 messages total)
- ... continues ...
- Settlement: Transfer to seller + Transfer to winner (4 messages)

Total: ~40 messages vs ~6 messages with internal ledger

The marketplace needs an efficient mechanism to handle ARIO within its boundaries while maintaining security and allowing users to withdraw at any time.

## Decision

We will implement an **ARIO Internal Ledger** pattern that maintains an internal balance sheet for ARIO tokens within the marketplace process. This ledger:

1. **Tracks both available and locked balances** per user per order
2. **Uses deposits and withdrawals** as boundary operations with the external ARIO process
3. **Handles all internal operations synchronously** (bids, trades, fees) without external transfers
4. **Locks balances** in active orders to prevent double-spending
5. **Replaces multiple old globals** with a unified data structure

### Data Structure

```lua
-- Global in globals.lua
ARIOBalances = ARIOBalances or {}
```

Structure per user:

```lua
ARIOBalances[address] = {
    balance = '0',        -- Available balance (string integer in mARIO)
    orders = {            -- Locked balance per order
        [orderId] = '1000000000',  -- Amount locked in this order
        -- ... more orders
    }
}
```

**Key Properties**:
- **Available balance** (`balance`): Can be used for new bids/orders or withdrawn
- **Locked balance** (`orders[orderId]`): Reserved for specific order, cannot be used elsewhere
- **Total balance**: Sum of available + all locked amounts
- **String integers**: All amounts stored as strings for bint (256-bit integer) compatibility

### Unified Structure Benefits

This single structure replaces four previous globals:

```lua
-- OLD (before ADR-003):
ARIOBalances = {}              -- Just available balance
EnglishAuctionBalances = {}    -- Auction bids
OrderLockedBalances = {}       -- Buy order locks
UserOrdersIndex = {}           -- Reverse lookup

-- NEW (after ADR-003):
ARIOBalances = {               -- Everything in one place
    [address] = {
        balance = "...",       -- Available
        orders = { ... }       -- All locks by orderId
    }
}
```

**Advantages**:
- O(1) lookup for user's total involvement
- Simpler memory management
- Easier to query user's full position
- Atomic operations on single data structure

### Deposit Flow

Users deposit ARIO via Credit-Notice with `X-Action: Deposit`:

```lua
-- In notices.lua
if msg.Tags['X-Action'] == constants.ACTIONS.DEPOSIT then
    local isArioNotice = _utils.isArioToken(msg.From)
    assert(isArioNotice, "Deposit must be from ARIO")
    balances.handleDeposit(msg)
    return
end

-- In balances.lua
function balances.handleDeposit(msg)
    local sender = msg.Tags.Sender
    local quantity = msg.Tags.Quantity
    balances.increaseBalance(sender, quantity)
    _utils.Send(msg, { 
        Target = sender, 
        Action = "Deposit-Notice", 
        Data = json.encode(quantity) 
    })
end
```

**Flow**:
1. User sends `Transfer` to ARIO process with marketplace as recipient
2. ARIO process sends `Credit-Notice` to marketplace with `X-Action: Deposit`
3. Marketplace increases user's available balance
4. Marketplace sends `Deposit-Notice` confirmation to user

**No intent tracking required** - deposits are synchronous within the Credit-Notice handler.

### Withdrawal Flow

Users withdraw ARIO via direct message to marketplace:

```lua
-- Handler: Withdraw-Ario
function balances.withdrawArioHandler(msg)
    local account = msg.From
    local quantity = msg.Tags.Quantity
    local recipient = msg.Tags.Recipient or account
    
    assert(quantity and _utils.checkValidAmount(quantity), "Invalid quantity")
    assert(balances.walletHasSufficientBalance(account, quantity), "Insufficient balance")
    
    balances.reduceBalance(account, quantity)
    ucm.transfer(recipient, quantity, ARIO_TOKEN_PROCESS_ID, msg)
    
    return json.encode({
        Status = 'Success',
        Message = 'ARIO withdrawal initiated',
        Quantity = quantity,
        Recipient = recipient,
    })
end
```

**Flow**:
1. User sends `Withdraw-Ario` message to marketplace with `Quantity` tag
2. Marketplace reduces user's available balance immediately
3. Marketplace sends `Transfer` to ARIO process
4. ARIO process sends `Debit-Notice` to marketplace (informational only)

**No intent tracking required** - withdrawals use `ucm.transfer()` (not `ucm.transferWithIntent()`) because ARIO withdrawals don't need completion tracking. The balance is deducted immediately and the transfer is fire-and-forget.

**Rationale**: If ARIO transfer fails, it's an ARIO process issue, not a marketplace concern. Users can retry withdrawal.

### Balance Locking for Orders

When users create ARIO-dominant orders (buying ANT with ARIO) or place bids, their ARIO is locked:

```lua
function balances.lockBalanceForOrder(orderId, user, qty)
    assert(balances.walletHasSufficientBalance(user, qty), "Insufficient balance to lock")
    
    balances.ensureAccountExists(user)
    
    -- Reduce from available balance
    balances.reduceBalance(user, qty)
    
    -- Add to locked orders
    local prevLocked = ARIOBalances[user].orders[orderId] or '0'
    ARIOBalances[user].orders[orderId] = tostring(bint(prevLocked) + bint(qty))
end
```

**When balances are locked**:
- Placing a bid on an English auction
- Creating a buy order with internal ARIO balance
- Replacing a lower bid (delta is locked, old bid unlocked)

**Locked balance properties**:
- Cannot be used for other orders
- Cannot be withdrawn
- Shown separately in balance queries
- Automatically unlocked on order completion/cancellation/expiration

### Balance Unlocking

Balances are unlocked when orders complete, cancel, or expire:

```lua
function balances.unlockBalanceFromOrder(orderId, user, recipient, qty)
    assert(type(orderId) == "string", "OrderId is required!")
    assert(type(user) == "string", "User is required!")
    assert(type(recipient) == "string", "Recipient is required!")
    assert(bint(qty) > 0, "Quantity must be greater than 0")
    
    balances.ensureAccountExists(user)
    
    -- Check locked balance exists
    local lockedBalance = ARIOBalances[user].orders[orderId] or '0'
    assert(bint(lockedBalance) >= bint(qty), "Insufficient locked balance")
    
    -- Reduce from locked balance
    local newLockedBalance = bint(lockedBalance) - bint(qty)
    if newLockedBalance == bint(0) then
        ARIOBalances[user].orders[orderId] = nil
    else
        ARIOBalances[user].orders[orderId] = tostring(newLockedBalance)
    end
    
    -- Add to recipient's available balance
    balances.increaseBalance(recipient, qty)
end
```

**Unlock scenarios**:
- **Order cancelled**: User gets their locked ARIO back
- **Auction settled**: Winner's ARIO goes to seller, losers get ARIO back
- **Bid replaced**: Previous bidder gets ARIO back
- **Order expires**: Creator gets locked ARIO back

**Note**: `recipient` parameter allows unlocking to a different user (e.g., auction winner's ARIO going to seller).

### Internal Transfers

ARIO moves between users within the marketplace without external transfers:

```lua
function balances.transfer(recipient, from, qty, allowUnsafeAddresses)
    assert(_utils.isValidAOAddress(recipient, allowUnsafeAddresses), "Invalid recipient")
    assert(from ~= recipient, "Cannot transfer to self")
    assert(bint(qty) > 0, "Quantity must be greater than 0")
    
    balances.reduceBalance(from, qty)
    balances.increaseBalance(recipient, qty)
    
    return {
        [from] = balances.getBalance(from),
        [recipient] = balances.getBalance(recipient),
    }
end
```

**Use cases**:
- Buyer pays seller (ARIO buy order fills ANT sell order)
- Treasury collects fees
- Auction settlement (winner → seller)

**Performance**: O(1) operations, purely internal state updates.

### ARIO Order Creation Blocking

To enforce internal ledger usage, ARIO Credit-Notices with order creation are blocked:

```lua
-- In notices.lua Credit-Notice handler
if msg.Tags['X-Order-Action'] == 'Create-Order' and _utils.isArioToken(msg.From) then
    handleInvalidTransfer('ARIO orders must use internal balance - deposit ARIO first, then call Create-Order')
    return
end
```

This forces the two-step flow:
1. Deposit ARIO (via Credit-Notice with `X-Action: Deposit`)
2. Create order (via direct message using internal balance)

**Rationale**: Prevents users from bypassing the internal ledger and maintains consistency.

### Balance Queries

Users can query their balance breakdown:

```lua
function balances.getBalanceHandler(msg)
    local target = msg.Tags.Target or msg.Tags.Address or msg.From
    local available = balances.getBalance(target)
    local locked = balances.getUserTotalLockedBalance(target)
    local total = bint(available) + bint(locked)
    
    balances.ensureAccountExists(target)
    
    return json.encode({
        address = target,
        balance = available,           -- Available for new orders/withdrawal
        lockedBalance = locked,         -- Total locked across all orders
        totalBalance = tostring(total), -- Available + locked
        orders = ARIOBalances[target].orders or {}, -- Per-order breakdown
    })
end
```

**Response example**:

```json
{
  "address": "user-abc...",
  "balance": "5000000000",           // 5 ARIO available
  "lockedBalance": "3000000000",     // 3 ARIO locked
  "totalBalance": "8000000000",      // 8 ARIO total
  "orders": {
    "order-1": "1000000000",         // 1 ARIO locked in order-1
    "order-2": "2000000000"          // 2 ARIO locked in order-2
  }
}
```

This transparency helps users understand where their ARIO is allocated.

## Cranking Requirements

**None required** - The internal ledger pattern is purely synchronous.

- **Trigger**: Direct user messages (Create-Order, Bid-On-English-Auction, Withdraw-Ario)
- **Execution**: Immediate state updates within handler
- **Performance**: O(1) for individual operations
- **Cost**: Pay-per-use (only when user initiates action)

All balance operations (lock, unlock, transfer, deposit, withdraw) complete within a single message handler with no deferred processing.

**Contrast with ANT transfers**: ANT transfers require intent tracking and asynchronous resolution (see ADR-004), while ARIO operations are synchronous because the ledger is internal to the marketplace process.

## Consequences

### Positive

1. **Gas Efficiency**: Eliminates ~75% of messages for multi-bid auctions
2. **Instant Operations**: No waiting for external transfer confirmations
3. **Simple Intent Model**: ARIO doesn't need intent tracking (only ANTs do)
4. **Atomic Bids**: Bid locking happens instantly without race conditions
5. **Clear Accounting**: Users see available vs locked balance breakdown
6. **Unified Structure**: Single data structure simplifies implementation
7. **Security**: Balance locking prevents double-spending
8. **Auditability**: All operations traceable within marketplace state
9. **UX**: Fast response times for bids and trades

### Negative

1. **Centralization Risk**: Marketplace holds user funds (trust requirement)
2. **Liquidity Lock-in**: ARIO locked in marketplace can't be used elsewhere
3. **Exit Dependency**: Users depend on marketplace availability to withdraw
4. **State Bloat**: Large user base accumulates balance state
5. **Recovery Risk**: Marketplace bugs could affect many users' funds
6. **Withdrawal Friction**: Two-step process (deposit → trade → withdraw)
7. **Trust Model**: Users must trust marketplace won't mismanage funds

### Neutral

1. **Boundary Operations**: Deposits/withdrawals still require external transfers
2. **ARIO-Specific**: Pattern only applies to ARIO, not ANTs
3. **No Interest**: Deposited ARIO doesn't earn yield
4. **State Size**: Balance state grows linearly with users
5. **Withdrawal Timing**: Withdrawals are fire-and-forget (no confirmation wait)

## Alternatives Considered

### 1. External Transfers Per Trade

Use external ARIO transfers for every trade operation.

**Rejected because**:
- High message costs (2-4 messages per operation)
- Poor latency (waiting for transfer confirmations)
- Requires intent tracking for every ARIO movement
- Bad UX for frequent traders (especially auction bidders)
- Significantly higher gas costs

### 2. Allowance Model

Use ERC-20 style allowances where users approve marketplace to pull ARIO.

**Rejected because**:
- Not standard in AO ecosystem
- Still requires external transfer per operation
- Adds approval step (worse UX)
- Doesn't reduce message count
- More complex error handling

### 3. Escrow Contract

Use separate escrow contract to hold user funds.

**Rejected because**:
- Additional contract deployment and complexity
- Still requires deposits/withdrawals to escrow
- Doesn't improve message efficiency
- Adds another trust boundary
- No clear benefit over internal ledger

### 4. Lazy Withdrawal (Virtual Balances)

Don't actually reduce balance on withdrawal, just track pending withdrawals.

**Rejected because**:
- Complicates balance accounting (available vs pending withdrawal)
- Risk of double-spending if withdrawal fails
- Harder to reason about user's actual balance
- Adds complexity without clear benefit

### 5. Batch Settlements

Accumulate trades and settle in batches periodically.

**Rejected because**:
- Adds latency (users wait for batch)
- Complicates real-time balance queries
- Doesn't match AO's message-per-action model
- Hard to handle failures in batch

### 6. Off-Chain Balance Tracking

Track balances off-chain and settle on-chain periodically.

**Rejected because**:
- Defeats purpose of on-chain marketplace
- Centralization (who tracks off-chain state?)
- Trust issues (off-chain data can be manipulated)
- Not compatible with AO's process model

## Implementation Notes

### Account Initialization

Accounts are created lazily on first interaction:

```lua
function balances.ensureAccountExists(address)
    if not ARIOBalances[address] then
        ARIOBalances[address] = {
            balance = '0',
            orders = {}
        }
    end
end
```

This is called before any balance operation to ensure the account structure exists.

### Balance Arithmetic

All balance operations use bint (256-bit integers) for safety:

```lua
local bint = require('.bint')(256)

-- Increase balance
function balances.increaseBalance(target, qty)
    assert(bint(qty) > 0, "Quantity must be greater than 0")
    
    balances.ensureAccountExists(target)
    local prevBalance = balances.getBalance(target)
    ARIOBalances[target].balance = tostring(bint(prevBalance) + bint(qty))
end

-- Reduce balance
function balances.reduceBalance(target, qty)
    assert(balances.walletHasSufficientBalance(target, qty), "Insufficient balance")
    assert(bint(qty) > 0, "Quantity must be greater than 0")
    
    balances.ensureAccountExists(target)
    local prevBalance = balances.getBalance(target)
    ARIOBalances[target].balance = tostring(bint(prevBalance) - bint(qty))
end
```

**Important**: Balances are stored as strings but computed as bint to handle large numbers safely.

### Total Locked Balance

To get a user's total locked balance across all orders:

```lua
function balances.getUserTotalLockedBalance(user)
    if not ARIOBalances[user] or not ARIOBalances[user].orders then
        return '0'
    end
    
    local total = bint(0)
    for _, amount in pairs(ARIOBalances[user].orders) do
        total = total + bint(amount)
    end
    
    return tostring(total)
end
```

This iterates through all orders for the user, summing locked amounts.

### Fee Collection

Marketplace fees are added to the treasury's internal balance:

```lua
-- In utils.lua
function utils.accrueFee(amount)
    local balances = require('balances')
    balances.increaseBalance(TREASURY_ADDRESS, amount)
    
    -- Also track in AccruedFeesAmount for withdrawal tracking
    AccruedFeesAmount = tostring(bint(AccruedFeesAmount) + bint(amount))
end
```

The treasury can withdraw fees using the standard withdrawal mechanism.

### English Auction Bid Handling

When a user places a bid on an English auction:

```lua
-- In english_auction.lua
function english_auction.bidOnEnglishAuctionHandler(msg)
    local orderId = msg.Tags['Order-Id']
    local bidAmount = msg.Tags['Bid-Amount']
    local bidder = msg.From
    
    -- Validate bid amount
    -- ... validation logic ...
    
    -- Calculate delta (how much more to lock)
    local currentBid = balances.getOrderLockedBalance(orderId, bidder)
    local delta = bint(bidAmount) - bint(currentBid)
    
    if delta > bint(0) then
        -- Lock additional ARIO for this bid
        balances.lockBalanceForOrder(orderId, bidder, tostring(delta))
    end
    
    -- If this user is replacing their own bid, delta might be 0 (no-op)
    -- If another user had highest bid, refund them (handled in update logic)
end
```

**Delta calculation** is critical: users only lock the *difference* between their current bid and new bid, not the full amount again.

### Bid Replacement and Refunds

When a new highest bid is placed, the previous bidder gets their ARIO back:

```lua
-- If there's a previous highest bidder (and it's not the same bidder)
if order.highestBidder and order.highestBidder ~= bidder then
    local previousBidAmount = order.highestBid
    
    -- Unlock previous bidder's ARIO back to their available balance
    balances.unlockBalanceFromOrder(
        orderId, 
        order.highestBidder,    -- user who locked it
        order.highestBidder,    -- recipient (same user)
        previousBidAmount       -- amount to unlock
    )
    
    -- Send notification to previous bidder
    _utils.Send(msg, {
        Target = order.highestBidder,
        Action = 'Bid-Returned',
        ['Order-Id'] = orderId,
        ['Returned-Amount'] = previousBidAmount,
    })
end
```

This happens synchronously within the bid handler - no external transfers needed.

### Migration from Old Globals

The implementation migrated from multiple globals to the unified structure:

**Before**:
```lua
ARIOBalances = { ["user1"] = "1000000000" }
EnglishAuctionBalances = { ["order1"] = { ["user1"] = "500000000" } }
OrderLockedBalances = { ["order2"] = { ["user1"] = "300000000" } }
UserOrdersIndex = { ["user1"] = { "order1", "order2" } }
```

**After**:
```lua
ARIOBalances = {
    ["user1"] = {
        balance = "200000000",  -- 1000000000 - 500000000 - 300000000
        orders = {
            ["order1"] = "500000000",
            ["order2"] = "300000000"
        }
    }
}
```

This migration improved:
- Memory efficiency (one structure instead of four)
- Query performance (one lookup instead of four)
- Code clarity (single source of truth)

## References

- ARNS Marketplace Specification: `docs/spec.md`
- ADR-002: Credit Notice Pattern: `docs/ADR-002-credit-notice-pattern.md`
- ADR-004: Intent-Based Workflow Pattern: `docs/ADR-004-intent-based-workflow.md`
- Source: `src/balances.lua` - Balance management implementation
- Source: `src/notices.lua` - Deposit handling via Credit-Notice
- Source: `src/ucm.lua` - Internal transfers and order execution
- Source: `src/english_auction.lua` - Bid locking and unlocking
- Source: `src/globals.lua` - ARIOBalances global definition

## Future Considerations

1. **Interest on Deposits**: Accrual of yield on deposited ARIO balances
2. **Withdrawal Limits**: Per-user or global withdrawal limits for security
3. **Emergency Pause**: Ability to pause deposits/withdrawals in case of exploit
4. **Balance Snapshots**: Periodic snapshots for auditing and recovery
5. **Multi-Sig Withdrawals**: Require multiple signatures for large withdrawals
6. **Insurance Fund**: Reserve fund to cover potential losses from bugs
7. **Batch Withdrawals**: Allow users to withdraw from multiple accounts at once
8. **Withdrawal Queue**: Priority queue for large withdrawals during high volume
9. **Balance Staking**: Allow users to stake locked balances for additional yield
10. **Cross-Marketplace Transfers**: Allow ARIO transfers between compatible marketplaces

