# ADR-004: Intent-Based Workflow Pattern

## Status

Accepted

## Context

The ARNS Marketplace handles ANT (Arweave Name Token) transfers, which are fundamentally different from ARIO internal balance operations:

1. **Cross-Process Communication**: ANT transfers involve external ANT processes that the marketplace doesn't control
2. **Asynchronous Execution**: Transfers don't complete immediately - they require message round-trips
3. **Multi-Step Workflows**: Listing an ANT involves: create order → transfer ANT → confirm ownership
4. **Failure Scenarios**: External processes can fail, timeout, or behave maliciously
5. **State Consistency**: Marketplace must track partial completion and handle rollbacks

Without a robust tracking mechanism, the marketplace would face:

- **Lost Assets**: ANTs sent but never confirmed could be stuck in limbo
- **Inconsistent State**: Orders created but ANTs never received
- **Poor UX**: Users don't know if their multi-step action succeeded
- **No Error Recovery**: Failed transfers have no way to notify users or rollback
- **Memory Leaks**: Partial state accumulates without cleanup

Traditional approaches like polling (checking state repeatedly) or optimistic updates (assume success) are inadequate:

- **Polling**: Expensive, slow, unbounded message costs
- **Optimistic**: Unsafe, can create invalid state
- **Callbacks**: Not guaranteed in distributed systems
- **Timeouts**: Hard to tune, can fail prematurely or waste resources

The marketplace needs a pattern that:
- Tracks multi-step workflows reliably
- Handles both success and failure paths
- Cleans up expired/abandoned operations
- Provides user visibility into progress
- Integrates with marketplace operations (fees, refunds, etc.)

## Decision

We will implement an **Intent-Based Workflow Pattern** using a parent/child intent hierarchy with state machine tracking. This pattern:

1. **Creates parent intents** for user-initiated multi-step operations
2. **Generates child intents** for each asynchronous external action
3. **Tracks state transitions** through a well-defined state machine
4. **Resolves via notice handlers** (Debit-Notice, State-Notice)
5. **Cascades failures** from child to parent with error context
6. **Prunes expired intents** using TTL-based cleanup
7. **Charges listing fees** upfront to prevent spam

### Intent Hierarchy

```
Parent Intent (User-initiated)
├── Status: pending → active → settling → completed/failed
├── TTL: 24 hours
├── Listing Fee: Charged at creation (duration-based)
└── Child Intents (System-generated)
    ├── Child 1: Transfer ANT to seller
    │   ├── Status: pending → resolved
    │   └── Expected: Debit-Notice from ANT process
    └── Child 2: Transfer ARIO to buyer
        ├── Status: pending → resolved
        └── Expected: Debit-Notice from ARIO process
```

**Key Concepts**:
- **Parent Intent**: Represents the user's goal (e.g., "Create-Order", "Cancel-Order", "Settle-Auction")
- **Child Intent**: Represents a single external action required to complete the parent
- **Resolution**: Child intent resolves when expected response arrives (Debit-Notice or State-Notice)
- **Completion**: Parent completes when all children resolve successfully
- **Failure**: Any child failure cascades to parent, entire intent fails

### Intent Types

```lua
-- In constants.lua
constants.INTENT_TYPES = {
    PARENT = 'parent', -- User-initiated
    CHILD = 'child',   -- System-generated
}
```

**Parent Intent Fields**:
```lua
{
    intentId = "1",              -- Auto-incrementing counter
    type = "parent",
    initiator = "user-address",  -- Who started this intent
    parentIntentId = nil,        -- Always nil for parents
    childIntentIds = {           -- Map for O(1) lookup
        ["2"] = true,
        ["3"] = true
    },
    action = "Create-Order",     -- What action this intent represents
    status = "pending",          -- Current state
    createdAt = 1234567890,      -- Timestamp
    ttl = 1234567890 + 86400000, -- Expiration (24h from creation)
    resolvedAt = nil,            -- When transitioned to active/settling
    completedAt = nil,           -- When reached terminal state
    failureReason = nil,         -- Error message if failed
    forwardedTags = { ... }      -- Tags to include in responses
}
```

