# ADR-000: Orderbook Architecture and Order Directionality

## Status

Accepted

## Context

The AR.IO Marketplace needs an efficient data structure for managing trading pairs between ARIO tokens and ANTs (Arweave Name Tokens). The orderbook must support:

1. **Multiple Trading Pairs**: Many different ANT processes trading against ARIO
2. **Directional Trading**: Clear semantics for who is buying vs. selling
3. **ANT Uniqueness**: Each ANT token (quantity of 1) can only be listed once
4. **Order Types**: Support for fixed price, Dutch auctions, and English auctions across all pairs

The marketplace operates in a constrained environment:
- **Single token pairs**: Only ANT ↔ ARIO trading (not ANT ↔ ANT or multi-hop)
- **Asymmetric assets**: ANTs are unique (quantity=1), ARIO is fungible (any quantity)

Key design questions:
- How should orders be organized in memory?
- Should orders be bidirectional (ANT→ARIO and ARIO→ANT) or unidirectional?
- How do we efficiently find orders for matching?
- What happens when a buyer wants to purchase an ANT?
- Should buy orders sit in the orderbook or match immediately?

## Decision

We implement a **directional, unidirectional orderbook** where:

1. **Only sell orders are stored** - the orderbook contains ANT listings (ANT → ARIO pairs)
2. **ANT-dominant orders are added to the orderbook** - sellers list ANTs and wait for buyers
3. **ARIO-dominant orders match immediately** - buyers find and fill existing sell orders on-the-spot
4. **O(1) order lookup** via a separate OrderIndex for fast retrieval
5. **Empty pair pruning** to prevent memory bloat from dead trading pairs

### Orderbook Structure

```lua
-- Global orderbook state (two-level nested structure)
Orderbook = {
  [dominantToken] = {              -- Level 1: Token being sold (ANT process ID)
    [swapToken] = {                -- Level 2: Token being bought (ARIO process ID)
      pair = {dominantToken, swapToken},
      orders = {
        [orderId] = orderObject,   -- Dictionary of orders for this pair
        -- ...
      }
    }
  }
}

-- Global index for O(1) lookup (location cache)
OrderIndex = {
  [orderId] = {
    dominantToken = "ant-process-id",
    swapToken = "ario-process-id"
  }
}
```

**Example**:
```lua
Orderbook = {
  ["bLAgYxAdX2Ry-nt6aH2ixgvJXbpsEYm28NgJgyqfs-U"] = {  -- ANT process ID
    ["ARIO_TOKEN_PROCESS_ID"] = {
      pair = {"bLAgYxAdX2Ry-nt6aH2ixgvJXbpsEYm28NgJgyqfs-U", "ARIO_TOKEN_PROCESS_ID"},
      orders = {
        ["order-msg-id-1"] = {
          id = "order-msg-id-1",
          creator = "seller-address",
          token = "bLAgYxAdX2Ry-nt6aH2ixgvJXbpsEYm28NgJgyqfs-U",
          quantity = "1",
          price = "10000000000",  -- 10 ARIO
          orderType = "fixed",
          status = "active",
          dominantToken = "bLAgYxAdX2Ry-nt6aH2ixgvJXbpsEYm28NgJgyqfs-U",
          swapToken = "ARIO_TOKEN_PROCESS_ID",
          -- ... more fields
        }
      }
    }
  }
}

OrderIndex = {
  ["order-msg-id-1"] = {
    dominantToken = "bLAgYxAdX2Ry-nt6aH2ixgvJXbpsEYm28NgJgyqfs-U",
    swapToken = "ARIO_TOKEN_PROCESS_ID"
  }
}
```

### Order Directionality: ANT-Dominant vs ARIO-Dominant

**This is the most critical design decision in the marketplace.**

The marketplace distinguishes between two fundamentally different order types based on which token is dominant (being offered):

#### ANT-Dominant Orders (Selling ANT for ARIO)

**Characteristics**:
- **dominantToken**: ANT process ID (what seller is offering)
- **swapToken**: ARIO process ID (what seller wants)
- **Behavior**: **Added to orderbook as a listing**
- **Think of it as**: "Limit sell order" - sits and waits for buyers
- **Created via**: Intent-based workflow (see ADR-004)

