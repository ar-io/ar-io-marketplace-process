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

6. **Test Cases** (`tests/e2e/fixed-price.test.ts`)
   - List ANT at fixed price
   - Buy fixed price listing
   - Handle overpayment with refund
   - Cancel listings
   - Error handling (insufficient payment, invalid order ID)
   - Intent pagination and filtering
   - Order querying by multiple criteria

### Known Issues

**Credit-Notice Flow**: The current tests attempt to create orders by sending ANT Transfer messages with X-* tags (e.g., `X-Order-Type`, `X-Price`). However, these transfers are not resulting in orders being created in the marketplace.

**Possible Causes**:
1. The ANT process may not forward X-* tags in Credit-Notice messages
2. The marketplace Credit-Notice handler may not process these tags correctly
3. The marketplace may expect a different workflow (intent-based vs direct transfer)

**Next Steps**:
1. Investigate the marketplace Credit-Notice handler implementation
2. Verify if X-* tags are forwarded by the ANT process
3. Consider using the intent-based workflow explicitly
4. Add integration tests that mock the Credit-Notice flow

## Running Tests

```bash
# Recommended: Use setup script first
npx tsx scripts/setup-e2e.ts

# Run all e2e tests (uses existing processes if e2e-test.json exists)
pnpm test:e2e

# Clean up and spawn new processes
pnpm test:e2e:clean

# Run quick smoke test to generate test output
npx tsx --test tests/e2e/smoke-test.ts

# Run specific test file
npx tsx --test tests/e2e/fixed-price.test.ts

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

## Advanced Configuration

### Custom Timeouts

Tests use generous timeouts (450s) for order creation/execution on localnet. To adjust:

Edit test files and modify timeout parameters in `waitForNewOrders()`, `waitForOrderStatus()`, etc.

### Process Reuse

By default, tests reuse processes from `e2e-test.json` to speed up test runs. To force new processes:

```bash
pnpm test:e2e:clean
```

### Fresh ANTs

Each test that lists an ANT spawns a fresh ANT to ensure clean state. This is because after transferring an ANT to the marketplace, the test wallet no longer owns it.

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

## Contributing

When adding new test cases:
1. Follow the existing pattern of separate test suites per feature
2. Use descriptive test names that clearly state what is being tested
3. Add appropriate logging for debugging
4. Clean up any spawned processes or resources
5. Update this README if adding new utilities or changing architecture