**Child Intent Fields**:
```lua
{
    intentId = "2",              -- Auto-incrementing counter
    type = "child",
    initiator = "marketplace-id", -- ao.id (marketplace process)
    parentIntentId = "1",        -- Reference to parent
    action = "Transfer",         -- Always "Transfer" for children
    expectedMessage = "Debit-Notice", -- What response we expect
    expectedFrom = "ant-process-id",  -- Which process should respond
    status = "pending",          -- Current state
    createdAt = 1234567890,      -- Timestamp
    resolvedAt = nil,            -- When resolved
    failureReason = nil,         -- Error if failed
    forwardedTags = { ... }      -- Context for this transfer
}
```

### State Machine

**Parent Intent States**:
```
pending → active → settling → completed
              ↓         ↓         ↓
            failed    failed    failed
```

- **pending**: Intent created, waiting for user's ANT Credit-Notice
- **active**: ANT received, processing order creation
- **settling**: Order created, waiting for child transfers to complete
- **completed**: All children resolved successfully
- **failed**: Any validation or child transfer failed

**Child Intent States**:
```
pending → resolved
    ↓
  failed
```

- **pending**: Transfer sent, waiting for Debit-Notice/State-Notice
- **resolved**: Expected notice received
- **failed**: Transfer-Error received or parent failed

### Intent Creation

Users create intents via `Create-Intent` message:

```lua
-- Handler: Create-Intent
function intents.createIntentHandler(msg)
    local intentAction = msg.Tags['X-Intent-Action']
    assert(intentAction, 'X-Intent-Action required')
    
    local intentParams = {
        Action = intentAction,
        ['Order-Type'] = msg.Tags['X-Intent-Order-Type'],
        ['Swap-Token'] = msg.Tags['X-Intent-Swap-Token'],
        Quantity = msg.Tags['X-Intent-Quantity'],
        Price = msg.Tags['X-Intent-Price'],
        ['Expiration-Time'] = msg.Tags['X-Intent-Expiration-Time'],
        -- ... more params
    }
    
    -- Create parent intent (charges listing fee here)
    local intent = intents.createParentIntent(msg, intentAction, intentParams)
    
    return json.encode({
        ['Intent-Id'] = intent.intentId,
        Status = 'Success',
    })
end
```

**Listing Fee Calculation**:
```lua
function intents.calculateListingFee(expirationTime, currentTimestamp)
    local listingFee = bint(constants.FEE.LISTING_FEE_ARIO) -- 1 ARIO base
    
    if not expirationTime then
        return tostring(listingFee), nil
    end
    
    local listingDurationMs = bint(expirationTime) - bint(currentTimestamp)
    assert(listingDurationMs > bint(0), 'Expiration time must be in the future')
    assert(listingDurationMs <= bint(constants.LISTING.MAX_EXPIRATION_MS), 
           'Expiration time cannot exceed 30 days')
    
    -- Calculate fee based on duration (1 ARIO per day)
    local listingDurationHours = tonumber(tostring(listingDurationMs / bint(3600000)))
    local hoursPerFee = constants.FEE.LISTING_FEE_MULTIPLIER_HOURS * 24 -- 24 hours
    local feeMultiplier = math.ceil(listingDurationHours / hoursPerFee)
    
    listingFee = listingFee * bint(feeMultiplier)
    return tostring(listingFee), nil
end
```

**Fee Examples**:
- 1-day listing: 1 ARIO
- 7-day listing: 7 ARIO
- 30-day listing: 30 ARIO
- No expiration: 1 ARIO (base fee)

**Why charge upfront?**:
- Prevents spam (free intents would enable DoS)
- Commits user to completion (sunk cost)
- Pays for state storage during TTL period

### Intent Resolution Flow

**Step 1: User Creates Intent**
```
User → Marketplace: Create-Intent
  Tags:
    X-Intent-Action: Create-Order
    X-Intent-Order-Type: fixed
    X-Intent-Swap-Token: ARIO-process-id
    X-Intent-Quantity: 1
    X-Intent-Price: 100000000000
    
Marketplace deducts listing fee from user's internal ARIO balance
Marketplace creates parent intent with status "pending"
Marketplace → User: Intent-Created notice with Intent-Id
```

