# AR.IO Marketplace Feature Checklist

> **Status**: ✅ All Core Features Implemented  
> **Last Updated**: 2025-11-25  
> **Test Coverage**: 345 passing tests / 0 failures / 0 pending

---

## 🏗️ Core Architecture

### ARIO Internal Ledger
- [x] **Deposit System** - Users deposit ARIO to marketplace internal balance
- [x] **Withdrawal System** - Users withdraw ARIO from internal balance (no intents)
- [x] **Internal Balance Tracking** - Available + locked balance per user per order
- [x] **Balance Locking** - Lock/unlock mechanism for bids and orders
- [x] **Credit-Notice Blocking** - ARIO Credit-Notices for orders explicitly blocked
- [x] **Direct Transfers** - ARIO withdrawals use direct transfer (no intent tracking)

### ANT Intent-Based Operations
- [x] **Intent Creation** - Parent intents for ANT listings with listing fee
- [x] **Intent Validation** - Credit-Notices require valid X-Intent-Id
- [x] **Child Intent Tracking** - All ANT transfers create child intents
- [x] **Intent Resolution** - Debit-Notices resolve child intents
- [x] **Intent Completion** - Parent intents auto-complete when all children resolve
- [x] **Intent Failure Handling** - Transfer errors cascade to parent intents
- [x] **Intent Expiration** - TTL-based intent expiration (24 hours)
- [x] **State-Notice Handler** - ANT ownership verification

### Data Structures
- [x] **ARIOBalances** - Unified balance tracking (available + locked per order)
- [x] **Intents** - Parent/child intent relationships with status tracking
- [x] **Orderbook** - Directional pairs with order dictionaries
- [x] **OrderIndex** - O(1) order lookup by ID
- [x] **Order Status** - Active, executed, cancelled, expired states

---

## 🛒 Order Types

### Fixed Price Orders
- [x] **ANT Sell Orders** - List ANT for fixed ARIO price via Credit-Notice + Intent
- [x] **ANT Buy Orders** - Buy ANT at fixed price using internal ARIO balance
- [x] **Immediate Matching** - Buy orders matched immediately with sell orders
- [x] **Partial Fills** - Not supported for ANT (whole token only)
- [x] **Excess Refunds** - Overpayment refunded to internal balance (ARIO) or via intent (ANT)
- [x] **Expiration** - Orders expire at specified time
- [x] **VWAP Tracking** - Volume-weighted average price tracking per pair

### Dutch Auction Orders
- [x] **ANT Sell Orders** - List ANT with decreasing price over time
- [x] **ANT Buy Orders** - Buy ANT at current Dutch price using internal ARIO balance
- [x] **Price Decay** - Automatic price reduction based on time intervals
- [x] **Minimum Price** - Price floor enforcement
- [x] **Immediate Settlement** - Auction settles immediately when matched
- [x] **Current Price Calculation** - Dynamic price based on elapsed time
- [x] **Excess Refunds** - Overpayment refunded appropriately

### English Auction Orders
- [x] **ANT Sell Orders** - List ANT for English auction via Credit-Notice + Intent
- [x] **Bidding System** - Place and update bids using internal ARIO balance
- [x] **Delta Calculation** - Contract-side delta calculation for bid increases
- [x] **Bid Locking** - Bids locked in internal balance until settlement
- [x] **Minimum Increment** - 1 ARIO minimum bid increment enforcement
- [x] **Highest Bid Tracking** - Real-time highest bid/bidder tracking
- [x] **Manual Settlement** - Anyone can settle expired auction with bids
- [x] **Auto Settlement** - Pruning system triggers settlement on expired auctions
- [x] **Losing Bid Returns** - All losing bids returned to internal balance at settlement
- [x] **Expiration** - Auctions expire at specified time

---

## 💰 Financial Operations

### Deposits & Withdrawals
- [x] **ARIO Deposits** - Via Credit-Notice with X-Action: Deposit
- [x] **ARIO Withdrawals** - Direct withdraw from internal balance
- [x] **Balance Queries** - Get individual or paginated balances
- [x] **Balance Breakdown** - Available, locked, and total balance reporting

### Fee System
- [x] **Listing Fees** - Duration-based fees for ANT listings (charged in ARIO from internal balance)
- [x] **Transaction Fees** - 5% fee on order matching (0.5% to treasury, 4.5% to marketplace)
- [x] **Fee Accrual** - Treasury fee tracking in internal ARIO balance
- [x] **Fee Withdrawal** - Treasury can withdraw accrued fees
- [x] **ANT Fee Handling** - ANT fees transferred externally with intent tracking

