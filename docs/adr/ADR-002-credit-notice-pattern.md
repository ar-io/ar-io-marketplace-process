# ADR-002: Credit Notice Pattern for Token Transfers

## Status

Accepted

## Context

The ARNS Marketplace needs to accept external token transfers from other AO processes, specifically:

1. **ANT tokens** - Arweave Name Tokens that users want to list for sale on the marketplace
2. **ARIO tokens** - The payment token used for deposits into the marketplace's internal ledger

> See [ARIO Internal Ledger ADR](docs/adr/ADR-003-ario-internal-ledger.md) regarding decision on using a ledger for the ARIO token.

These transfers originate from external token processes and arrive asynchronously as messages. The marketplace must:

- Validate incoming transfers to prevent invalid or malicious transactions
- Support different workflows for ANT (intent-based) vs ARIO (deposit-based) transfers
- Provide clear error handling and refund mechanisms
- Integrate with the module whitelist system for ANT security
- Maintain compatibility with the AO token specification

Without a robust transfer reception pattern, the marketplace would be vulnerable to:
- Invalid token transfers corrupting state
- Loss of user funds due to processing errors
- Security exploits from malicious token processes
- Poor user experience from unclear error messages

## Decision

We will implement a **Credit-Notice handler pattern** that serves as the primary entry point for all external token transfers. This handler will:

1. **Use the AO Credit-Notice standard** as defined in the token specification
2. **Apply validation layers** to ensure transfers meet marketplace requirements
3. **Route transfers differently** based on token type (ARIO vs ANT) and action
4. **Enforce intent requirements** for ANT order creation
5. **Block ARIO Credit-Notices for order creation** (forcing internal balance usage)
6. **Refund invalid transfers** appropriately based on token type

### Handler Entry Point

```lua
-- In notices.lua
function notices.creditNoticeHandler(msg)
```

This handler is registered in `process.lua` as a critical handler (errors cause immediate failure):

```lua
-- the last param 'true' signals that this is a critical memory error handler.
utils.createHandler('Action', 'Credit-Notice', notices.creditNoticeHandler, nil, true)
```

### Validation Chain

The Credit-Notice handler applies validations in this order:

1. **Deposit Detection** - Check for `X-Action: Deposit` tag (ARIO deposits only)
2. **Sender Validation** - Verify `Sender` tag exists and is valid address
3. **Quantity Validation** - Verify `Quantity` tag exists and is positive integer
4. **ARIO Order Blocking** - Block ARIO Credit-Notices with `X-Order-Action: Create-Order`
5. **Intent ID Requirement** - Require `X-Intent-Id` for ANT orders
6. **Intent Validation** - Verify intent exists, matches sender, and hasn't expired
7. **Module Whitelist** - Check ANT module is whitelisted (via `From-Module` tag)

### Token Type Routing

#### ARIO Deposits

```lua
if msg.Tags['X-Action'] == constants.ACTIONS.DEPOSIT then
    local isArioNotice = _utils.isArioToken(msg.From)
    assert(isArioNotice, "Deposit must be from ARIO")
    balances.handleDeposit(msg)
    return
end
```

ARIO deposits are processed immediately and added to the user's internal balance.

#### ARIO Order Blocking

```lua
if msg.Tags['X-Order-Action'] == 'Create-Order' and _utils.isArioToken(msg.From) then
    handleInvalidTransfer('ARIO orders must use internal balance - deposit ARIO first, then call Create-Order')
    return
end
```

This forces users to use the internal ledger for ARIO trading, avoiding external transfer overhead.

#### ANT Order Creation

```lua
if msg.Tags['X-Order-Action'] == 'Create-Order' then
    -- Intent validation (already performed above)
    -- Whitelist validation
    if not _utils.isArioToken(msg.From) and not _utils.isWhitelisted(msg) then
        intents.failIntent(msg.Tags['X-Intent-Id'], 'ANT module not whitelisted', msg)
        return
    end
    
    -- Proceed with order creation
    ucm.createOrder(orderArgs)
end
```

ANT orders require a valid intent and whitelisted module before processing.

### Refund Strategy

Invalid transfers are handled differently based on token type:

