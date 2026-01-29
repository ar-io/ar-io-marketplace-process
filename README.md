# ar.io Marketplace AO Process

## Overview

The AR.IO Marketplace is a decentralized protocol built on AO for trustless exchange of ARIO tokens and ANT (Arweave Name Tokens). The marketplace supports three order types:

- **Fixed Price Orders** - Immediate buy/sell at a set price
- **Dutch Auction Orders** - Price decreases over time until filled
- **English Auction Orders** - Competitive bidding with settlement period

### Key Architecture Features

- **Unidirectional Orderbook** - Only ANT sell orders sit in the orderbook; ARIO buy orders match immediately (see [ADR-000](docs/adr/ADR-000-orderbook-architecture.md))
- **ARIO Internal Ledger** - All ARIO operations use an internal balance system (deposit → trade → withdraw)
- **ANT Intent-Based System** - ANT transfers are tracked through parent/child intent relationships
- **Multiple Order Types** - Fixed price, Dutch auctions, and English auctions
- **Listing Fees** - Duration-based fees (1 ARIO per hour) charged from internal balance
- **Transaction Fees** - 5% fee on all trades (0.5% treasury, 4.5% marketplace)

## Quick Start

```bash
# Install dependencies
npm install @permaweb/aoconnect

# Interact with the marketplace
import { message, result } from '@permaweb/aoconnect';
```

## How It Works

### Important: Two Types of Orders

The marketplace has an **asymmetric orderbook** (see [ADR-000](docs/adr/ADR-000-orderbook-architecture.md)):

- **Selling ANT (ANT-dominant orders)**: Your ANT listing **sits in the orderbook** and waits for buyers
- **Buying ANT (ARIO-dominant orders)**: Your buy order **matches immediately** against existing listings or fails

This is similar to NFT marketplaces (OpenSea, Rarible) where only "listings" sit in the orderbook, and buyers execute instant purchases.

### Selling ANT (Listing Flow)

1. **Create Intent** - Create a listing intent (charges listing fee from ARIO balance)
2. **Transfer ANT** - Send ANT to marketplace with `X-Intent-Id` tag
3. **Marketplace Receives** - `Credit-Notice` activates the order
4. **Order Added to Orderbook** - Your ANT listing appears for buyers to purchase
5. **Wait for Buyer** - Order sits until matched, cancelled, or expired
6. **Settlement** - When bought, marketplace transfers ANT to buyer (tracked via child intent)

### Buying ANT (Instant Purchase Flow)

1. **Deposit ARIO** - Transfer ARIO to marketplace via `Credit-Notice` with `X-Action: Deposit`
2. **Browse Listings** - Use `Get-Orders` to find ANTs for sale
3. **Create Buy Order** - Specify which ANT to buy via `Swap-Token` (ANT process ID)
4. **Immediate Match** - Order fills instantly if listing still available
5. **Receive ANT** - Marketplace transfers ANT to you immediately
6. **Withdraw** - Withdraw remaining ARIO balance anytime

---

## API Reference

All handlers return a notice to the sender with the action result. Successful operations return `{Action}-Notice` (e.g., `Info-Notice`), while errors return `Invalid-{Action}-Notice`.

### 📊 Marketplace Information

#### `Info`

Get marketplace process information.

**Parameters:** None

**Response:**
```json
{
  "Name": "AR.IO Marketplace",
  "Version": "0.1.0",
  "Owner": "process-owner-address",
  "Treasury": "treasury-address",
  "['ARIO-Token-Process-Id']": "ario-process-id",
  "['Accrued-Fees']": "fee-amount-in-mARIO"
}
```

**Example (aoconnect):**

```typescript
import { message, result } from '@permaweb/aoconnect';

const messageId = await message({
  process: MARKETPLACE_PROCESS_ID,
  tags: [{ name: 'Action', value: 'Info' }],
  signer: createDataItemSigner(wallet),
});

const { Messages } = await result({
  message: messageId,
  process: MARKETPLACE_PROCESS_ID,
});

const info = JSON.parse(Messages[0].Data);
console.log('Marketplace:', info);
```