**Required Parameters**:
```lua
{
  dominantToken = "ant-process-id",
  swapToken = "ario-process-id",
  quantity = "1",                    -- MUST be exactly 1 for ANTs
  price = "10000000000",             -- REQUIRED: price in mARIO
  orderType = "fixed" | "dutch" | "english",
  expirationTime = 1234567890,       -- REQUIRED: Unix timestamp
}
```

**Flow**:
```
1. Seller creates intent (charges listing fee from ARIO balance)
2. Seller transfers ANT to marketplace with X-Intent-Id
3. Marketplace receives Credit-Notice
4. Order is ADDED to Orderbook[ANT][ARIO]
5. Order sits and waits for buyer
6. When buyer comes, order is filled and removed
```

**Validation Rules**:
- Quantity MUST be exactly `1` (ANTs are non-fungible)
- Price is REQUIRED (seller sets asking price)
- Expiration time is REQUIRED (max 30 days)
- Each ANT can only be listed once (checked via token ID)

**Storage Location**:
```lua
Orderbook[ANT_PROCESS_ID][ARIO_PROCESS_ID].orders[orderId] = {
  -- order sits here until filled, cancelled, or expired
}
```

#### ARIO-Dominant Orders (Buying ANT with ARIO)

**Characteristics**:
- **dominantToken**: ARIO process ID (what buyer is offering)
- **swapToken**: ANT process ID (what buyer wants)
- **Behavior**: **Matches immediately against existing sell orders**
- **Think of it as**: "Market buy order" - executes now or fails
- **Created via**: Direct message using internal ARIO balance

**Required Parameters**:
```lua
{
  dominantToken = "ario-process-id",
  swapToken = "ant-process-id",
  quantity = "10000000000",          -- Amount of ARIO to spend
  requestedOrderId = "order-id",     -- REQUIRED: specific order to match
  orderType = "fixed" | "dutch" | "english",
}
```

**Flow**:
```
1. Buyer sends Create-Order message (uses internal ARIO balance)
2. Marketplace looks for matching sell order in Orderbook[ANT][ARIO]
3. If found and valid: execute trade immediately
4. If not found or invalid: refund ARIO and error
5. Order is NEVER added to orderbook
```

