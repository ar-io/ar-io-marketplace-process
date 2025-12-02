# ADR-007: Before/After Handler Hooks Pattern

## Status

Accepted

## Context

The marketplace process handles incoming messages through registered message handlers. Each handler processes a specific action (e.g., `Create-Order`, `Cancel-Order`, `Credit-Notice`). Some handlers need to perform common operations before and after their main logic:

**Before Handler Operations**:
- Authentication and authorization checks
- Input validation
- Rate limiting
- Logging and metrics
- State snapshots for rollback

**After Handler Operations**:
- Success notifications
- State cleanup
- Audit logging
- Metrics recording
- Event emission

Without a structured approach, these cross-cutting concerns are either:
1. **Duplicated** across handlers (bad for maintenance)
2. **Inconsistently applied** (some handlers have logging, others don't)
3. **Mixed with business logic** (reduces readability)

Additionally, the marketplace needs to extend handler behavior without modifying core handler code, such as:
- Adding custom validation for specific order types
- Implementing custom notification strategies
- Plugin-style extensions for future features

The AO environment also presents specific challenges:
- Handlers may be updated or replaced during process lifetime
- Module loading order affects what code is available
- Circular dependencies between handler utilities and main logic

## Decision

We will implement an **onBeforeHandler and onAfterHandler pattern** that allows registering hook functions to run before and after message handlers. These hooks will be lazily loaded to work with the lazy module loading pattern (see [ADR-006](./ADR-006-lazy-module-loading.md)).

### Pattern

```lua
-- In utils.lua

---@class HandlerHooks
---@field onBefore? fun(msg: table): boolean, string? -- Return false, error to abort
---@field onAfter? fun(msg: table, result: any): void

---@type table<string, HandlerHooks>
local handlerHooks = {}

---Register hooks for a specific handler
---@param handlerName string
---@param hooks HandlerHooks
function utils.registerHandlerHooks(handlerName, hooks)
    handlerHooks[handlerName] = hooks
end

---Get hooks for a handler (lazy loaded)
---@param handlerName string
---@return HandlerHooks|nil
function utils.getHandlerHooks(handlerName)
    return handlerHooks[handlerName]
end
```

### Handler Implementation

```lua
-- In ucm.lua

function ucm.createOrderHandler(msg)
    local _utils = require('utils')  -- Lazy load
    
    -- Execute onBefore hook
    local hooks = _utils.getHandlerHooks('Create-Order')
    if hooks and hooks.onBefore then
        local ok, err = hooks.onBefore(msg)
        if not ok then
            error(err or 'onBefore hook rejected message')
        end
    end
    
    -- Main handler logic
    local result = ucm.createOrder({
        orderId = msg.Id,
        sender = msg.Sender,
        -- ...
    })
    
    -- Execute onAfter hook
    if hooks and hooks.onAfter then
        hooks.onAfter(msg, result)
    end
    
    return result
end
```

### Registering Hooks

```lua
-- In process.lua or separate hooks module

local function registerMarketplaceHooks()
    local _utils = require('utils')
    
    -- Create-Order hooks
    _utils.registerHandlerHooks('Create-Order', {
        onBefore = function(msg)
            -- Validate seller has sufficient balance
            local _balances = require('balances')  -- Lazy load in hook
            
            if not msg.Tags['X-Swap-Token'] then
                return false, 'X-Swap-Token required'
            end
            
            -- Check rate limiting, auth, etc.
            return true  -- OK to proceed
        end,
        
        onAfter = function(msg, result)
            -- Log order creation
            local _utils = require('utils')  -- Lazy load in hook
            _utils.logEvent('Order-Created', {
                orderId = result,
                seller = msg.Sender,
                timestamp = msg.Timestamp
            })
        end
    })
    
    -- Cancel-Order hooks
    _utils.registerHandlerHooks('Cancel-Order', {
        onBefore = function(msg)
            -- Check authorization
            return true
        end,
        onAfter = function(msg, result)
            -- Notify order cancelled
        end
    })
end

-- Call during process initialization
registerMarketplaceHooks()
```

### Lazy Loading in Hooks

Hooks can themselves use lazy loading to avoid circular dependencies:

```lua
_utils.registerHandlerHooks('Credit-Notice', {
    onBefore = function(msg)
        -- Lazy load inside hook function
        local _balances = require('balances')
        local _intents = require('intents')
        
        -- Use loaded modules
        if msg.Tags['X-Intent-Id'] then
            local intent = _intents.getIntent(msg.Tags['X-Intent-Id'])
            if not intent then
                return false, 'Intent not found'
            end
        end
        
        return true
    end,
    
    onAfter = function(msg, result)
        -- Lazy load different modules as needed
        local _utils = require('utils')
        _utils.emitNotice('Credit-Processed', msg.Sender)
    end
})
```

### Optional Hooks

Handlers work correctly even if no hooks are registered:

```lua
local hooks = _utils.getHandlerHooks('Some-Handler')
-- hooks may be nil - safe to check

if hooks and hooks.onBefore then
    -- Only run if hook exists
end
```

## Consequences

### Positive

1. **Separation of Concerns**: Cross-cutting logic separated from business logic
2. **Consistency**: Common operations applied uniformly across handlers
3. **Extensibility**: New behaviors added without modifying handler code
4. **Testability**: Hooks can be tested independently
5. **Lazy Loading Compatible**: Works seamlessly with lazy module loading pattern
6. **Circular Dependency Safe**: Hooks load modules on-demand, avoiding cycles
7. **Optional**: Handlers work without hooks, no mandatory overhead
8. **Clear Flow**: Explicit before/after semantics easy to understand
9. **AO Update Resilience**: Lazy loading in hooks adapts to AO changes
10. **Plugin Architecture**: Foundation for plugin system

### Negative

1. **Indirection**: Handler behavior not entirely visible in handler code
2. **Execution Order**: Multiple hooks create ordering dependencies
3. **Error Handling**: Hook errors must be carefully managed
4. **Debugging**: Stack traces include hook layer
5. **Performance**: Small overhead from hook checks and calls
6. **Documentation**: Hook behavior must be documented separately
7. **Testing Complexity**: Must test handler + hook combinations

### Neutral

1. **Registry Pattern**: Requires central hook registry
2. **Convention-Based**: Relies on naming conventions for handler identification
3. **Runtime Registration**: Hooks registered at process initialization
4. **No Static Analysis**: Hook usage not visible to static analyzers
5. **Lua-Specific**: Pattern tailored to Lua's dynamic nature

## Alternatives Considered

### 1. Middleware Chain Pattern

Implement handlers as middleware chain with each layer wrapping the next:

```lua
local function loggingMiddleware(handler)
    return function(msg)
        print('Before handler')
        local result = handler(msg)
        print('After handler')
        return result
    end
end

local finalHandler = loggingMiddleware(authMiddleware(createOrderHandler))
```

**Rejected because**:
- Complex to manage multiple middleware layers
- Difficult to selectively apply middleware
- Doesn't work well with lazy loading
- Over-engineered for our needs
- Harder to understand control flow

### 2. Decorator Pattern

Use decorators to wrap handlers:

```lua
function withLogging(handler)
    return function(msg)
        log('start')
        local result = handler(msg)
        log('end')
        return result
    end
end

handlers['Create-Order'] = withLogging(ucm.createOrderHandler)
```

**Rejected because**:
- Still requires wrapping each handler
- Tight coupling between handler and decorators
- Doesn't solve lazy loading integration
- Less flexible than hook registry
- Harder to add/remove behaviors dynamically

### 3. Event System

Emit events before/after handlers and let listeners respond:

```lua
function ucm.createOrderHandler(msg)
    events.emit('before:Create-Order', msg)
    local result = ucm.createOrder(...)
    events.emit('after:Create-Order', msg, result)
    return result
end
```

**Rejected because**:
- Requires full event system implementation
- Async event handling complexity
- Harder to enforce synchronous validation
- More overhead than needed
- Overkill for simple hooks

### 4. Inheritance/OOP Pattern

Use object-oriented inheritance with overridable methods:

```lua
BaseHandler = {}
function BaseHandler:onBefore(msg) end
function BaseHandler:handle(msg) end
function BaseHandler:onAfter(msg) end

CreateOrderHandler = inherits(BaseHandler)
function CreateOrderHandler:handle(msg)
    -- Implementation
end
```

**Rejected because**:
- Lua doesn't have native class system
- Requires implementing OOP infrastructure
- Not idiomatic in Lua/AO
- Doesn't fit existing codebase style
- More complex than needed

### 5. Hard-coded Helper Functions

Call common helper functions at start/end of each handler:

```lua
function ucm.createOrderHandler(msg)
    validateMessage(msg)  -- Hard-coded
    logMessageReceived(msg)  -- Hard-coded
    
    local result = ucm.createOrder(...)
    
    logMessageProcessed(msg)  -- Hard-coded
    return result
end
```

**Rejected because**:
- Duplicated across all handlers
- Inconsistent application
- Hard to modify behavior
- No extensibility
- Maintenance burden

## Implementation Notes

### Hook Registration Timing

Hooks should be registered during process initialization, before any handlers run:

```lua
-- In process.lua

-- 1. Load modules
local utils = require('utils')
local ucm = require('ucm')

-- 2. Register hooks
utils.registerHandlerHooks('Create-Order', {...})
utils.registerHandlerHooks('Cancel-Order', {...})

-- 3. Register handlers
Handlers.add('Create-Order', ucm.createOrderHandler)
Handlers.add('Cancel-Order', ucm.cancelOrderHandler)
```

### Error Handling in Hooks

Hooks should handle errors gracefully:

```lua
onBefore = function(msg)
    local ok, err = pcall(function()
        -- Hook logic that might fail
        validateSomething(msg)
    end)
    
    if not ok then
        -- Return false with error message
        return false, 'Validation failed: ' .. tostring(err)
    end
    
    return true  -- Success
end
```

Handler should check hook result:

```lua
if hooks and hooks.onBefore then
    local ok, err = hooks.onBefore(msg)
    if not ok then
        error(err or 'Hook rejected message')
    end
end
```

### Lazy Loading Pattern in Hooks

Always use lazy loading inside hook functions:

```lua
-- GOOD: Lazy load in function
onBefore = function(msg)
    local _balances = require('balances')  -- Load when hook runs
    return _balances.checkSufficient(msg.Sender, 100)
end

-- BAD: Top-level require
local balances = require('balances')  -- Loads immediately (circular dep risk)
onBefore = function(msg)
    return balances.checkSufficient(msg.Sender, 100)
end
```

### Multiple Hooks per Handler

Current implementation supports single hook set per handler. For multiple hooks:

```lua
-- Future enhancement
utils.addHandlerHook('Create-Order', 'auth', { onBefore = authCheck })
utils.addHandlerHook('Create-Order', 'logging', { onAfter = logEvent })

-- Execute all hooks in registration order
local hooks = utils.getAllHandlerHooks('Create-Order')
for _, hook in ipairs(hooks) do
    if hook.onBefore then
        hook.onBefore(msg)
    end
end
```

### Hook Naming Convention

Use descriptive names when registering multiple hooks:

```lua
utils.registerHandlerHooks('Create-Order:auth', {...})
utils.registerHandlerHooks('Create-Order:validation', {...})
utils.registerHandlerHooks('Create-Order:logging', {...})
```

### Testing Hooks

Test hooks independently from handlers:

```lua
-- test_hooks.lua
local hooks = require('marketplace_hooks')

-- Test onBefore validation
local result, err = hooks['Create-Order'].onBefore({
    Sender = 'test-addr',
    Tags = { ['X-Swap-Token'] = 'token-id' }
})

assert(result == true, 'Should accept valid message')

-- Test with invalid message
result, err = hooks['Create-Order'].onBefore({
    Sender = 'test-addr',
    Tags = {}  -- Missing X-Swap-Token
})

assert(result == false, 'Should reject invalid message')
assert(err:match('X-Swap-Token'), 'Should explain error')
```

## References

- [ADR-006: Lazy Module Loading Pattern](./ADR-006-lazy-module-loading.md)
- [Hook Pattern (Design Patterns)](https://en.wikipedia.org/wiki/Hooking)
- AO Handler Documentation
- Source: `src/utils.lua` - Hook registry implementation
- Source: `src/process.lua` - Hook registration

## Future Considerations

1. **Multiple Hook Sets**: Support multiple before/after hooks per handler
2. **Hook Priority**: Order hooks by priority when multiple registered
3. **Hook Conditions**: Conditional hooks that only run for certain messages
4. **Hook Context**: Pass shared context object through hook chain
5. **Hook Metrics**: Track hook execution time and success rates
6. **Hook Debugging**: Debug mode that logs all hook executions
7. **Hook Versioning**: Support versioned hooks for gradual rollout
8. **Hook Validation**: Schema validation for hook function signatures
9. **Hook Documentation**: Auto-generate documentation from registered hooks
10. **Hook Removal**: API to unregister hooks dynamically