---

### 🛒 Order Management

#### `Get-Orders`

Query orders with flexible filtering and pagination.

**Parameters:**

| Tag | Type | Required | Description |
|-----|------|----------|-------------|
| `Status` | string | No | Filter by status: `active`, `executed`, `cancelled`, `expired`, `listed`, `completed`, `all` |
| `Ids` | JSON array | No | Filter by specific order IDs: `["id1", "id2"]` |
| `Dominant-Token` | string | No | Filter by dominant token (token being offered) |
| `Swap-Token` | string | No | Filter by swap token (token requested) |
| `Cursor` | string | No | Pagination cursor from previous response |
| `Limit` | number | No | Items per page (default: 100, max: 1000) |
| `Sort-By` | string | No | Field to sort by (default: `CreatedAt`) |
| `Sort-Order` | string | No | `asc` or `desc` (default: `desc`) |

**Response:**
```json
{
  "items": [/* array of orders */],
  "limit": 100,
  "totalItems": 250,
  "sortBy": "CreatedAt",
  "sortOrder": "desc",
  "hasMore": true,
  "nextCursor": "cursor-string"
}
```

**Example (aoconnect):**

```typescript
// Get all active orders
const msgId = await message({
  process: MARKETPLACE_PROCESS_ID,
  tags: [
    { name: 'Action', value: 'Get-Orders' },
    { name: 'Status', value: 'active' },
    { name: 'Limit', value: '50' },
  ],
  signer: createDataItemSigner(wallet),
});

const { Messages } = await result({
  message: msgId,
  process: MARKETPLACE_PROCESS_ID,
});

const orders = JSON.parse(Messages[0].Data);
console.log(`Found ${orders.totalItems} active orders`);
```

#### `Get-Order`

Get a single order by ID.

**Parameters:**

| Tag | Type | Required | Description |
|-----|------|----------|-------------|
| `Order-Id` | string | Yes | The order ID to retrieve |

**Example (aoconnect):**

```typescript
const msgId = await message({
  process: MARKETPLACE_PROCESS_ID,
  tags: [
    { name: 'Action', value: 'Get-Order' },
    { name: 'Order-Id', value: 'order-message-id' },
  ],
  signer: createDataItemSigner(wallet),
});

const { Messages } = await result({
  message: msgId,
  process: MARKETPLACE_PROCESS_ID,
});

const order = JSON.parse(Messages[0].Data);
```

#### `Create-Order`

Create an ARIO buy order using internal balance. This order **matches immediately** against existing ANT listings.

