# Bug Fixes Summary

## Issues Identified from E2E Test Output

### 1. ✅ Buy Intent Missing Required Parameters (FIXED)
**Error:** `Failed to create buy intent: X-Intent-Swap-Token required for Create-Order (line 5029)`

**Root Cause:** The `buyFixedPriceListing` method in `MarketplaceProcess` was not passing the required `swapToken` and `quantity` parameters when creating a buy intent.

**Fix:**
- Updated `tests/utils/marketplace_process.ts` - `buyFixedPriceListing()` method
- Added `swapToken: arioProcessId` and `quantity: amount` to the `createIntent()` call
- Added error handling to check for `Invalid-Create-Intent-Notice` before parsing JSON

**Integration Tests Added:**
- ✅ `should fail to create buy intent without X-Intent-Swap-Token`
- ✅ `should fail to create buy intent without X-Intent-Quantity`
- ✅ `should successfully create buy intent with all required parameters`

All 3 new tests passing in `tests/integration/intent.test.ts`

---

### 1b. 🔧 Buy Transfer Missing X-Swap-Token Tag (IN PROGRESS)
**Issue:** When buying with ARIO, the ARIO transfer to marketplace was missing the `X-Swap-Token` tag (should be the ANT process ID being purchased).

**Root Cause:** The `buyFixedPriceListing` method didn't fetch the order details to get the ANT process ID before sending the ARIO transfer.

**Fix Applied:**
- Added `Step 0` to fetch order details using `getOrderById(orderId)`
- Extract `antProcessId` from `orderData.dominantToken`
- Include `X-Swap-Token: antProcessId` in the ARIO transfer tags

**Status:** Code fixed, awaiting e2e verification

---

### 2. 🔍 Cancel Order Authorization Issue
**Error:** `Unauthorized to cancel this order (line 5534)`

**Root Cause:** When an ANT transfer creates an order, the marketplace registers the order `creator` as the `sender` from the Credit-Notice (the wallet address). The cancel check verifies `msg.From == currentOrderEntry.creator`, but we need to verify what `msg.From` is being set to in the test.

**Status:** Identified, needs further investigation in e2e tests

**Note:** The order creator is set to `args.sender` in `fixed_price.lua:62`, and the cancel handler checks `msg.From == currentOrderEntry.creator` in `ucm.lua:433`. Need to verify that the test wallet is signing the cancel request correctly.

---

### 3. 🚨 ANT Credit-Notice Not Forwarded (CRITICAL BLOCKER)
**Observation:** 
- ANT transfers complete successfully
- Intents are created
- But orders NEVER appear in marketplace (0 orders after 450s)
- Intent stays in `pending` status (never transitions to `active` or `completed`)

**Root Cause:** The ANT process spawned by `ANT.spawn()` is **not forwarding Credit-Notices** to the marketplace. When we transfer the ANT to the marketplace, the marketplace's Credit-Notice handler never fires.

**Hypothesis:** 
1. ANT process not fully initialized after `ANT.spawn()` returns
2. Missing delay/verification step before using freshly spawned ANT
3. Possible SDK issue with Credit-Notice forwarding setup

**Fix Attempted:**
- Added 5-second delay after marketplace initialization in `process_manager.ts` ✅
- Added 10-second delay after ANT spawning + Info verification 🔧 (testing)
- Increased all timeout values from 300s to 450s ✅

**Status:** 🔧 Testing ANT initialization delay fix

**Impact:** This is the PRIMARY BLOCKER preventing any listing tests from succeeding

---

## Changes Made

### Files Modified:
1. **tests/utils/marketplace_process.ts**
   - Fixed `buyFixedPriceListing()` to include required intent parameters
   - Increased timeout defaults to 450s for all wait methods
   - Added error handling for invalid intent creation

2. **tests/utils/process_manager.ts**
   - Added 5-second initialization delay after marketplace spawn

3. **tests/utils/graphql.ts**
   - Increased `DEFAULT_TIMEOUT` to 450s

4. **tests/e2e/fixed-price.test.ts**
   - Updated all timeout parameters from 300s to 450s
   - Fixed cancel test to find order by ANT process ID instead of array position

5. **tests/integration/intent.test.ts** ✅
   - Added 3 new tests for buy intent parameter validation
   - All tests passing

---

## Next Steps
1. Run e2e tests to verify buy intent fix
2. Investigate cancel authorization issue (why is `msg.From` not matching order creator?)
3. Analyze first listing timeout with profiling data
4. Consider adding integration test for the full Credit-Notice → Create-Order workflow