### Refunds & Error Handling
- [x] **ARIO Refunds** - Excess ARIO refunded to internal balance
- [x] **ANT Refunds** - ANT refunded via external transfer with intent
- [x] **Validation Errors** - Comprehensive validation with clear error messages
- [x] **Transfer Errors** - Transfer-Error notices cascade intent failures
- [x] **Insufficient Balance** - Proper balance checks before operations

---

## 📊 Query & Information Handlers

### Order Queries
- [x] **Get Orders** - Retrieve all orders with pagination and filtering
- [x] **Get Order** - Retrieve single order by ID
- [x] **Order Filtering** - Filter by status, type, creator, token
- [x] **Order Sorting** - Sort by price, date, quantity
- [x] **Cursor Pagination** - Efficient pagination with cursors

### Balance Queries
- [x] **Get Balance** - Retrieve single user's ARIO balance
- [x] **Get Paginated Balances** - Retrieve all balances with pagination
- [x] **Balance Breakdown** - Available vs locked balance reporting

### Intent Queries
- [x] **Get Paginated Intents** - Retrieve intents with pagination
- [x] **Get Intent By ID** - Retrieve single intent details
- [x] **Intent Filtering** - Filter by status, type, initiator
- [x] **Intent Status Tracking** - Pending, active, completed, failed states

### Marketplace Info
- [x] **Process Info** - Name, version, owner, treasury address
- [x] **ARIO Token Process ID** - Configured token address
- [x] **Accrued Fees** - Total fees collected

---

## 🔧 System Operations

### Order Lifecycle
- [x] **Order Creation** - Create orders via Credit-Notice (ANT) or direct message (ARIO)
- [x] **Order Matching** - Automatic matching for compatible orders
- [x] **Order Cancellation** - Cancel active orders (returns locked funds)
- [x] **Order Settlement** - Manual settlement for English auctions
- [x] **Order Expiration** - Automatic expiration via pruning system

### Intent Lifecycle
- [x] **Intent Creation** - Create parent intents with listing fee charge
- [x] **Intent Resolution** - Resolve intents on Credit-Notice receipt
- [x] **Child Intent Creation** - Automatic child intent creation for transfers
- [x] **Child Intent Resolution** - Resolve on Debit-Notice receipt
- [x] **Parent Completion** - Auto-complete parent when all children resolved
- [x] **Intent Failure** - Fail intents on transfer errors with cascading
- [x] **Intent Expiration** - TTL-based expiration (not yet pruned automatically)

### Pruning System
- [x] **Order Pruning** - Scheduled pruning of expired orders
- [x] **Auto Settlement** - Expired English auctions auto-settle if bids exist
- [x] **Expiration Tracking** - Next scheduled prune time tracking
- [x] **On-Demand Pruning** - Pruning triggered by message timestamps

### Token Transfers
- [x] **Internal ARIO Transfers** - Balance modifications within marketplace
- [x] **External ARIO Transfers** - Withdrawals via Transfer message (no intent)
- [x] **ANT Transfers** - All ANT transfers via Transfer message with intent tracking
- [x] **Transfer Confirmation** - Debit-Notice handling for confirmed transfers
- [x] **Transfer Errors** - Transfer-Error notice handling with intent failure

---

## 🔐 Validation & Security

### Input Validation
- [x] **Address Validation** - Arweave address format validation
- [x] **Amount Validation** - Positive integer amounts with bint support
- [x] **Token Validation** - ARIO must be in every trade pair
- [x] **Pair Validation** - Valid trading pair enforcement
- [x] **Expiration Validation** - Future timestamps with max duration (30 days)
- [x] **Price Validation** - Positive price validation for orders

### Access Control
- [x] **Sender Validation** - Message sender must match expected address
- [x] **Balance Checks** - Sufficient balance validation before operations
- [x] **Intent Authorization** - Intent initiator must match sender
- [x] **Order Ownership** - Only order creator can cancel orders
- [x] **Fee Payment** - Listing fee balance check before intent creation

### State Consistency
- [x] **Balance Invariants** - Available + locked balance consistency
- [x] **Intent Tracking** - Parent/child intent relationship integrity
- [x] **Order Index** - OrderIndex cleanup on stale entries
- [x] **Atomic Operations** - Balance operations use bint for precision
- [x] **No Double Spending** - Balance locks prevent concurrent spending

---

## 📡 Message Handlers