**Step 2: User Sends ANT with Intent ID**
```
User → ANT Process: Transfer
  Recipient: marketplace-id
  Quantity: 1
  X-Intent-Id: "1"
  X-Order-Action: Create-Order
  (plus other order params)

ANT Process → Marketplace: Credit-Notice
  Sender: user-address
  Quantity: 1
  X-Intent-Id: "1"
  X-Order-Action: Create-Order
  From-Module: ant-module-id

Marketplace validates:
  ✓ Intent "1" exists
  ✓ Intent status is "pending"
  ✓ Sender matches intent.initiator
  ✓ Intent hasn't expired (< TTL)
  ✓ ANT module is whitelisted

Marketplace transitions intent: pending → active
Marketplace creates order in orderbook
Marketplace checks if any child intents were created
  If no children: complete intent immediately
  If children exist: transition to "settling"
```

**Step 3: Child Intent Resolution (if applicable)**
```
If order creation triggered ANT transfers (e.g., immediate match):

Marketplace → ANT Process: Transfer
  Recipient: buyer-address
  Quantity: 1
  X-Intent-Id: "2" (child intent)

Marketplace creates child intent:
  parentIntentId: "1"
  expectedFrom: ant-process-id
  expectedMessage: Debit-Notice

ANT Process → Marketplace: Debit-Notice
  X-Intent-Id: "2"

Marketplace validates:
  ✓ Intent "2" exists
  ✓ Intent type is "child"
  ✓ Sender matches child.expectedFrom

Marketplace resolves child intent: pending → resolved
Marketplace checks parent's children:
  All children resolved? → complete parent
  Any pending? → keep parent in "settling"
```

**Step 4: Parent Completion**
```
When all children resolve (or no children created):

Marketplace transitions parent: settling → completed
Marketplace prunes parent + all children from Intents global
Marketplace → User: Intent-Resolved notice
  Intent-Id: "1"
  Status: completed
  Intent-Action: Create-Order
```

### Child Intent Creation

Child intents are created automatically when transfers are needed:

```lua
-- In ucm.lua
function ucm.transferWithIntent(recipient, quantity, token, handledMsg)
    local intents = require('intents')
    
    -- Construct send parameters
    local sendParams = {
        Target = token,
        Action = 'Transfer',
        Tags = {
            Recipient = recipient,
            Quantity = quantity,
        },
    }
    
    -- Add intent tracking (creates child intent if parent exists)
    sendParams = intents.createSendWithIntent(sendParams, handledMsg, {
        Recipient = recipient,
        Quantity = quantity,
        Token = token,
    })
    
    utils.Send(handledMsg, sendParams)
end
```

**When child intents are created**:
- ANT transfer to seller (order fills immediately)
- ANT transfer to buyer (cancellation, settlement)
- ANT transfer for any cross-process operation

**Important**: ARIO withdrawals do NOT create child intents - they use `ucm.transfer()` instead of `ucm.transferWithIntent()` (see ADR-003).

### Debit-Notice Handler

Child intents resolve when Debit-Notice arrives:

```lua
function notices.debitNoticeHandler(msg)
    local intentId = msg.Tags['X-Intent-Id']
    if not intentId then return end
    
    local intent = intents.getIntentById(intentId)
    if not intent then return end
    
    -- Validate this is expected Debit-Notice
    if intent.type == constants.INTENT_TYPES.CHILD 
       and intent.expectedFrom == msg.From then
        
        -- Resolve child (will auto-complete parent if all children done)
        intents.resolveIntent(intentId, msg.Timestamp, msg)
        
        -- Get parent status for acknowledgment
        local parent = intents.getIntentById(intent.parentIntentId)
        local parentStatus = parent and parent.status or 'not-found'
        
        -- Send acknowledgment
        _utils.Send(msg, {
            Target = intent.initiator,
            Action = 'Debit-Notice-Processed',
            ['Intent-Id'] = intentId,
            ['Parent-Intent-Id'] = intent.parentIntentId,
            ['Parent-Intent-Status'] = parentStatus,
            ['Child-Intent-Status'] = 'resolved',
        })
    end
end
```

### State-Notice Handler

For ANT ownership verification (post-transfer confirmation):