```lua
local function handleInvalidTransfer(errorMessage)
    if _utils.isArioToken(msg.From) then
        -- Accept ARIO tokens as fees (no refund)
        if quantity and _utils.checkValidAmount(quantity) then
            _utils.accrueFee(quantity)
        end
    else
        -- Refund non-ARIO tokens (like ANT)
        _utils.refundAndError(msg, sender, errorMessage)
    end
end
```

**Rationale**: 
- ARIO transfers that fail validation are accepted as marketplace fees (user error tax)
- ANT transfers are refunded because they represent unique assets that shouldn't be forfeited

### Intent Integration

ANT orders require pre-created intents:

```lua
-- REQUIRE X-Intent-Id for ANT orders
if not msg.Tags['X-Intent-Id'] then
    handleInvalidTransfer('X-Intent-Id required - create intent first')
    return
end

-- Validate intent exists and matches sender
local intent = intents.getIntentById(msg.Tags['X-Intent-Id'])
if not intent then
    handleInvalidTransfer('Intent already resolved or does not exist')
    return
end

if sender ~= intent.initiator then
    handleInvalidTransfer('Sender does not match intent initiator')
    return
end
```

This two-phase workflow (create intent → send ANT with intent ID) enables:
- Listing fee collection before ANT transfer
- Intent-based tracking of multi-step workflows
- Atomic failure handling (intent fails if ANT transfer fails)

See [ADR-004: Intent-Based Workflow Pattern](./ADR-004-intent-based-workflow.md) for details.

## Cranking Requirements

**None required** - The Credit-Notice pattern is purely event-driven.

- **Trigger**: Incoming `Credit-Notice` messages from token processes
- **Frequency**: On-demand (whenever a transfer occurs)
- **Performance**: O(1) validation checks, no iteration over state
- **Cost**: Pay-per-use (only when transfers happen)

The handler responds immediately to each message and requires no background processing or scheduled cleanup.

## Consequences

### Positive

1. **Security**: Multiple validation layers prevent invalid or malicious transfers
2. **Clarity**: Clear separation between ARIO deposits and ANT orders
3. **Compliance**: Follows AO token specification for Credit-Notice handling
4. **Error Recovery**: Refund mechanism prevents loss of ANT assets
5. **Integration**: Seamless integration with intent system and module whitelist
6. **Gas Efficiency**: ARIO deposit blocking forces efficient internal ledger usage
7. **Auditability**: All transfers logged via Credit-Notice messages

### Negative

1. **User Friction**: Two-step process for ANT listings (create intent → send ANT)
2. **Complexity**: Multiple validation paths increase handler complexity
3. **Error Messages**: Users must understand different rules for ARIO vs ANT
4. **No ARIO Refunds**: Invalid ARIO transfers forfeit tokens as fees (could be seen as punitive)
5. **Intent Dependency**: ANT orders depend on intent system availability
6. **Whitelist Dependency**: ANT orders require whitelisted modules (see ADR-001)

### Neutral

1. **Event-Driven Only**: No batch processing or deferred handling
2. **Token Type Assumptions**: Assumes two-token model (ARIO + ANTs)
3. **Validation Ordering**: Specific validation order affects error messages
4. **Refund Timing**: Refunds happen immediately within same message handler

## Alternatives Considered

### 1. Direct Transfer Pattern

Allow users to send tokens directly without validation, trusting sender honesty.

**Rejected because**:
- No protection against malicious or buggy token processes
- No way to enforce intent-based workflows
- Higher risk of state corruption and fund loss due to cranking issues on AO

### 2. Allowance Pattern

Use an ERC-20 style allowance system where users approve the marketplace to pull tokens.

**Rejected because**:
- Requires additional user transactions (approve + transfer)
- Not standard in AO ecosystem
- More complex state management
- Doesn't solve asynchronous transfer tracking problem
- Not supported by the AO token spec


### 3. Escrow Contract Pattern

Use a separate escrow contract to hold tokens before marketplace listing.

**Rejected because**:
- Additional contract complexity and deployment
- Worse user experience (three-party interaction)
- Doesn't reduce validation requirements
- Adds another trust boundary

### 4. Optimistic Reception

Accept all transfers optimistically and validate later during order matching.

**Rejected because**:
- Allows invalid state to accumulate
- Complicates error handling and refunds
- Poor user experience (late failures)
- Risk of marketplace state corruption

## Implementation Notes

### Handler Registration