### Action Handlers (User-Initiated)
- [x] **Info** - Get marketplace information
- [x] **Get-Orders** - Query orders
- [x] **Get-Order** - Query single order
- [x] **Create-Order** - Create ARIO buy order (internal balance)
- [x] **Cancel-Order** - Cancel order and unlock funds
- [x] **Settle-Auction** - Settle expired English auction
- [x] **Withdraw-Fees** - Withdraw treasury fees
- [x] **Create-Intent** - Create ANT listing intent
- [x] **Get-Paginated-Intents** - Query intents
- [x] **Get-Intent-By-Id** - Query single intent
- [x] **Push-ANT-Intent-Resolution** - Trigger ANT State query
- [x] **Get-Paginated-Balances** - Query all balances
- [x] **Get-Balance** - Query single balance
- [x] **Withdraw-Ario** - Withdraw ARIO from marketplace
- [x] **Bid-On-English-Auction** - Place or update bid

### Notice Handlers (System-Initiated)
- [x] **Credit-Notice** - Handle incoming token transfers (deposits & ANT orders)
- [x] **Debit-Notice** - Handle transfer confirmations (resolve child intents)
- [x] **Transfer-Error** - Handle transfer failures (fail intents)
- [x] **State-Notice** - Handle ANT ownership verification (resolve state intents)

---

## 🧪 Testing Coverage

### Unit Tests (Lua)
- [x] **Balance Management** - 10 tests (deposits, withdrawals, locks, unlocks)
- [x] **UCM Core** - 19 tests (order creation, matching, transfers)
- [x] **Dutch Auction** - 4 tests (price decay, matching, settlements)
- [x] **English Auction** - 31 tests (bidding, settlement, validation)
- [x] **Fixed Price** - 5 tests (matching, refunds, validation)
- [x] **Intent Management** - 53 tests (creation, resolution, failure, expiration)
- [x] **Utils** - 223 tests (validation, pagination, helpers)

**Total: 345 passing unit tests**

### Integration Tests (TypeScript)
- [x] **Activity Tests** - Order queries and filtering
- [x] **Auction Tests** - English auction lifecycle
- [x] **Info Tests** - Marketplace information queries
- [x] **Intent Tests** - Intent creation and resolution workflows
- [x] **UCM Tests** - Order creation and matching workflows

### E2E Tests
- [x] **ANT Listing Test** - Complete ANT listing workflow
- [x] **Fixed Price Test** - Fixed price order workflow
- [x] **Smoke Test** - Basic marketplace operations

---

## 🚀 Performance Features

### Optimization
- [x] **O(1) Order Lookup** - OrderIndex for fast order retrieval
- [x] **Dictionary-Based Orders** - Efficient order storage (no array iteration)
- [x] **Lazy Index Cleanup** - Index cleanup on access (no batch operations needed)
- [x] **Scheduled Pruning** - Efficient expiration handling
- [x] **Cursor Pagination** - Efficient pagination without loading all data

### Scalability
- [x] **Bint Arithmetic** - Arbitrary precision integers (no overflow)
- [x] **String-Based Amounts** - Consistent amount representation
- [x] **Stateless Handlers** - Handlers don't maintain session state
- [x] **Deterministic Sorting** - Tie-breaker fields for pagination consistency

---

## 📋 Data Models

### Order Model
```lua
{
  id: string,                    -- Unique order ID
  creator: string,               -- Order creator address
  token: string,                 -- Token being sold/bought
  quantity: string,              -- Amount (string integer)
  originalQuantity: string,      -- Original amount
  price: string,                 -- Price per unit
  orderType: string,             -- "fixed", "dutch", or "english"
  status: string,                -- "active", "executed", "cancelled", "expired"
  dateCreated: number,           -- Creation timestamp
  expirationTime: number,        -- Expiration timestamp
  dominantToken: string,         -- First token in pair
  swapToken: string,             -- Second token in pair
  
  -- Dutch auction specific
  minimumPrice: string,          -- Minimum price
  decreaseInterval: string,      -- Time between price decreases
  decreaseStep: string,          -- Amount to decrease per interval
  
  -- English auction specific
  bids: table,                   -- Bidder addresses
  highestBid: string,            -- Highest bid amount
  highestBidder: string,         -- Highest bidder address
}
```

### Balance Model
```lua
{
  balance: string,               -- Available ARIO balance
  orders: {                      -- Locked ARIO per order
    [orderId]: string            -- Locked amount
  }
}
```

### Intent Model
```lua
{
  id: string,                    -- Unique intent ID
  type: string,                  -- "parent" or "child"
  status: string,                -- "pending", "active", "completed", "failed"
  initiator: string,             -- Intent creator address
  createdAt: number,             -- Creation timestamp
  ttl: number,                   -- Expiration timestamp
  listingFee: string,            -- Fee charged (parent only)
  
  -- Parent intent specific
  childIntentIds: table,         -- Child intent IDs
  forwardedTags: table,          -- Tags forwarded to children
  
  -- Child intent specific
  parentIntentId: string,        -- Parent intent ID
  expectedFrom: string,          -- Expected sender for resolution
}
```