```lua
function intents.stateNoticeHandler(msg)
    local intentId = msg.Tags['X-Intent-Id']
    assert(intentId, 'X-Intent-Id required')
    
    local intent = intents.getIntentById(intentId)
    assert(intent, 'Intent not found')
    assert(msg.From == intent.expectedFrom, 'Sender does not match expected')
    
    -- Whitelist check for ANT State-Notice
    if not _utils.isWhitelisted(msg) then
        intents.failIntent(intentId, 'ANT module not whitelisted', msg)
        return
    end
    
    local antState = _utils.safeDecodeJson(msg.Data)
    assert(antState, 'Invalid State-Notice data')
    assert(antState.Owner == ao.id, 'Marketplace does not own this ANT')
    
    -- Ownership confirmed, resolve intent
    intents.resolveIntent(intentId, msg.Timestamp, msg)
    
    _utils.Send(msg, {
        Target = intent.initiator,
        Action = 'State-Notice-Processed',
        ['Intent-Id'] = intentId,
        ['ANT-Id'] = msg.From,
        ['Owner'] = antState.Owner,
        ['Intent-Status'] = 'resolved',
    })
end
```

**Use case**: Users can manually trigger ANT ownership check via `Push-ANT-Intent-Resolution` to resolve stuck intents.

### Transfer-Error Handler

Failures cascade from child to parent:

```lua
function notices.transferErrorHandler(msg)
    local intentId = msg.Tags['X-Intent-Id']
    if not intentId then return end
    
    local intent = intents.getIntentById(intentId)
    if not intent or intent.type ~= constants.INTENT_TYPES.CHILD then
        return
    end
    
    -- Extract failure reason
    local reason = msg.Tags.Message or msg.Tags.Error or msg.Data or 'Transfer failed'
    
    -- Fail child intent
    intents.failIntent(intentId, reason, msg)
    
    -- Cascade failure to parent
    if intent.parentIntentId then
        local parent = intents.getIntentById(intent.parentIntentId)
        if parent then
            intents.failIntent(intent.parentIntentId, 'Child transfer failed: ' .. reason, msg)
        end
    end
end
```

**Failure scenarios**:
- ANT process rejects transfer (insufficient balance, etc.)
- Recipient address invalid
- Token process error/bug
- Network timeout (though AO guarantees eventual delivery)

### Intent Failure

When an intent fails, it's marked as failed and pruned:

```lua
function intents.failIntent(intentId, reason, msg)
    local intent = Intents[intentId]
    if not intent then return false end
    
    intent.status = constants.INTENT_STATUSES.FAILED
    intent.failureReason = reason
    
    -- Use resolveIntent to handle pruning
    local success, resolvedIntent = intents.resolveIntent(intentId, os.time(), msg)
    
    -- Send failure notice after pruning
    if success and resolvedIntent and msg then
        _utils.Send(msg, {
            Target = resolvedIntent.initiator,
            Action = 'Intent-Resolved',
            ['Intent-Id'] = tostring(resolvedIntent.intentId),
            Status = resolvedIntent.status,
            ['Intent-Action'] = resolvedIntent.action,
            ['Failure-Reason'] = resolvedIntent.failureReason or '',
        })
    end
    
    return true
end
```

**Important**: Failed intents are pruned immediately, freeing memory. The pruning logic captures intent data before deletion and sends the failure notice.

## Cranking Requirements

**TTL-based pruning required** - Intents expire after 24 hours if not completed.

### Passive Cranking Mechanism

The intent pruning is triggered on **every incoming message** via `utils.onBeforeHandler()`:

```lua
function utils.onBeforeHandler(msg)
    -- ... address formatting ...
    
    -- Prune expired orders from orderbook
    local ucm = require('ucm')
    ucm.pruneOrderbook(msg.Timestamp, msg)
    
    -- Prune expired intents (TTL-based cleanup)
    local intents = require('intents')
    intents.pruneIntents(msg.Timestamp)
end
```

This handler runs **before** every message handler, ensuring expired intents are cleaned up opportunistically.

### Pruning Implementation