**Validation Rules**:
- `requestedOrderId` is REQUIRED (must specify which ANT to buy)
- Quantity must be >= order's price (can overpay, excess refunded)
- No expiration time (immediate execution only)
- Price is NOT specified (buyer accepts seller's price)

**Storage Location**:
```
NONE - ARIO-dominant orders don't sit in the orderbook!
They either:
  - Match immediately → trade executes, sell order removed
  - Don't match → error, ARIO refunded
```

### Critical Asymmetry

**This is NOT a traditional limit order book with bid/ask spreads!**

Traditional orderbook:
```
Bids (buy orders)        Asks (sell orders)
$9.50 - 10 units    |    $10.50 - 5 units
$9.00 - 20 units    |    $11.00 - 15 units
```

AR.IO Marketplace orderbook:
```
Sell Orders (ANT listings)
ANT #1: 10 ARIO
ANT #2: 15 ARIO
ANT #3: 8 ARIO

Buy Orders: NONE (match immediately or fail)
```

**Why this design?**

1. **ANTs are unique**: You're buying a specific ANT, not fungible units
2. **No bid aggregation**: Can't combine multiple buy orders for one ANT
3. **Prevents stale orders**: Buy orders that can't fill would clutter the book
4. **Simpler UX**: Buyers browse listings, click "buy now"
5. **Matches NFT marketplace pattern**: OpenSea, Rarible work the same way

### Order Matching Logic

When an ARIO-dominant order comes in, the marketplace:

```lua
function ucm.createOrder(args)
  local validPair = ucm.validateOrderParams(args)
  local pair = ucm.ensurePairExists(validPair)
  
  local isBuyingAnt = utils.isArioToken(args.dominantToken)
  
  if isBuyingAnt then
    -- ARIO-dominant: buyer wants ANT
    -- Look in OPPOSITE pair direction: [ANT][ARIO]
    local oppositePair = { validPair[2], validPair[1] }
    local oppositePairObj = ucm.ensurePairExists(oppositePair)
    
    -- Try to match with existing ANT sell orders
    ucm.handleAntOrderAuctions(args, oppositePair, oppositePairObj)
    -- If no match found, this will error and refund
    return
  else
    -- ANT-dominant: seller lists ANT
    -- Add to orderbook and wait
    ucm.handleArioOrderAuctions(args, validPair, pair)
    return
  end
end
```

**Key point**: When buying, we look in `Orderbook[ANT][ARIO]`, not `Orderbook[ARIO][ANT]`. The buyer "flips" the pair to find sell orders.

### O(1) Order Lookup via OrderIndex

Finding an order by ID requires knowing which pair it's in. Without an index, this would be O(n×m) where n=number of ANTs, m=average orders per ANT.

The OrderIndex provides O(1) lookup:

```lua
function ucm.getOrderById(orderId)
  -- O(1) lookup in index
  local location = OrderIndex[orderId]
  if not location then
    return nil, nil
  end
  
  -- O(1) nested table access
  local pair = Orderbook[location.dominantToken][location.swapToken]
  if not pair then
    -- Stale index, clean up
    OrderIndex[orderId] = nil
    return nil, nil
  end
  
  -- O(1) order retrieval
  local order = pair.orders[orderId]
  if not order then
    -- Stale index, clean up
    OrderIndex[orderId] = nil
    return nil, nil
  end
  
  return order, pair
end
```

**Index Management**:
- Created when order is added: `OrderIndex[orderId] = { dominantToken, swapToken }`
- Deleted when order is removed: `OrderIndex[orderId] = nil`
- Self-healing: detects stale entries and cleans them up

**Use Cases**:
- Cancel-Order: Find order to cancel
- Settle-Auction: Find auction to settle
- Get-Order: Retrieve order details
- Bid-On-English-Auction: Find auction to bid on

### Empty Pair Pruning

Over time, trading pairs can become empty as orders complete. Empty pairs waste memory:

```lua
function ucm.pruneEmptyPair(dominantToken, swapToken)
  local pair = Orderbook[dominantToken][swapToken]
  if not pair then return end
  
  -- Check if any orders remain
  local hasOrders = false
  for _ in pairs(pair.orders) do
    hasOrders = true
    break
  end
  
  -- If empty, remove the pair
  if not hasOrders then
    Orderbook[dominantToken][swapToken] = nil
    
    -- If dominant token level is now empty, remove it too
    local hasSwapTokens = false
    for _ in pairs(Orderbook[dominantToken]) do
      hasSwapTokens = true
      break
    end
    
    if not hasSwapTokens then
      Orderbook[dominantToken] = nil
    end
  end
end
```

**Called when**:
- Order is cancelled
- Order is filled (fully executed)
- Order expires

**Benefits**:
- Prevents memory bloat
- Keeps orderbook compact
- No dead pairs in iteration

### Order Lifecycle

**ANT Sell Order**:
```
Created → Active → [Matched/Cancelled/Expired] → Removed
  ↓
Added to Orderbook[ANT][ARIO]
  ↓
Sits and waits
  ↓
Buyer comes
  ↓
Order filled, removed from orderbook
  ↓
ANT transferred to buyer via intent
```

**ARIO Buy Order**:
```
Created → [Match Found?]
            ↓ Yes: Execute trade, done
            ↓ No: Error, refund ARIO
Never touches orderbook
```

## Consequences

### Positive

1. **Memory Efficient**: Only stores active sell orders, not speculative buy orders
2. **Fast Lookups**: O(1) order retrieval via OrderIndex
3. **Clear Semantics**: Buyers browse listings, sellers list ANTs
4. **No Stale Data**: Empty pairs pruned automatically
5. **Scales Well**: Number of pairs = number of unique ANTs listed (not exponential)
6. **Simple Matching**: Direct lookup, no complex bid/ask matching algorithm
7. **NFT-Like UX**: Familiar pattern from NFT marketplaces
8. **Prevents Spam**: Can't create free buy orders that sit forever
9. **Atomic Operations**: Buy orders execute immediately or fail cleanly

### Negative

1. **No Buy Order Queue**: Buyers can't place advance orders for ANTs not yet listed
2. **No Price Discovery on Buy Side**: Can't see what buyers are willing to pay
3. **Asymmetric API**: ANT orders vs ARIO orders work very differently
4. **Learning Curve**: Users must understand dominant token concept
5. **No Bid Aggregation**: Can't pool multiple buyers for one ANT
6. **Immediate Execution Only**: ARIO buyers can't "place and forget"
7. **Requires Specific Order ID**: Buyers must know exactly which ANT they want

### Neutral

1. **Unidirectional Design**: Could be bidirectional, but complexity not justified
2. **Index Duplication**: OrderIndex duplicates some data (location info)
3. **Pair Direction**: `[ANT][ARIO]` chosen arbitrarily (could be reversed)
4. **Dictionary vs Array**: `orders` is a dictionary (could be array with different tradeoffs)

## Alternatives Considered

### 1. Bidirectional Orderbook

Store both buy and sell orders:

```lua
Orderbook = {
  [tokenA] = {
    [tokenB] = {
      sellOrders = {},  -- Selling tokenA for tokenB
      buyOrders = {}    -- Buying tokenA with tokenB
    }
  }
}
```

**Rejected because**:
- Doubles memory usage
- More complex matching logic
- Buy orders for unique ANTs don't make sense (you want a specific ANT)
- Would need bid aggregation (multiple buyers → one ANT?)
- Stale buy orders would clutter the book

### 2. Flat Order List (No Pairs)

Store all orders in a single list:

```lua
Orders = {
  [orderId] = {
    dominantToken = "...",
    swapToken = "...",
    -- ...
  }
}
```

**Rejected because**:
- O(n) search to find orders for a specific pair
- Can't efficiently list ANTs for sale
- No pair-level operations
- Harder to prevent duplicate ANT listings

### 3. Traditional Limit Order Book

Separate bid/ask books with price levels:

```lua
Orderbook = {
  [pair] = {
    bids = {
      ["10.00"] = { orders },
      ["9.50"] = { orders },
    },
    asks = {
      ["10.50"] = { orders },
      ["11.00"] = { orders },
    }
  }
}
```

**Rejected because**:
- ANTs are unique, not fungible (can't aggregate at price levels)
- No partial fills for ANTs (quantity is always 1)
- Overkill for ANT ↔ ARIO only trading
- Complex matching algorithm not needed

### 4. Graph-Based Order Routing

Orders as nodes, matches as edges:

```lua
Orders = { [id] = order }
Edges = { [orderId] = { matchingOrders } }
```

**Rejected because**:
- Way too complex for single-pair trading
- No multi-hop trading in marketplace
- ANT ↔ ARIO only (no ANT ↔ ANT)
- Performance overhead not justified

### 5. Array-Based Order Storage

Store orders in arrays instead of dictionaries:

```lua
pair.orders = { order1, order2, order3 }  -- Array
```

**Rejected because**:
- O(n) deletion (need to find and remove)
- O(n) lookup by order ID
- Fragmentation from deletes
- Dictionary provides O(1) operations

### 6. Hybrid: Sell-Only Book + Buy Order Queue

Store sell orders in book, queue buy orders separately:

```lua
SellOrders[ANT][ARIO] = { orders }
BuyQueue[ANT] = { waitingBuyers }  -- Notified when ANT listed
```

**Considered but deferred**:
- Could work for future feature: "buy alerts"
- Adds complexity without clear current benefit
- Would need matching logic when new ANT listed
- Could be added later without breaking changes

## Implementation Notes

### Type Definitions

```lua
---@alias TokenId string Process ID of a token
---@alias OrderId string Message ID of order creation
---@alias Pair table Trading pair with orders

---@class Pair
---@field pair TokenId[] The [dominantToken, swapToken] pair
---@field orders table<OrderId, Order> Dictionary of orders

---@alias Orderbook table<TokenId, table<TokenId, Pair>>
-- Structure: Orderbook[dominantToken][swapToken] = Pair

---@alias OrderIndex table<OrderId, OrderLocation>

---@class OrderLocation
---@field dominantToken TokenId The dominant token for this order
---@field swapToken TokenId The swap token for this order
```

### Pair Lookup

```lua
function ucm.getPair(dominantToken, swapToken)
  if Orderbook[dominantToken] and Orderbook[dominantToken][swapToken] then
    return Orderbook[dominantToken][swapToken]
  end
  return nil
end
```

### Pair Creation

```lua
function ucm.ensurePairExists(validPair)
  local dominantToken, swapToken = validPair[1], validPair[2]
  
  -- Create dominantToken level if doesn't exist
  if not Orderbook[dominantToken] then
    Orderbook[dominantToken] = {}
  end
  
  -- Create pair if doesn't exist
  if not Orderbook[dominantToken][swapToken] then
    Orderbook[dominantToken][swapToken] = {
      pair = validPair,
      orders = {},
    }
  end
  
  return Orderbook[dominantToken][swapToken]
end
```

## User Experience Implications

### For Sellers (ANT Owners)

**Workflow**:
1. Deposit ARIO for listing fee (1 ARIO per 7 days)
2. Create intent with price and expiration
3. Transfer ANT to marketplace with `X-Intent-Id`
4. ANT appears in orderbook
5. Wait for buyer
6. Receive ARIO when sold

**Mental Model**: "Post a classified ad" - list it and wait

### For Buyers (ARIO Holders)

**Workflow**:
1. Deposit ARIO to internal balance
2. Browse orderbook (via `Get-Orders`)
3. Find desired ANT order
4. Send `Create-Order` with `Swap-Token` (ANT process ID)
5. If available: instantly receive ANT
6. If gone: get refund and error

**Mental Model**: "Buy it now" button - instant purchase or failure

### Common Misunderstandings

❌ **Wrong**: "I can place a buy order for 5 ARIO and wait for any ANT"
✅ **Right**: "I must specify which ANT I want and buy it immediately"

❌ **Wrong**: "The orderbook shows both buy and sell orders"
✅ **Right**: "The orderbook only shows ANTs for sale (sell orders)"

❌ **Wrong**: "I can place a bid below the asking price and wait"
✅ **Right**: "I must pay the asking price (or more) to buy immediately"

❌ **Wrong**: "Orders are matched by price priority"
✅ **Right**: "Buyers choose specific orders to fill"

## Future Considerations

1. **Buy Order Queue**: Allow buyers to queue for specific ANTs (notify when listed)
2. **Offer System**: Let buyers make offers below asking price (seller can accept)
3. **Batch Buying**: Buy multiple ANTs in one transaction
4. **Pair Statistics**: Track volume, last sale price, etc. per pair
5. **Order Aggregation**: Bundle similar ANTs for bulk purchase
6. **Watchlists**: Users can watch specific ANT tokens
7. **Price History**: Store historical prices for each ANT
8. **Bidirectional Support**: Future multi-token trading (ANT ↔ AR, etc.)
9. **Advanced Filters**: Search orders by metadata, traits, etc.
10. **Order Modification**: Allow sellers to update price without recreating order

## References

- Source: `src/ucm.lua` - Orderbook implementation
- Source: `src/types.lua` - Type definitions for Orderbook, Pair, Order
- ADR-004: Intent-Based Workflow - How ANT orders are created
- ADR-003: ARIO Internal Ledger - How ARIO orders use internal balance
- README.md: API Reference - User-facing documentation

## Related Decisions

- **ADR-001**: Module Whitelist - Which ANT modules can be traded
- **ADR-002**: Credit-Notice Pattern - How ANTs enter the marketplace
- **ADR-003**: ARIO Internal Ledger - Why ARIO uses internal balance
- **ADR-004**: Intent-Based Workflow - How multi-step ANT orders work