---

## 🔄 State Transitions

### Order Status Flow
```
Created → Active → Executed
              ↓
           Cancelled
              ↓
           Expired
```

### Intent Status Flow
```
Created → Pending → Active → Completed
                       ↓
                    Failed
```

### Balance Flow
```
External Deposit → Available Balance → Locked in Order → Unlocked → Available Balance → External Withdrawal
```

---

## 📦 Constants & Configuration

### Fees
- [x] **Listing Fee Base** - 1 ARIO for first 7 days
- [x] **Listing Fee Multiplier** - Additional ARIO per 7 days
- [x] **Transaction Fee** - 5% of transaction amount
- [x] **Treasury Fee** - 0.5% to treasury
- [x] **Marketplace Fee** - 4.5% to marketplace

### Limits
- [x] **Max Expiration** - 30 days (2592000000 ms)
- [x] **Intent TTL** - 24 hours (86400000 ms)
- [x] **ANT Quantity** - Exactly 1 per order
- [x] **Min Bid Increment** - 1 ARIO (1000000000 mARIO)

### Pagination
- [x] **Default Limit** - 100 items
- [x] **Max Limit** - 10000 items
- [x] **Default Sort By** - CreatedAt
- [x] **Default Sort Order** - Ascending

---

## ⚠️ Known Limitations

### Current Limitations
- [x] **ANT Orders** - Must be exactly 1 ANT (no fractional or multi-ANT orders)
- [x] **Trade Pairs** - Only ARIO ↔ ANT pairs supported
- [x] **Intent Pruning** - Expired intents not automatically pruned (manual cleanup needed)
- [x] **Batch Operations** - No batch order creation or cancellation

### Not Implemented
- [ ] **Limit Orders** - No limit order support (use fixed price instead)
- [ ] **Stop Loss** - No stop loss orders
- [ ] **Partial Fills** - No partial ANT fills (whole token only)
- [ ] **Order Modification** - Cannot modify existing orders (must cancel and recreate)
- [ ] **Multi-Token Trading** - Only ARIO-ANT pairs

---

## 📚 Documentation

### Available Documentation
- [x] **Architecture Audit Report** - Comprehensive compliance audit
- [x] **Feature Checklist** - This document
- [x] **Spec** - Marketplace specification (spec.md)
- [x] **Dutch Auction** - Dutch auction documentation
- [x] **English Auction** - English auction documentation
- [x] **Fixed Price** - Fixed price order documentation
- [x] **SDK Integration** - Integration guides
- [x] **Mermaid Diagram** - Architecture diagram

### Code Documentation
- [x] **Type Annotations** - Lua type annotations with @type
- [x] **Function Docs** - @param and @return documentation
- [x] **Inline Comments** - Explanatory comments throughout
- [x] **Module Docs** - File-level documentation

---

## 🎯 Future Enhancements

### Planned Features
- [ ] **Automatic Intent Pruning** - Scheduled cleanup of expired intents
- [ ] **Order Modification** - Modify price/expiration without canceling
- [ ] **Batch Operations** - Batch order creation and cancellation
- [ ] **Enhanced Analytics** - More detailed VWAP and trading statistics
- [ ] **Multi-ANT Orders** - Support for multiple ANTs in single order (if use case emerges)

### Potential Features
- [ ] **Order Books** - Traditional order book view for each pair
- [ ] **Trading History** - Detailed trade history per user
- [ ] **Price Oracles** - External price data integration
- [ ] **Advanced Filters** - More query filtering options
- [ ] **Notifications** - Event notifications for order status changes

---

## ✅ Compliance Summary

### Architecture Requirements
- [x] **ARIO Internal Ledger** - All ARIO operations use internal balance (no intents)
- [x] **ANT Intent-Based** - All ANT operations tracked with intents
- [x] **Data Structure Organization** - Clean, efficient data structures

### Code Quality
- [x] **Type Safety** - Lua type annotations throughout
- [x] **Error Handling** - Comprehensive validation and error messages
- [x] **Test Coverage** - 345 unit tests, integration tests, E2E tests
- [x] **Documentation** - Inline docs, type annotations, external docs

### Security
- [x] **Input Validation** - All inputs validated
- [x] **Balance Checks** - No negative balances or double spending
- [x] **Access Control** - Proper authorization checks
- [x] **Precision Arithmetic** - Bint for all numeric operations

---

**Last Verified**: 2025-11-25  
**Test Status**: 345 passing / 0 failures / 0 pending  
**Compliance**: ✅ Fully Compliant