```lua
function intents.pruneIntents(now)
    -- Return early if not time yet
    if not Pruning or not Pruning.nextScheduledIntentsPruning 
       or now < Pruning.nextScheduledIntentsPruning then
        return
    end
    
    local nextTTL = nil
    
    -- Iterate through all intents
    for intentId, intent in pairs(Intents) do
        -- Only process parent intents (children are pruned with parents)
        if intent.type == constants.INTENT_TYPES.PARENT and intent.ttl then
            if now >= intent.ttl then
                -- Intent expired, fail it
                intents.failIntent(intentId, 'Intent expired (24h TTL)', nil)
            else
                -- Track next expiration
                if not nextTTL or intent.ttl < nextTTL then
                    nextTTL = intent.ttl
                end
            end
        end
    end
    
    -- Schedule next prune
    Pruning.nextScheduledIntentsPruning = nextTTL
end
```

### Scheduling Optimization

The pruning schedule is updated whenever an intent is created:

```lua
function intents.scheduleNextIntentsPruning(timestamp)
    if not timestamp then return end
    
    if not Pruning then
        Pruning = { nextScheduledIntentsPruning = nil }
    end
    
    -- Schedule if no prune scheduled or if this one is sooner
    if not Pruning.nextScheduledIntentsPruning 
       or timestamp < Pruning.nextScheduledIntentsPruning then
        Pruning.nextScheduledIntentsPruning = timestamp
    end
end
```

Called in `createParentIntent()`:

```lua
local ttl = msg.Timestamp + constants.INTENT_TTL_MS
local intent = {
    -- ... fields ...
    ttl = ttl,
}
Intents[intent.intentId] = intent

-- Schedule pruning for this intent's TTL
intents.scheduleNextIntentsPruning(ttl)
```

### Cranking Characteristics

- **Trigger**: Every incoming message (via `onBeforeHandler`)
- **Frequency**: Variable (depends on marketplace activity)
- **Performance**: O(n) where n = number of parent intents
- **Cost**: Amortized across all messages (minimal per-message overhead)
- **Early Return**: If not time to prune yet, returns immediately (O(1))

**Passive cranking benefits**:
- No dedicated cron or scheduler needed
- Cleanup happens naturally with marketplace activity
- Low overhead when nothing to prune
- Scales with usage (more activity = more frequent cleanup)

**Trade-offs**:
- Cleanup timing depends on marketplace activity (low activity = slower cleanup)
- Worst-case: all intents processed on single message (if many expire at once)
- Dead marketplace would never clean up expired intents (acceptable - no new intents created either)

## Consequences

### Positive

1. **Reliability**: Multi-step workflows tracked from start to finish
2. **Error Recovery**: Clear failure paths with user notifications
3. **State Consistency**: Partial completions tracked, no orphaned state
4. **User Visibility**: Users can query intent status at any time
5. **Automatic Cleanup**: TTL-based expiration prevents memory leaks
6. **Spam Prevention**: Listing fees prevent free intent creation
7. **Cascading Failures**: Child failures properly propagate to parents
8. **Flexibility**: Supports any multi-step workflow (orders, cancellations, settlements)
9. **Auditability**: Complete trail of intent lifecycle

### Negative

1. **Complexity**: More complex than optimistic or polling approaches
2. **Memory Overhead**: Intents stored in state for up to 24 hours
3. **UX Friction**: Two-step process (create intent → send ANT)
4. **Learning Curve**: Users must understand intent model
5. **Fee Burden**: Listing fees can be expensive for long-duration listings
6. **State Bloat**: High intent creation rate accumulates state
7. **Pruning Dependency**: Requires regular marketplace activity for cleanup
8. **Error Verbosity**: Multiple notice types to handle (Debit, State, Transfer-Error)

### Neutral

1. **TTL Duration**: 24 hours chosen arbitrarily (could be tuned)
2. **Fee Structure**: 1 ARIO per day is a policy decision (not technical)
3. **Parent/Child Model**: Other models possible (flat, graph, etc.)
4. **Intent IDs**: Simple counter (could use UUIDs or content hashes)
5. **Pruning Timing**: Opportunistic cleanup (not guaranteed real-time)

## Alternatives Considered

### 1. Polling Pattern

Marketplace periodically queries ANT processes for ownership status.