The Credit-Notice handler is registered as a **critical handler** (5th parameter = `true`):

```lua
utils.createHandler('Action', ActionMap.creditNotice, notices.creditNoticeHandler, nil, true)
```

This means:
- Errors cause immediate handler failure (no silent errors)
- Handler execution is wrapped in `pcall` for error capture
- Failed handlers send error notices back to sender

### Message Tags

Expected tags on Credit-Notice messages:

**Standard Tags** (from token specification):
- `Action`: "Credit-Notice"
- `Sender`: Original sender address
- `Quantity`: Amount transferred (string integer)

**Marketplace Tags**:
- `X-Action`: "Deposit" (for ARIO deposits) or omitted (for orders)
- `X-Order-Action`: "Create-Order" (for ANT orders)
- `X-Intent-Id`: Intent ID (required for ANT orders)

**Whitelist Tags** (from AO system):
- `From-Module`: Module ID of the sending process (auto-populated by AO)

### Error Handling

The handler uses `handleInvalidTransfer()` helper to centralize error logic:

```lua
local function handleInvalidTransfer(errorMessage)
    if _utils.isArioToken(msg.From) then
        -- ARIO: Accept as fee
        if quantity and _utils.checkValidAmount(quantity) then
            _utils.accrueFee(quantity)
        end
    else
        -- ANT: Refund
        _utils.refundAndError(msg, sender, errorMessage)
    end
end
```

This helper is called for all validation failures after initial deposit routing.

### Order Creation Flow

After successful validation, the handler routes to order creation:

```lua
local orderArgs = {
    orderId = msg.Id,
    orderGroupId = msg.Tags['X-Group-ID'] or 'None',
    dominantToken = msg.From,
    swapToken = msg.Tags['X-Swap-Token'],
    sender = sender,
    quantity = quantity,
    createdAt = msg.Timestamp,
    blockheight = msg['Block-Height'],
    orderType = msg.Tags['X-Order-Type'] or 'fixed',
    expirationTime = msg.Tags['X-Expiration-Time'] and tonumber(msg.Tags['X-Expiration-Time']),
    msg = msg, -- Pass msg context for intent tracking
}

ucm.createOrder(orderArgs)
```

The order creation is wrapped in `pcall` to catch errors and refund if needed:

```lua
local ok, err = pcall(function()
    ucm.createOrder(orderArgs)
end)
if not ok then
    -- Only refund if error wasn't already handled
    if not string.find(tostring(err), 'required') and not string.find(tostring(err), 'must be') then
        _utils.refundAndError(msg, sender, 'Order creation failed: ' .. tostring(err), 'Order-Error')
    end
    return
end
```

### Intent Completion

After successful order creation, the handler checks if the parent intent can be completed:

```lua
local intent = intents.getIntentById(msg.Tags['X-Intent-Id'])
if intent and intent.type == 'parent' then
    -- Count pending child intents
    local hasPendingChildren = false
    for childId in pairs(intent.childIntentIds) do
        local child = intents.getIntentById(childId)
        if child and child.status == 'pending' then
            hasPendingChildren = true
            break
        end
    end
    
    -- If no pending children, complete immediately
    if not hasPendingChildren then
        intents.updateIntentStatus(msg.Tags['X-Intent-Id'], 'completed', msg)
    end
end
```

This enables single-step ANT listings (where the ANT transfer is the only step) to complete immediately.

## References

- [AO Token Specification](https://github.com/permaweb/ao/tree/main/blueprints)
- ADR-001: Module Whitelist for ANT Trading: `docs/ADR-001-module-whitelist.md`
- ADR-003: ARIO Internal Ledger Pattern: `docs/ADR-003-ario-internal-ledger.md`
- ADR-004: Intent-Based Workflow Pattern: `docs/ADR-004-intent-based-workflow.md`
- Source: `src/notices.lua` - Credit-Notice handler implementation
- Source: `src/balances.lua` - ARIO deposit handling
- Source: `src/intents.lua` - Intent validation and resolution

## Future Considerations

1. **Multi-Token Support**: Extend to support additional payment tokens beyond ARIO
2. **Deposit Limits**: Add minimum/maximum deposit amounts for spam prevention
3. **Rate Limiting**: Implement per-user transfer rate limits
4. **Validation Metrics**: Track validation failure rates by error type

