# E2E Tests for AR.IO Marketplace

## Overview

This directory contains end-to-end tests for the AR.IO marketplace process. The tests spawn real AO processes on a local AO network and verify the full marketplace workflow.

## Quick Start

```bash
# 1. Ensure ao-localnet is running
pnpm localnet:start

# 2. Bootstrap the localnet (first time only)
pnpm localnet:bootstrap

# 3. Setup and validate e2e environment
npx tsx scripts/setup-e2e.ts

# 4. Run e2e tests
pnpm test:e2e

# 5. Clean slate (spawns new processes)
pnpm test:e2e:clean
```

## Prerequisites

### 1. AO Localnet Running

The e2e tests require a running AO localnet with all services healthy:

```bash
# Start localnet
pnpm localnet:start

# Check status
docker ps --filter "name=ao-localnet"

# View logs if needed
docker compose logs -f
```

### 2. Environment Configuration

Ensure your `.env` file has all required variables:

```bash
# Check configuration
npx tsx scripts/setup-e2e.ts --validate-only

# Or get config from localnet
pnpm localnet:config
```

Required variables:
- `GRAPHQL_URL` - GraphQL endpoint (default: http://localhost:4000/graphql)
- `GATEWAY_URL` - Arweave gateway (default: http://localhost:4000)
- `CU_URL` - Compute unit URL (default: http://localhost:4004)
- `MU_URL` - Messenger unit URL (default: http://localhost:4002)
- `SCHEDULER` - Scheduler process ID
- `MODULE_ID` - AOS module ID
- `WALLET_PATH` - Path to test wallet (default: tests/fixtures/localnet_wallet.json)
- `AUTHORITY` - Authority address (must match wallet)

## Test Infrastructure

### Current Implementation

The test infrastructure is fully implemented with the following components:

1. **Process Management** (`tests/utils/process_manager.ts`)
   - Spawns and manages AR.IO, Marketplace, and ANT processes
   - Persists process IDs to `e2e-test.json` for reuse across test runs
   - Validates process health before reusing
   - Automatically spawns fresh ANTs for each test to ensure clean state

2. **Health Checks** (`tests/utils/localnet_health.ts`)
   - Validates all localnet services are running
   - Checks response times and connectivity
   - Provides detailed health status

3. **Configuration Validation** (`tests/utils/config_validator.ts`)
   - Validates all required environment variables
   - Checks file paths and URLs
   - Provides helpful error messages

4. **GraphQL Utilities** (`tests/utils/graphql.ts`)
   - Query messages by tags
   - Poll for Credit-Notice and Debit-Notice messages
   - Wait for intent resolution

5. **Process Wrappers**
   - `ArioProcess` - Wraps ARIO token interactions
   - `MarketplaceProcess` - Extended with E2E helper methods
   - High-level methods for listing and buying

6. **Test Helpers** (`tests/utils/test_helpers.ts`)
   - Helper functions for auction creation
   - Intent status tracking utilities
   - Fresh ANT spawning for each test
   - Price calculation for Dutch auctions
   - Multi-wallet generation (for future bidding tests)

7. **Test Cases**
   - **Fixed Price** (`tests/e2e/fixed-price.test.ts`) - List/buy/cancel ANT at fixed price, error handling
   - **Intent Workflow** (`tests/e2e/intent-workflow.test.ts`) - Create intents, track status, pagination, error scenarios
   - **Balance Management** (`tests/e2e/balance-management.test.ts`) - Deposit/withdraw ARIO, balance queries, fee deduction
   - **Module Whitelist** (`tests/e2e/module-whitelist.test.ts`) - ANT module whitelist enforcement
   - **Dutch Auctions** (`tests/e2e/dutch-auction.test.ts`) - Creation, validation, price calculation, expiration
   - **English Auctions** (`tests/e2e/english-auction.test.ts`) - Creation, bidding, settlement validation
   - **Pagination & Filtering** (`tests/e2e/pagination-filtering.test.ts`) - Intent/order pagination, filtering, sorting
   - **Info Endpoint** (`tests/e2e/info-endpoint.test.ts`) - Comprehensive info structure and statistics validation

### Test Coverage

The e2e test suite now comprehensively covers:

**Core Workflows**:
- Fixed-price listings (create, buy, cancel)
- Dutch auctions (creation, validation, expiration)
- English auctions (creation, settlement validation)
- Intent-based workflow (create, track, resolve)

**Balance Management**:
- ARIO deposits via Credit-Notice
- ARIO withdrawals
- Balance queries
- Listing fee deduction

**Security & Validation**:
- ANT module whitelist enforcement
- Parameter validation (missing fields, invalid values)
- Error handling (insufficient payment, invalid IDs)
- Authorization checks

**Query & Pagination**:
- Intent pagination with limit/cursor
- Order filtering by status
- Trading pair filtering
- Combined filters
- Sorting parameters

**System Information**:
- Info endpoint structure validation
- Activity statistics
- Intent statistics
- UCM statistics

## Running Tests

```bash
# Recommended: Use setup script first
npx tsx scripts/setup-e2e.ts

# Run all e2e tests (uses existing processes if e2e-test.json exists)
pnpm test:e2e

# Clean up and spawn new processes
pnpm test:e2e:clean

# Run specific test suites
npx tsx --test tests/e2e/fixed-price.test.ts
npx tsx --test tests/e2e/intent-workflow.test.ts
npx tsx --test tests/e2e/balance-management.test.ts
npx tsx --test tests/e2e/module-whitelist.test.ts
npx tsx --test tests/e2e/dutch-auction.test.ts
npx tsx --test tests/e2e/english-auction.test.ts
npx tsx --test tests/e2e/pagination-filtering.test.ts
npx tsx --test tests/e2e/info-endpoint.test.ts

# Run quick smoke test
npx tsx --test tests/e2e/smoke-test.ts

# Validate configuration only
npx tsx scripts/setup-e2e.ts --validate-only

# Skip health checks (use with caution)
npx tsx scripts/setup-e2e.ts --skip-health

# Clean start (removes e2e-test.json)
npx tsx scripts/setup-e2e.ts --clean
```

## Test Output Logging

All e2e tests now generate a detailed `test-output.json` file that includes:

- **Test Run Metadata**: Test run ID, timestamps, duration
- **Process IDs**: All spawned process IDs (ARIO, Marketplace, ANT)
- **Workflows**: Each test workflow with:
  - Start/end timestamps
  - Success/failure status
  - Error messages if failed
  - All messages sent during the workflow
- **Messages**: Detailed logging for each AO message:
  - Action type
  - Target process ID
  - All tags sent (including X-* custom tags)
  - Message ID returned
  - Duration in milliseconds
  - Success/failure status
- **Intents**: Intent tracking (if applicable):
  - Intent ID
  - Status changes
  - Related messages
  - Resolution time
- **Summary Statistics**: Totals for messages, intents, successes, and failures

### Example Output

```json
{
  "testRunId": "test-1763405661374",
  "processes": {
    "ario": "TLzO2bcbMOPXaDVJ7HyMpq1qHFnVDaVZt3CKkYZtpk8",
    "marketplace": "lqEziBaGPWz917r63ZVXSVVbZkwegGHLP58cyTWPBEs",
    "ant": "6mSi5PhSBcloDnTDXzJa2u5AQoV1XlkjdBRgY2nrCXA"
  },
  "workflows": {
    "smoke-test-listing": {
      "started": 1763405922666,
      "status": "failed",
      "messages": [
        {
          "action": "Transfer ANT (List Fixed Price)",
          "processId": "6mSi5PhSBcloDnTDXzJa2u5AQoV1XlkjdBRgY2nrCXA",
          "tags": [
            { "name": "Action", "value": "Transfer" },
            { "name": "X-Order-Type", "value": "fixed" },
            { "name": "X-Price", "value": "1000000" }
          ],
          "status": "success",
          "messageId": "tv7EaxhEHameGB4b4HcBnjSlU6uLmUk9XcLJOFNgeEk",
          "duration": 62334
        }
      ],
      "error": "Order not created after 5s"
    }
  },
  "summary": {
    "totalMessages": 1,
    "successfulMessages": 1,
    "failedMessages": 0
  }
}
```

This output is invaluable for debugging transaction flows and understanding why operations succeed or fail.

## Troubleshooting

### Localnet Not Running

**Symptom**: Health checks fail, tests can't connect to services

**Solution**:
```bash
# Check if containers are running
docker ps --filter "name=ao-localnet"

# Start localnet
pnpm localnet:start

# Wait for services to be healthy
npx tsx scripts/setup-e2e.ts
```

### Invalid Configuration

**Symptom**: Missing environment variables, invalid paths

**Solution**:
```bash
# Validate configuration
npx tsx scripts/setup-e2e.ts --validate-only

# Get config from localnet
pnpm localnet:config

# Update your .env file with the output
```

### Process Spawn Failures

**Symptom**: Tests fail to spawn processes, timeout errors

**Solution**:
```bash
# Clean and restart
rm -f e2e-test.json
pnpm test:e2e:clean

# Check localnet has been seeded
pnpm localnet:seed

# Check wallet has AR balance
# (bootstrap script should have minted AR)
```

### Tests Timeout Waiting for Orders

**Symptom**: Tests timeout waiting for orders to be created or executed

**Possible Causes**:
1. Credit-Notice not being sent by ANT process
2. Marketplace not processing Credit-Notice
3. Intent workflow not completing

**Solution**:
```bash
# Check test output log for detailed message flow
cat test-output.log

# Verify ANT and marketplace processes are responsive
# Tests will show detailed error messages
```

### Stale Process Configuration

**Symptom**: Tests fail with "Process not found" or validation errors

**Solution**:
```bash
# Force clean start
rm -f e2e-test.json
pnpm test:e2e
```

## Test Patterns and Best Practices

### Intent Workflow Testing

Intent-based workflows are fundamental to the marketplace. Tests follow this pattern:

```typescript
// 1. Create intent
const intentResult = await marketplaceProcess.createIntent({
  action: 'Create-Order',
  orderType: 'fixed',
  swapToken: arioProcessId,
  quantity: '1',
  price: '1000000',
});

// 2. Get intent ID
const intentData = JSON.parse(intentResult.Data);
const intentId = intentData['Intent-Id'];

// 3. Track intent status
const intent = await marketplaceProcess.getIntentById(intentId);
const intentInfo = JSON.parse(intent.Data);
console.log('Intent status:', intentInfo.status); // 'pending', 'completed', 'failed'

// 4. Verify intent resolution
// After Credit-Notice, intent moves to 'completed' or is pruned
```

### Module Whitelist Testing

Testing ANT module whitelist enforcement:

```typescript
// Whitelisted module (default ANT module)
const WHITELISTED_MODULE = 'drhsJZSyX8InDsd5EAfQDTgdKnD_wvjddHKY3KDPdf8';

// Non-whitelisted module for negative testing
const NON_WHITELISTED_MODULE = '9afQ1PLf2mrshqCTZEzzJTR2gWaC9zHYWyqH3_1234';

// Transfer with module tag
await ao.message({
  process: antProcessId,
  tags: [
    { name: 'Action', value: 'Transfer' },
    { name: 'From-Module', value: WHITELISTED_MODULE },
    // ... other tags
  ],
});
```

### Auction Testing

Dutch and English auctions require time-based testing:

```typescript
import { createDutchAuction, createEnglishAuction } from '../utils/test_helpers.js';

// Create Dutch auction
const { intentId, expirationTime } = await createDutchAuction(
  marketplaceProcess,
  {
    swapToken: arioProcessId,
    quantity: '1',
    startingPrice: '10000000',
    minimumPrice: '5000000',
    decreaseInterval: '60000',
    durationMs: 3_600_000, // 1 hour
  }
);

// Create English auction
const { intentId, expirationTime } = await createEnglishAuction(
  marketplaceProcess,
  {
    swapToken: arioProcessId,
    quantity: '1',
    startingBid: '1000000',
    durationMs: 3_600_000, // 1 hour
  }
);
```

### Balance Management

Testing ARIO balance operations:

```typescript
// Deposit ARIO
await marketplaceProcess.depositArio('1000000000', arioProcessId, testAddress);

// Check balance
const balance = await marketplaceProcess.getMarketplaceBalance(testAddress);
console.log('Balance:', balance);

// Withdraw ARIO
await marketplaceProcess.withdrawArio('500000000');

// Verify listing fee deduction
// Creating an intent costs 1 ARIO (1000000 micro-ARIO)
const balanceBefore = await marketplaceProcess.getMarketplaceBalance(testAddress);
await marketplaceProcess.createIntent({ /* ... */ });
const balanceAfter = await marketplaceProcess.getMarketplaceBalance(testAddress);
// balanceAfter < balanceBefore (fee deducted)
```

## Advanced Configuration

### Custom Timeouts

Tests use generous timeouts (450s-1800s) for order creation/execution on localnet. To adjust:

Edit test files and modify timeout parameters in `waitForNewOrders()`, `waitForOrderStatus()`, etc.

### Process Reuse

By default, tests reuse processes from `e2e-test.json` to speed up test runs. To force new processes:

```bash
pnpm test:e2e:clean
```

### Fresh ANTs

Each test that lists an ANT spawns a fresh ANT to ensure clean state. This is because after transferring an ANT to the marketplace, the test wallet no longer owns it.

### Test Helpers

Use helper functions from `tests/utils/test_helpers.ts`:

```typescript
import {
  waitForIntentStatus,
  createDutchAuction,
  createEnglishAuction,
  spawnFreshAnt,
  pollMarketplaceUntil,
  formatArio,
} from '../utils/test_helpers.js';

// Wait for intent to complete
await waitForIntentStatus(marketplaceProcess, intentId, 'completed', 120000);

// Spawn fresh ANT
const antId = await spawnFreshAnt(antRegistryProcessId);

// Poll until condition met
await pollMarketplaceUntil(
  marketplaceProcess,
  (info) => info.activity.totalOrders > 0,
  120000
);
```

## Test Architecture

### Process Lifecycle

```
┌─────────────────────────────────────────┐
│ getOrSpawnProcesses()                    │
│                                          │
│  1. Check for e2e-test.json             │
│  2. If exists, validate processes       │
│  3. If invalid or missing, spawn new    │
│  4. Save to e2e-test.json               │
└─────────────────────────────────────────┘
```

### Order Creation Flow (Expected)

```
User                ANT               Marketplace
 │                   │                     │
 │──Transfer────────>│                     │
 │  (with X-* tags)  │                     │
 │                   │                     │
 │                   │──Credit-Notice─────>│
 │                   │   (forwards tags)   │
 │                   │                     │
 │                   │                     │──Create Order
 │                   │                     │
 │<──────────────────┴─────────────────────│
           Debit-Notice (ANT transfer)
```

## Utilities

### MarketplaceProcess Helper Methods

```typescript
// High-level listing
await marketplaceProcess.listAntForFixedPrice(antId, price, swapToken);
await marketplaceProcess.listAntForDutchAuction(antId, params);
await marketplaceProcess.listAntForEnglishAuction(antId, params);

// High-level buying
await marketplaceProcess.buyFixedPriceListing(arioId, orderId, amount);
await marketplaceProcess.bidOnEnglishAuction(arioId, orderId, bidAmount);

// Polling helpers
await marketplaceProcess.waitForNewOrders(previousCount, timeout);
await marketplaceProcess.waitForOrderStatus(orderId, status, timeout);
await marketplaceProcess.waitForOrderCountChange(status, previousCount, timeout);
```

### GraphQL Utilities

```typescript
// Query messages
const creditNotices = await queryCreditNotices(processId, filters);
const debitNotices = await queryDebitNotices(processId, filters);
const intentMessages = await queryIntentMessages(intentId, processId);

// Poll for resolution
await waitForIntentResolution(intentId, processId, timeout);
```

## Troubleshooting E2E Tests

### Intent Workflow Issues

**Symptom**: Intent created but order not appearing

**Causes**:
- Credit-Notice not being sent by ANT
- Marketplace not processing Credit-Notice
- Module whitelist rejection

**Solutions**:
```bash
# Check test output log for Credit-Notice flow
cat test-output.log

# Verify ANT is responsive
# Check intent status - should show 'failed' if rejected

# Check module whitelist - default ANT module should be whitelisted
```

### Module Whitelist Failures

**Symptom**: Order not created despite valid intent and transfer

**Solution**:
- Verify ANT was spawned with whitelisted module
- Default ANT module: `drhsJZSyX8InDsd5EAfQDTgdKnD_wvjddHKY3KDPdf8`
- Check marketplace whitelist configuration
- Look for Intent-Resolved message with failure reason

### Balance Management Issues

**Symptom**: Insufficient balance errors

**Solution**:
```bash
# Ensure ARIO deposit before operations
await marketplaceProcess.depositArio('10000000000', arioProcessId, testAddress);

# Check current balance
const balance = await marketplaceProcess.getMarketplaceBalance(testAddress);
console.log('Current balance:', balance);

# Remember: Intent creation costs 1 ARIO fee
```

### Auction Test Failures

**Symptom**: Auction tests timeout

**Causes**:
- Expiration time validation failures
- Missing required parameters
- Time-based calculations incorrect

**Solutions**:
- Use relative timestamps (Date.now() + duration)
- Ensure expirationTime is in the future
- Verify minimumPrice < startingPrice for Dutch auctions
- Use test helpers for auction creation

### Pagination Issues

**Symptom**: nextCursor errors or unexpected results

**Solution**:
- Verify limit parameter is set correctly
- Check hasMore flag before using nextCursor
- Ensure sufficient items exist for pagination test

## Contributing

When adding new test cases:
1. Follow the existing pattern of separate test suites per feature
2. Use descriptive test names that clearly state what is being tested
3. Add appropriate logging for debugging (use `profile()` helper)
4. Spawn fresh ANTs for each test that needs one
5. Use test helpers from `test_helpers.ts` for common operations
6. Add timeout handling for async operations
7. Clean up any spawned processes or resources
8. Update this README if adding new utilities or changing architecture
9. Add test to appropriate describe block
10. Ensure test can run independently (no order dependencies)