**Rejected because**:
- Expensive: O(n) messages per poll cycle
- Slow: Polling interval adds latency
- Unbounded cost: Polling continues until success
- Doesn't handle failures well
- Scales poorly with many concurrent operations

### 2. Optimistic Completion

Assume transfers succeed and update state immediately.

**Rejected because**:
- Unsafe: Creates invalid state if transfer fails
- Hard to rollback: Reverting completed actions is complex
- Poor error handling: Failures detected too late
- Trust issues: Relies on external process honesty
- Audit nightmare: State doesn't match reality

### 3. Webhook Callbacks

External processes call back to marketplace on completion.

**Rejected because**:
- Not guaranteed: Callbacks can fail or be dropped
- Security: How to verify callback authenticity?
- Doesn't fit AO model: Messages are one-way, not request/response
- Complexity: Requires callback infrastructure

### 4. Synchronous Transfers

Block until transfer completes (like a database transaction).

**Rejected because**:
- Not possible in AO: Processes are asynchronous by design
- Would require locking: Bad for concurrent operations
- Poor performance: Every action waits for external process
- Doesn't match AO's message-passing model

### 5. Event Sourcing

Store all events and rebuild state from event log.

**Rejected because**:
- Overkill: Intent pattern simpler for this use case
- Performance: Replaying events is expensive
- Complexity: Requires event store and replay logic
- State size: Event log grows unbounded
- Doesn't solve intent tracking problem (still need to track completion)

### 6. State Machine Actors

Each workflow is a separate actor/process.

**Rejected because**:
- Resource intensive: One process per workflow
- Complexity: Managing many processes
- Doesn't fit AO: Single process per marketplace
- Coordination overhead: Communication between actors
- No clear benefit over intent pattern

### 7. Sagas Pattern

Use compensating transactions to rollback on failure.

**Considered but modified**:
- Saga pattern inspired the cascading failure approach
- Full saga pattern requires compensation logic for each step
- Intent pattern is simpler: just mark as failed
- For marketplace use case, refunds are the compensation (already implemented)

## Implementation Notes

### Intent ID Generation

Intent IDs are generated using a simple counter:

```lua
IntentCounter = IntentCounter or "0"

function intents.incrementIntentCounter()
    IntentCounter = tostring(bint(IntentCounter) + bint(1))
    return tostring(IntentCounter)
end
```

**Why string counter?**:
- Compatible with bint (256-bit integers)
- Predictable and sequential
- Easy to debug (intent "1", "2", "3", etc.)
- Guaranteed unique within process

**Alternative considered**: UUIDs (more entropy, but harder to debug and less human-readable).

### Intent Pruning on Completion

When intents reach terminal states (completed/failed), they are pruned immediately:

```lua
function intents.resolveIntent(intentId, timestamp, msg)
    local intent = Intents[intentId]
    if not intent then return false end
    
    if intent.type == constants.INTENT_TYPES.PARENT then
        -- Parent intent state transitions
        if intent.status == constants.INTENT_STATUSES.PENDING then
            intent.status = constants.INTENT_STATUSES.ACTIVE
            intent.resolvedAt = timestamp
        end
        
        -- Prune when terminal state reached
        if intent.status == constants.INTENT_STATUSES.COMPLETED 
           or intent.status == constants.INTENT_STATUSES.FAILED then
            
            -- Capture data BEFORE pruning
            local resolvedIntent = {
                intentId = intent.intentId,
                initiator = intent.initiator,
                action = intent.action,
                status = intent.status,
                resolvedAt = timestamp,
                failureReason = intent.failureReason,
            }
            
            -- Delete all child intents
            for childId in pairs(intent.childIntentIds) do
                Intents[childId] = nil
            end
            
            -- Delete parent
            Intents[intentId] = nil
            
            return true, resolvedIntent
        end
    end
    -- ... child intent logic ...
end
```

**Why prune immediately?**:
- Frees memory as soon as intent completes
- Prevents unbounded state growth
- Terminal intents serve no further purpose
- Users can still get result via Intent-Resolved notice

### Intent Queries

Users can query intents before they're pruned:

```lua
-- Get single intent by ID
function intents.getIntentByIdHandler(msg)
    local intentId = msg.Tags['Intent-Id']
    assert(intentId, 'Intent-Id required')
    
    local intent = intents.getIntentById(intentId)
    assert(intent, 'Intent not found')
    
    -- If parent, include all children
    local response = _utils.deepCopy(intent)
    if intent.type == constants.INTENT_TYPES.PARENT then
        response.children = {}
        for childId in pairs(intent.childIntentIds) do
            response.children[childId] = intents.getIntentById(childId)
        end
    end
    
    return json.encode(response)
end

-- Get paginated intents
function intents.getPaginatedIntentsHandler(msg)
    local _utils = require('utils')
    local page = _utils.parsePaginationTags(msg)
    
    local intentsArray = intents.getAllIntents()
    
    local paginatedIntents = _utils.paginateTableWithCursor(
        intentsArray,
        page.cursor,
        'createdAt',
        page.limit,
        page.sortBy,
        page.sortOrder,
        page.filters -- { initiator = "address", status = "pending", type = "parent" }
    )
    
    return json.encode(paginatedIntents)
end
```

**Use cases**:
- Check if intent is still pending
- Debug stuck workflows
- Monitor marketplace activity
- Audit user operations

### Manual Intent Resolution

Users can manually push ANT ownership verification:

```lua
function intents.pushANTIntentResolutionHandler(msg)
    local intentId = msg.Tags['X-Intent-Id']
    assert(intentId, 'X-Intent-Id required')
    
    local intent = intents.getIntentById(intentId)
    assert(intent, 'Intent not found')
    
    -- For child intents, check against parent's initiator
    local expectedInitiator = intent.initiator
    if intent.type == constants.INTENT_TYPES.CHILD and intent.parentIntentId then
        local parent = Intents[intent.parentIntentId]
        if parent then
            expectedInitiator = parent.initiator
        end
    end
    
    assert(msg.From == expectedInitiator, 'Sender does not match intent initiator')
    
    local antId = intent.expectedFrom
    
    -- Send State query to ANT
    _utils.Send(msg, {
        Target = antId,
        Action = "State",
        Tags = {
            ['X-Intent-Id'] = intentId,
        }
    })
end
```

**Why manual resolution?**:
- Handles edge case where Debit-Notice was lost/delayed
- Gives users control to "unstick" workflows
- Useful for debugging and testing
- Fallback mechanism if automatic resolution fails

## References

- ARNS Marketplace Specification: `docs/spec.md`
- ADR-001: Module Whitelist for ANT Trading: `docs/ADR-001-module-whitelist.md`
- ADR-002: Credit Notice Pattern: `docs/ADR-002-credit-notice-pattern.md`
- ADR-003: ARIO Internal Ledger Pattern: `docs/ADR-003-ario-internal-ledger.md`
- Source: `src/intents.lua` - Intent management and handlers
- Source: `src/notices.lua` - Debit-Notice and Transfer-Error handlers
- Source: `src/ucm.lua` - Child intent creation via `transferWithIntent()`
- Source: `src/utils.lua` - Pruning trigger via `onBeforeHandler()`
- Source: `src/globals.lua` - Intents global and pruning schedule

## Future Considerations

1. **Intent Delegation**: Allow users to delegate intent management to other addresses
2. **Multi-Signature Intents**: Require multiple approvals for high-value operations
3. **Intent Templates**: Pre-defined intent workflows for common patterns
4. **Intent Pausing**: Ability to pause/resume long-running intents
5. **Partial Completion**: Allow intents to partially complete and continue later
6. **Intent Chaining**: One intent triggers another (workflow orchestration)
7. **Custom TTLs**: Allow users to specify custom TTL per intent (within limits)
8. **Intent Refunds**: Return listing fees on early completion or cancellation
9. **Priority Intents**: Pay more fees for faster processing or higher priority
10. **Intent Snapshots**: Periodic snapshots for recovery and auditing
11. **Intent Metrics**: Track success/failure rates, average completion time, etc.
12. **Batch Intent Creation**: Create multiple intents in a single message
13. **Intent Notifications**: Real-time push notifications on state changes
14. **Intent Rollback**: Automatic rollback on failure (like database transactions)
15. **Cross-Marketplace Intents**: Intents that span multiple marketplace processes

