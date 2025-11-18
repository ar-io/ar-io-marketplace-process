# E2E Tests for AR.IO Marketplace

## Overview

This directory contains end-to-end tests for the AR.IO marketplace process. The tests spawn real AO processes and verify the full marketplace workflow.

## Test Status

### Current Implementation

The test infrastructure is fully implemented with the following components:

1. **Process Management** (`tests/utils/process_manager.ts`)
   - Spawns and manages AR.IO, Marketplace, and ANT processes
   - Persists process IDs to `e2e-test.json` for reuse across test runs
   - Validates process health before reusing

2. **GraphQL Utilities** (`tests/utils/graphql.ts`)
   - Query messages by tags
   - Poll for Credit-Notice and Debit-Notice messages
   - Wait for intent resolution

3. **Process Wrappers**
   - `ArioProcess` - Wraps ARIO token interactions
   - `MarketplaceProcess` - Extended with E2E helper methods
   - High-level methods for listing and buying

4. **Test Cases** (`tests/e2e/fixed-price.test.ts`)
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
# Run e2e tests (uses existing processes if e2e-test.json exists)
pnpm test:e2e

# Clean up and spawn new processes
pnpm test:e2e:clean

# Run quick smoke test to generate test-output.json
npx tsx --test tests/e2e/smoke-test.ts
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

## Configuration

Required environment variables (see `.env.example`):
- `WALLET_PATH` - Path to test wallet JSON file
- `AOS_MODULE` - AOS module ID
- `SCHEDULER` - Scheduler ID
- `AUTHORITY` - Authority address
- `CU_URL` - Compute unit URL
- `GRAPHQL_URL` - Arweave GraphQL endpoint

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

