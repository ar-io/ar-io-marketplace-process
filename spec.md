# ARNS Marketplace
## Introduction

The **ARNS Marketplace** protocol facilitates the trustless exchange of ARnS tokens using a decentralized order book system.

This specification describes the ARNS Marketplace's functionality, including order creation and execution.

---

### Key Components

1. **ARNS Tokens**: Unique tokens representing ARNS domains on the permaweb.
2. **Order Book**: The data structure that stores active buy and sell orders for trading ARNS tokens.
3. **Swap Token**: A token used in exchange for ARNS tokens. The default swap token is `ARIO_TOKEN_PROCESS_ID`.
4. **Marketplace Process**: A single process that handles order creation, matching, auctions, settlement, cancellations, and internal activity tracking (no separate activity process).

---

### Core Data Structures

#### 1. **Order Book Entry**
Each pair of tokens traded is associated with an order book entry containing multiple orders.

```lua
Orderbook = {
    {
        Pair = {TokenId, TokenId}, -- {ARIO, ANT} or {ANT, ARIO}
        Orders = {
            {
                Id,
                Creator,
                Quantity,              -- current remaining quantity
                OriginalQuantity,      -- original listed quantity
                Token,                 -- dominant token process id (seller token for ARIO-dominant)
                DateCreated,
                Price,                 -- required for fixed/dutch/english listings
                ExpirationTime,        -- optional; used by dutch/english
                OrderType,             -- 'fixed' | 'dutch' | 'english'
                -- dutch-only fields
                MinimumPrice,
                DecreaseInterval,
                DecreaseStep,
            }
        },
        PriceData = {                 -- optional, for VWAP after trades
            Vwap,
            Block,
            DominantToken,
            MatchLogs
        }
    }
} 
```

#### 2. **Order**
Each order represents a user's intent to buy or sell a specific quantity of ARNS tokens at a certain price (limit orders) or at the market price (market orders).

---

### Functions

#### 1. **getPairIndex**
Finds the index of the token pair in the order book.

#### 2. **createOrder**
Creates an order and routes to the specific flow depending on dominance and order type:
- Validates pair, ARIO-in-trade requirement, and amounts.
- ANT-dominant (selling ANT): immediate execution against existing ARIO listings only; no orderbook listing.
- ARIO-dominant (selling ANT for ARIO via listing): adds to orderbook for Buy-Now (fixed), Dutch, or English auction.
- Populates metadata from ARIO records when swap token is ARIO.

#### 3. **cancelOrder**
Cancels an active or expired order by id if requested by the creator; returns funds and records cancellation internally.

#### 4. **settleAuction**
Settles an expired English auction; transfers funds and assets, charges fees, records settlement and execution, then removes order and clears bids.

#### 5. **handleError**
Handles error reporting and refunds the sender's tokens in case of an invalid transaction.

---

### Order Types

- **Fixed**: ARIO-dominant listings added to orderbook; ANT buyers execute immediately against a specific listing, with refund of any overpayment.
- **Dutch**: ARIO-dominant listings with decreasing price over time using `DecreaseInterval` and `DecreaseStep`; ANT buyers execute immediately at current price against a specific order.
- **English**: ARIO-dominant listings where bidders place increasing ARIO bids; requires settlement after expiration to transfer assets to the winner.

### Processes

The marketplace is a single process that handles all flows (order creation, matching, settlement, cancellations) and maintains internal activity state. Activity-related actions (listed/executed/cancelled orders, bids, settlements, metrics) are recorded via internal calls.

---

### Example Workflow

1. **Order Creation**:
   - A user creates a new order to buy or sell ARNS tokens.
   - ARIO must be one side of the pair.
   - If ANT-dominant, execute immediately against an ARIO listing or fail.
   - If ARIO-dominant, add a new listing to the orderbook (fixed/dutch/english).

2. **Order Matching**:
   - Fixed: ANT buyers must meet or exceed the listed price of the specific order; excess ARIO is refunded.
   - Dutch: ANT buyers execute against the specific order at its time-adjusted current price.
   - English: Bids are recorded internally; highest bid replaces previous highest (which is refunded). After expiration, `settleAuction` transfers assets and records execution.

---

### Fees

ARNS Marketplace captures a 0.5% fee on trades, adjustable via `calculateFeeAmount` and `calculateSendAmount` in `utils.lua` (or `bundle_ucm.lua` for bundled deployments). Fees accrue and can be withdrawn by the process owner via a management action.

---

### Error Handling

Errors in the system (such as invalid token pairs, insufficient quantities, or pricing issues) are caught by the `handleError` function, which returns any necessary tokens to the user and logs the error for further analysis.

Additional validation rules:
- ARIO must be involved in every trade pair.
- ANT tokens can only be sold in quantities of exactly 1.
- English bids must be strictly higher than the current highest bid and at least 1 ARIO higher; first bid must meet the minimum starting price.

---

### Conclusion

The ARNS Marketplace protocol is a decentralized marketplace built on the permaweb, enabling users to trade ARNS tokens. Its robust order book system supports both market and limit orders, ensuring efficient and trustless exchanges of ARNS tokens.