> **Important:** This handler is for **buying ANTs with ARIO** (ARIO-dominant orders). To **sell ANTs for ARIO** (ANT-dominant orders), use the Intent system (see [Intent Management](#-intent-management-ant-listings)). See [ADR-000](docs/adr/ADR-000-orderbook-architecture.md) for details on order directionality.

**Parameters:**

| Tag | Type | Required | Description |
|-----|------|----------|-------------|
| `Swap-Token` | string | Yes | ANT process ID you want to buy |
| `Quantity` | string | Yes | Amount of ARIO to offer (in mARIO) |
| `Order-Type` | string | Yes | Type of the sell order you're buying (`fixed`, `dutch`, or `english`) |

> **Note:** When buying ANT, you do NOT specify a price - you accept the seller's asking price. The `Swap-Token` (ANT process ID) uniquely identifies which ANT to buy, as each ANT can only have one active sell order at a time.

**Example (aoconnect):**

```typescript
// Buy a specific ANT listing
const msgId = await message({
  process: MARKETPLACE_PROCESS_ID,
  tags: [
    { name: 'Action', value: 'Create-Order' },
    { name: 'Swap-Token', value: ANT_PROCESS_ID }, // Which ANT to buy
    { name: 'Quantity', value: '10000000000' }, // 10 ARIO (must be >= asking price)
    { name: 'Order-Type', value: 'fixed' },
  ],
  signer: createDataItemSigner(wallet),
});

const { Messages } = await result({
  message: msgId,
  process: MARKETPLACE_PROCESS_ID,
});

console.log('Purchase result:', JSON.parse(Messages[0].Data));
```

#### `Cancel-Order`

Cancel an active order and unlock funds.

**Parameters:**

| Tag | Type | Required | Description |
|-----|------|----------|-------------|
| `Order-Id` | string | Yes | The order ID to cancel |

**Example (aoconnect):**

```typescript
const msgId = await message({
  process: MARKETPLACE_PROCESS_ID,
  tags: [
    { name: 'Action', value: 'Cancel-Order' },
    { name: 'Order-Id', value: 'order-message-id' },
  ],
  signer: createDataItemSigner(wallet),
});

const { Messages } = await result({
  message: msgId,
  process: MARKETPLACE_PROCESS_ID,
});
```

---

### 🎯 Intent Management (ANT Listings)

ANT listings use an intent-based workflow to ensure atomic transfers. ANT sell orders are **added to the orderbook** and wait for buyers, unlike ARIO buy orders which match immediately (see [ADR-000](docs/adr/ADR-000-orderbook-architecture.md)).

#### `Create-Intent`

Create a listing intent for ANT orders. This charges a listing fee from your internal ARIO balance.

**Listing Fee:** 1 ARIO per hour (calculated based on `X-Intent-Expiration-Time`)

**Parameters:**

| Tag | Type | Required | Description |
|-----|------|----------|-------------|
| `X-Intent-Quantity` | string | Yes | Amount to trade (usually `1` for ANT) |
| `X-Intent-Price` | string | Yes | Price per unit (for fixed/dutch), or starting bid (for english) |
| `X-Intent-Order-Type` | string | No | `fixed`, `dutch`, or `english` (default: `fixed`) |
| `X-Intent-Expiration-Time` | number | Yes | Unix timestamp (min 1 hour, max 30 days, fee rounded up to nearest hour) |
| `X-Intent-Minimum-Price` | string | No* | Minimum price floor (dutch auctions only) |
| `X-Intent-Decrease-Interval` | string | No* | Price decrease interval in ms (dutch auctions only) |

*Required only for dutch auction orders

> **Note:** This handler is only for ANT sell orders (`Create-Order` action is assumed, always swaps ANT for ARIO). ARIO buy orders don't use intents - they call `Create-Order` directly.

**Response:**
```json
{
  "Intent-Id": "intent-id",
  "Status": "Success"
}
```

**Example (aoconnect) - Create ANT Listing:**

```typescript
// Step 1: Create intent (charges listing fee)
const intentMsgId = await message({
  process: MARKETPLACE_PROCESS_ID,
  tags: [
    { name: 'Action', value: 'Create-Intent' },
    { name: 'X-Intent-Quantity', value: '1' }, // 1 ANT
    { name: 'X-Intent-Order-Type', value: 'fixed' },
    { name: 'X-Intent-Price', value: '10000000000' }, // 10 ARIO
    { name: 'X-Intent-Expiration-Time', value: String(Date.now() + 604800000) }, // 7 days
  ],
  signer: createDataItemSigner(wallet),
});

const { Messages: intentMessages } = await result({
  message: intentMsgId,
  process: MARKETPLACE_PROCESS_ID,
});

const intentData = JSON.parse(intentMessages[0].Data);
const intentId = intentData['Intent-Id'];
console.log('Intent created:', intentId);

// Step 2: Transfer ANT to marketplace with intent ID
// Order parameters come from the intent created in Step 1
const transferMsgId = await message({
  process: ANT_PROCESS_ID,
  tags: [
    { name: 'Action', value: 'Transfer' },
    { name: 'Recipient', value: MARKETPLACE_PROCESS_ID },
    { name: 'Quantity', value: '1' },
    { name: 'X-Intent-Id', value: intentId },
    { name: 'X-Order-Action', value: 'Create-Order' },
  ],
  signer: createDataItemSigner(wallet),
});

console.log('ANT transferred, order will be created automatically');
```

#### `Get-Paginated-Intents`

Query intents with filtering and pagination.

**Parameters:**

| Tag | Type | Required | Description |
|-----|------|----------|-------------|
| `Cursor` | string | No | Pagination cursor |
| `Limit` | number | No | Items per page (default: 100, max: 1000) |
| `Sort-By` | string | No | Field to sort by |
| `Sort-Order` | string | No | `asc` or `desc` |
| `Filters` | JSON object | No | Filter by: `{ "initiator": "address", "status": "pending", "type": "parent" }` |

**Example (aoconnect):**

```typescript
const msgId = await message({
  process: MARKETPLACE_PROCESS_ID,
  tags: [
    { name: 'Action', value: 'Get-Paginated-Intents' },
    { name: 'Filters', value: JSON.stringify({ status: 'active' }) },
    { name: 'Limit', value: '50' },
  ],
  signer: createDataItemSigner(wallet),
});

const { Messages } = await result({
  message: msgId,
  process: MARKETPLACE_PROCESS_ID,
});

const intents = JSON.parse(Messages[0].Data);
```

#### `Get-Intent-By-Id`

Get a specific intent with all child intents.

**Parameters:**

| Tag | Type | Required | Description |
|-----|------|----------|-------------|
| `Intent-Id` | string | Yes | The intent ID to retrieve |

**Example (aoconnect):**

```typescript
const msgId = await message({
  process: MARKETPLACE_PROCESS_ID,
  tags: [
    { name: 'Action', value: 'Get-Intent-By-Id' },
    { name: 'Intent-Id', value: intentId },
  ],
  signer: createDataItemSigner(wallet),
});

const { Messages } = await result({
  message: msgId,
  process: MARKETPLACE_PROCESS_ID,
});

const intent = JSON.parse(Messages[0].Data);
console.log('Intent status:', intent.status);
console.log('Child intents:', Object.keys(intent.children || {}).length);
```

#### `Push-ANT-Intent-Resolution`

Manually trigger ANT ownership verification for an intent.

**Parameters:**

| Tag | Type | Required | Description |
|-----|------|----------|-------------|
| `X-Intent-Id` | string | Yes | Intent ID to resolve |

**Example (aoconnect):**

```typescript
const msgId = await message({
  process: MARKETPLACE_PROCESS_ID,
  tags: [
    { name: 'Action', value: 'Push-ANT-Intent-Resolution' },
    { name: 'X-Intent-Id', value: intentId },
  ],
  signer: createDataItemSigner(wallet),
});
```

---

### 💰 Balance Management

All ARIO trading uses an internal balance system for efficiency and atomic operations.

#### `Get-Balance`

Get your ARIO balance in the marketplace.

**Parameters:** None

**Response:**
```json
{
  "address": "your-address",
  "balance": "1000000000", // Available balance in mARIO
  "totalBalance": "5000000000", // Available + locked
  "lockedBalance": "4000000000", // Locked in orders
  "orders": {
    "order-id-1": "2000000000",
    "order-id-2": "2000000000"
  }
}
```

**Example (aoconnect):**

```typescript
const msgId = await message({
  process: MARKETPLACE_PROCESS_ID,
  tags: [{ name: 'Action', value: 'Get-Balance' }],
  signer: createDataItemSigner(wallet),
});

const { Messages } = await result({
  message: msgId,
  process: MARKETPLACE_PROCESS_ID,
});

const balance = JSON.parse(Messages[0].Data);
console.log(`Available: ${balance.balance} mARIO`);
console.log(`Locked in orders: ${balance.lockedBalance} mARIO`);
```

#### `Get-Paginated-Balances`

Get all marketplace balances with pagination (admin/analytics).

**Parameters:**

| Tag | Type | Required | Description |
|-----|------|----------|-------------|
| `Cursor` | string | No | Pagination cursor from previous response |
| `Limit` | number | No | Items per page (default: 100, max: 1000) |
| `Sort-By` | string | No | Field to sort by (default: `balance`) |
| `Sort-Order` | string | No | `asc` or `desc` (default: `desc`) |

**Response:**
```json
{
  "items": [
    {
      "address": "user-address-1",
      "balance": "5000000000",       // Available balance in mARIO
      "lockedBalance": "2000000000", // Locked in orders
      "totalBalance": "7000000000",  // Available + locked
      "orders": {
        "order-id-1": "1000000000",
        "order-id-2": "1000000000"
      }
    }
  ],
  "limit": 100,
  "totalItems": 250,
  "sortBy": "balance",
  "sortOrder": "desc",
  "hasMore": true,
  "nextCursor": "cursor-string"
}
```

**Example (aoconnect):**

```typescript
const msgId = await message({
  process: MARKETPLACE_PROCESS_ID,
  tags: [
    { name: 'Action', value: 'Get-Paginated-Balances' },
    { name: 'Limit', value: '100' },
    { name: 'Sort-By', value: 'totalBalance' },
    { name: 'Sort-Order', value: 'desc' },
  ],
  signer: createDataItemSigner(wallet),
});

const { Messages } = await result({
  message: msgId,
  process: MARKETPLACE_PROCESS_ID,
});

const balances = JSON.parse(Messages[0].Data);
console.log(`Found ${balances.totalItems} accounts`);
balances.items.forEach(account => {
  console.log(`${account.address}: ${account.totalBalance} mARIO`);
});
```

#### Deposit ARIO

Deposit ARIO into your marketplace balance via `Credit-Notice`.

**Example (aoconnect):**

```typescript
// Transfer ARIO to marketplace
const msgId = await message({
  process: ARIO_PROCESS_ID,
  tags: [
    { name: 'Action', value: 'Transfer' },
    { name: 'Recipient', value: MARKETPLACE_PROCESS_ID },
    { name: 'Quantity', value: '10000000000' }, // 10 ARIO
    { name: 'X-Action', value: 'Deposit' }, // Important: marks as deposit
  ],
  signer: createDataItemSigner(wallet),
});

console.log('ARIO deposited to marketplace');
```

#### `Withdraw-Ario`

Withdraw ARIO from your marketplace balance.

**Parameters:**

| Tag | Type | Required | Description |
|-----|------|----------|-------------|
| `Quantity` | string | Yes | Amount to withdraw in mARIO |
| `Recipient` | string | No | Recipient address (default: sender) |

**Example (aoconnect):**

```typescript
const msgId = await message({
  process: MARKETPLACE_PROCESS_ID,
  tags: [
    { name: 'Action', value: 'Withdraw-Ario' },
    { name: 'Quantity', value: '5000000000' }, // 5 ARIO
  ],
  signer: createDataItemSigner(wallet),
});

const { Messages } = await result({
  message: msgId,
  process: MARKETPLACE_PROCESS_ID,
});

console.log('Withdrawal initiated');
```

---

### 🎪 Auction Operations

#### `Bid-On-English-Auction`

Place or update a bid on an English auction.

**Minimum Increment:** 1 ARIO (1000000000 mARIO)

**Parameters:**

| Tag | Type | Required | Description |
|-----|------|----------|-------------|
| `Order-Id` | string | Yes | Auction order ID |
| `Bid-Amount` | string | Yes | Your total bid amount in mARIO |

**Example (aoconnect):**

```typescript
const msgId = await message({
  process: MARKETPLACE_PROCESS_ID,
  tags: [
    { name: 'Action', value: 'Bid-On-English-Auction' },
    { name: 'Order-Id', value: auctionOrderId },
    { name: 'Bid-Amount', value: '15000000000' }, // 15 ARIO
  ],
  signer: createDataItemSigner(wallet),
});

const { Messages } = await result({
  message: msgId,
  process: MARKETPLACE_PROCESS_ID,
});

console.log('Bid placed successfully');
```

#### `Settle-Auction`

Settle an expired English auction (anyone can trigger).

**Parameters:**

| Tag | Type | Required | Description |
|-----|------|----------|-------------|
| `Order-Id` | string | Yes | Auction order ID to settle |

**Example (aoconnect):**

```typescript
const msgId = await message({
  process: MARKETPLACE_PROCESS_ID,
  tags: [
    { name: 'Action', value: 'Settle-Auction' },
    { name: 'Order-Id', value: auctionOrderId },
  ],
  signer: createDataItemSigner(wallet),
});
```

---

### 🔧 Administrative Operations

#### `Withdraw-Fees`

Withdraw accrued marketplace fees (treasury only).

**Parameters:**

| Tag | Type | Required | Description |
|-----|------|----------|-------------|
| `Quantity` | string | Yes | Amount to withdraw in mARIO |
| `Recipient` | string | No | Recipient address (default: treasury) |

**Example (aoconnect):**

```typescript
const msgId = await message({
  process: MARKETPLACE_PROCESS_ID,
  tags: [
    { name: 'Action', value: 'Withdraw-Fees' },
    { name: 'Quantity', value: '1000000000' }, // 1 ARIO
  ],
  signer: createDataItemSigner(treasuryWallet),
});
```

---

### 📡 System Handlers (Automatic)

These handlers are triggered automatically by the system and should not be called directly by users.

#### `Credit-Notice`

Handles incoming token transfers (deposits and ANT orders). Automatically called by token processes.

#### `Debit-Notice`

Confirms transfer completion and resolves child intents. Automatically called by token processes.

#### `Transfer-Error`

Handles transfer failures and cascades intent failures. Automatically called by token processes.

#### `State-Notice`

Resolves ANT ownership verification for intents. Called in response to `Push-ANT-Intent-Resolution`.

---

## Order Types

### Fixed Price Orders

Immediate buy/sell at a specified price.

**Use Case:** Quick trades at known prices

**Example:** Sell 1 ANT for 10 ARIO

### Dutch Auction Orders

Price decreases over time until someone buys.

**Use Case:** Price discovery for unique ANTs

**Parameters:**
- `Price`: Starting price
- `Minimum-Price`: Floor price
- `Decrease-Interval`: Time between decreases (ms)

**Example:** Start at 100 ARIO, decrease by 1 ARIO every hour, minimum 50 ARIO

### English Auction Orders

Competitive bidding with a settlement period.

**Use Case:** Maximum price discovery through competitive bidding

**Flow:**
1. Seller creates auction with expiration time
2. Bidders place/update bids (minimum 1 ARIO increment)
3. Auction expires
4. Anyone calls `Settle-Auction` to finalize
5. Winner receives ANT, losing bids refunded

---

## Complete Trading Examples

### Example 1: Buy ANT with ARIO

```typescript
import { message, result, createDataItemSigner } from '@permaweb/aoconnect';

// 1. Deposit ARIO to marketplace
await message({
  process: ARIO_PROCESS_ID,
  tags: [
    { name: 'Action', value: 'Transfer' },
    { name: 'Recipient', value: MARKETPLACE_PROCESS_ID },
    { name: 'Quantity', value: '20000000000' }, // 20 ARIO
    { name: 'X-Action', value: 'Deposit' },
  ],
  signer: createDataItemSigner(wallet),
});

// 2. Create buy order (must specify which ANT to buy)
const msgId = await message({
  process: MARKETPLACE_PROCESS_ID,
  tags: [
    { name: 'Action', value: 'Create-Order' },
    { name: 'Swap-Token', value: ANT_PROCESS_ID }, // Which ANT to buy
    { name: 'Quantity', value: '10000000000' }, // Offer 10 ARIO
    { name: 'Order-Type', value: 'fixed' },
  ],
  signer: createDataItemSigner(wallet),
});

// Order matches immediately if the specified sell order is still available
```

### Example 2: Sell ANT for ARIO

```typescript
// 1. Ensure you have ARIO balance for listing fee
await message({
  process: ARIO_PROCESS_ID,
  tags: [
    { name: 'Action', value: 'Transfer' },
    { name: 'Recipient', value: MARKETPLACE_PROCESS_ID },
    { name: 'Quantity', value: '2000000000' }, // 2 ARIO for fees
    { name: 'X-Action', value: 'Deposit' },
  ],
  signer: createDataItemSigner(wallet),
});

// 2. Create listing intent
const intentMsgId = await message({
  process: MARKETPLACE_PROCESS_ID,
  tags: [
    { name: 'Action', value: 'Create-Intent' },
    { name: 'X-Intent-Quantity', value: '1' },
    { name: 'X-Intent-Order-Type', value: 'fixed' },
    { name: 'X-Intent-Price', value: '15000000000' }, // 15 ARIO
    { name: 'X-Intent-Expiration-Time', value: String(Date.now() + 604800000) },
  ],
  signer: createDataItemSigner(wallet),
});

const { Messages } = await result({
  message: intentMsgId,
  process: MARKETPLACE_PROCESS_ID,
});

const intentId = JSON.parse(Messages[0].Data)['Intent-Id'];

// 3. Transfer ANT with intent ID
// Order parameters come from the intent created in Step 2
await message({
  process: ANT_PROCESS_ID,
  tags: [
    { name: 'Action', value: 'Transfer' },
    { name: 'Recipient', value: MARKETPLACE_PROCESS_ID },
    { name: 'Quantity', value: '1' },
    { name: 'X-Intent-Id', value: intentId },
    { name: 'X-Order-Action', value: 'Create-Order' },
  ],
  signer: createDataItemSigner(wallet),
});

console.log('ANT listing created!');
```

### Example 3: Dutch Auction

```typescript
// Create Dutch auction that starts at 50 ARIO, decreases by 1 ARIO every hour
const intentMsgId = await message({
  process: MARKETPLACE_PROCESS_ID,
  tags: [
    { name: 'Action', value: 'Create-Intent' },
    { name: 'X-Intent-Quantity', value: '1' },
    { name: 'X-Intent-Order-Type', value: 'dutch' },
    { name: 'X-Intent-Price', value: '50000000000' }, // Start: 50 ARIO
    { name: 'X-Intent-Minimum-Price', value: '10000000000' }, // Floor: 10 ARIO
    { name: 'X-Intent-Decrease-Interval', value: '3600000' }, // 1 hour
    { name: 'X-Intent-Expiration-Time', value: String(Date.now() + 604800000) },
  ],
  signer: createDataItemSigner(wallet),
});

// Then get intent ID and transfer ANT
// (see Example 2 for complete ANT transfer code - only need X-Intent-Id and X-Order-Action)
```

### Example 4: English Auction

```typescript
// Seller creates auction
const intentMsgId = await message({
  process: MARKETPLACE_PROCESS_ID,
  tags: [
    { name: 'Action', value: 'Create-Intent' },
    { name: 'X-Intent-Quantity', value: '1' },
    { name: 'X-Intent-Order-Type', value: 'english' },
    { name: 'X-Intent-Price', value: '10000000000' }, // Starting bid: 10 ARIO
    { name: 'X-Intent-Expiration-Time', value: String(Date.now() + 86400000) }, // 24 hours
  ],
  signer: createDataItemSigner(wallet),
});

// Then get intent ID and transfer ANT
// (see Example 2 for complete ANT transfer code - only need X-Intent-Id and X-Order-Action)

// Bidders place bids (must increment by at least 1 ARIO)
await message({
  process: MARKETPLACE_PROCESS_ID,
  tags: [
    { name: 'Action', value: 'Bid-On-English-Auction' },
    { name: 'Order-Id', value: auctionOrderId },
    { name: 'Bid-Amount', value: '15000000000' }, // 15 ARIO
  ],
  signer: createDataItemSigner(bidderWallet),
});

// After expiration, anyone can settle
await message({
  process: MARKETPLACE_PROCESS_ID,
  tags: [
    { name: 'Action', value: 'Settle-Auction' },
    { name: 'Order-Id', value: auctionOrderId },
  ],
  signer: createDataItemSigner(wallet),
});
```

---

## Testing

### Prerequisites

Before running the tests, ensure you have the following installed:

1. **Lua 5.3 and LuaRocks**: Use the provided installation script
   ```bash
   ./scripts/install-lua-deps.sh
   ```
   This script automatically installs Lua 5.3.1 and LuaRocks 3.9.1 for your operating system (macOS, Linux, or Windows via MSYS2).

### Running Tests

The test suite consists of unit tests (Lua) and integration tests (TypeScript):

**Unit Tests** (Lua with busted):
```bash
pnpm test:unit
```

**Integration Tests** (TypeScript with ao-loader):
```bash
pnpm test:integration
```

**All Tests**:
```bash
pnpm test
```

### E2E Testing (Coming Soon)

End-to-end tests using [ao-localnet](https://github.com/atticusofsparta/ao-localnet-archive) are planned but not yet implemented. The ao-localnet tool requires additional configuration and setup work before it can be reliably integrated for automated E2E testing.

**Current Status**: E2E infrastructure removed pending ao-localnet improvements

**What's Needed**:
- ao-localnet configuration and stability improvements
- Test wallet and process bootstrapping
- Full marketplace workflow tests (deposit → trade → settle)

### Manual Testing

To test the `process.lua` in a real AO environment:

1. Start the AO process: `aos your_process_name [--wallet /path/to/wallet.json]`
2. Deploy a token blueprint for ARIO: `.load-blueprint token`
3. Deploy the marketplace process: `.load src/process.lua`
4. Send messages to test handlers (see API Reference above)
5. Check [ao.link](https://ao.link) for debugging and message results

## Deployment

### Prerequisites

Before deploying, ensure you have:

1. **AO SDK installed**: Install the AO command line tools
   ```bash
	npm i -g https://get_ao.g8way.io
   ```

2. **Wallet file**: An Arweave wallet JSON file for deployment. You can generate one simply by running `aos` in terminal. It should be created in `~/.aos.json`.

### Deployment Steps

1. **Start CLI**:
   ```bash
   aos --wallet /path/to/your/wallet.json
   ```

2. **Deploy the code**:
	```bash
	user@aos-2.0.4[Inbox:1]> .load src/process.lua
	```
	If the code is correct, the CLI will show the standard prompt.

### Deployment Notes

- Use `src/process.lua` which is a self-contained version with all dependencies.

## Project Structure

This project consists of several components organized into different directories:

### Core Process Files (`src/`)

#### Main Process Files
- **`process.lua`** - Main entry point for the ARnS Marketplace process. Handles message routing, validation, and core marketplace functionality including order creation, credit notices, and basic process operations.

- **`ucm.lua`** - ANT Marketplace core logic. Contains the main marketplace functions including order book management, pair indexing, order creation, and error handling. This is the heart of the marketplace functionality.

- **`utils.lua`** - Utility functions used throughout the project. Includes address validation, amount validation, JSON message decoding, pair data validation, fee calculations, and table printing utilities.

### Testing (`tests/`)

- **`unit/`** - Lua unit tests with busted (426 tests, 83% coverage)
- **`integration/`** - TypeScript integration tests with ao-loader (69 tests)
- **`utils/`** - Test utilities and helpers

### Documentation (`docs/`)

- **`adr/`** - Architecture Decision Records (ADRs) documenting key design decisions:
  - **ADR-000: Orderbook Architecture** - Foundational design explaining unidirectional orderbook and order directionality
  - ADR-001: Module Whitelist for ANT Trading
  - ADR-002: Credit-Notice Pattern
  - ADR-003: ARIO Internal Ledger
  - ADR-004: Intent-Based Workflow
  - ADR-005: Class Type Pattern
  - ADR-006: Lazy Module Loading
  - ADR-007: Handler Hooks Pattern
