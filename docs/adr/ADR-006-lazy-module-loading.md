# ADR-006: Lazy Module Loading Pattern

## Status

Accepted

## Context

The marketplace process is structured as multiple Lua modules (`balances.lua`, `ucm.lua`, `intents.lua`, etc.) that depend on each other for functionality. In a typical Lua application, modules are loaded using `require()` at the top of files:

```lua
-- Traditional approach
local utils = require('utils')
local balances = require('balances')
local intents = require('intents')

function someFunction()
    utils.doSomething()
    balances.checkBalance()
end
```

However, the AO process environment presents unique challenges:

### Problem 1: Circular Dependencies

The marketplace modules have natural circular dependencies:
- `ucm.lua` needs `intents.lua` to create intents for orders
- `intents.lua` needs `ucm.lua` to cancel orders when intents fail
- `balances.lua` needs `utils.lua` for validation
- `utils.lua` needs `balances.lua` for fee accrual

Traditional top-level `require()` calls fail with circular dependency errors:

```
Error: loop or previous error loading module 'ucm'
```

### Problem 2: AO Module Updates

The AO ecosystem is rapidly evolving, with frequent updates to:
- Core AO runtime behavior
- Standard library functions
- Module loading mechanisms
- Process initialization patterns

Top-level `require()` statements execute during module load time, which means:
- Code is tightly coupled to specific AO runtime versions
- Updates to AO module loading can break existing processes
- Processes may fail to load after AO runtime updates
- Difficult to test different AO versions

### Problem 3: Global State Initialization Order

Modules define global state tables (`Orders`, `Intents`, `Balances`, etc.) that need to be initialized before use. Top-level requires create implicit initialization dependencies that are fragile and hard to reason about.

Without a robust module loading pattern, the marketplace process suffers from:
- Inability to handle circular module dependencies
- Brittleness to AO runtime updates
- Unclear initialization order
- Difficult testing and mocking
- Tight coupling between modules

## Decision

We will use **lazy module loading** where `require()` calls are placed inside functions rather than at module top-level. Modules are loaded on-demand when functions are actually called.

### Pattern

```lua
-- In ucm.lua

function ucm.cancelOrder(orderId, reason, msg)
    -- Load modules on-demand inside function
    local _intents = require('intents')
    local _utils = require('utils')
    
    local order = Orders[orderId]
    assert(order, 'Order not found: ' .. orderId)
    
    -- Use the loaded modules
    _utils.refund(order.seller, order.quantity)
    _intents.failIntent(order.intentId, reason, msg)
    
    order.status = 'cancelled'
end
```

### Naming Convention

Use underscore prefix for lazy-loaded modules to distinguish from parameters:

```lua
function myFunction(msg, utils)  -- 'utils' is a parameter
    local _utils = require('utils')  -- '_utils' is lazy-loaded module
    local _balances = require('balances')
    
    -- Clear distinction between parameter and module
end
```

### Global State Access

Modules can directly access global state tables without requiring:

```lua
function ucm.getOrder(orderId)
    -- Direct global access (no require needed)
    return Orders[orderId]
end

function ucm.createOrder(orderArgs)
    local _intents = require('intents')  -- Only require when needed
    
    -- Create intent first
    local intentId = _intents.createIntent({...})
    
    -- Store in global state
    Orders[orderArgs.orderId] = {...}
end
```

Global state tables are initialized in `globals.lua` and available throughout execution.

## Consequences

### Positive

1. **Circular Dependencies Resolved**: Modules can depend on each other without load-time errors
2. **AO Update Resilience**: Changes to AO module loading only affect runtime, not initialization
3. **Clear Execution Flow**: Module dependencies are explicit at point of use
4. **Easier Testing**: Can mock modules by replacing globals before function calls
5. **Lazy Initialization**: Modules only load when actually used
6. **Reduced Memory**: Unused modules never load in certain code paths
7. **Runtime Flexibility**: Can conditionally load different modules
8. **Debugging**: Easier to trace which function triggered module loads

### Negative

1. **Repeated Calls**: Each function call re-requires modules (though Lua caches them)
2. **Verbosity**: Every function must declare its dependencies internally
3. **Performance Overhead**: Tiny overhead from `require()` calls (negligible due to caching)
4. **Code Duplication**: Similar `require()` calls repeated across functions
5. **Visibility**: Harder to see module dependencies at file top-level
6. **Convention Reliance**: Requires team discipline to maintain pattern

### Neutral

1. **Lua Caching**: `require()` caches modules, so repeated calls return same table
2. **No Runtime Check**: Lua doesn't prevent circular requires, just returns partial modules
3. **Global State Direct**: Global tables accessed directly, not through requires
4. **Local Scope**: Required modules are local to function, can't leak between calls

## Alternatives Considered

### 1. Dependency Injection

Pass all dependencies as function parameters:

```lua
function ucm.cancelOrder(orderId, reason, msg, intents, utils, balances)
    intents.failIntent(...)
    utils.refund(...)
end
```

**Rejected because**:
- Extremely verbose function signatures
- Difficult to manage deep call chains
- Doesn't solve AO update issues
- Poor developer experience
- Doesn't fit Lua/AO conventions

### 2. Module Initialization Function

Use explicit initialization phase to wire up dependencies:

```lua
-- ucm.lua
local intents, utils

function ucm.init(deps)
    intents = deps.intents
    utils = deps.utils
end
```

**Rejected because**:
- Adds complexity to process startup
- Requires careful initialization ordering
- Doesn't prevent circular dependencies
- Extra boilerplate in every module
- Fragile to initialization mistakes

### 3. Service Locator Pattern

Use a central registry to lookup modules:

```lua
function ucm.cancelOrder(orderId)
    local intents = ServiceLocator.get('intents')
    local utils = ServiceLocator.get('utils')
end
```

**Rejected because**:
- Adds unnecessary abstraction layer
- Requires maintaining service registry
- Not idiomatic in Lua/AO
- Hides dependencies from static analysis
- Over-engineered for the problem

### 4. Require with Careful Ordering

Carefully order requires to avoid circular dependencies:

```lua
-- Load in specific order at top of file
local utils = require('utils')
-- DON'T require balances (creates cycle)
```

**Rejected because**:
- Fragile and difficult to maintain
- Breaks when adding new dependencies
- Doesn't solve AO update issues
- Creates artificial constraints
- Poor scalability

### 5. Forward Declarations

Use forward declarations and late binding:

```lua
local intents  -- Forward declaration

function ucm.cancelOrder()
    intents = intents or require('intents')  -- Lazy load
end
```

**Rejected because**:
- Module-level state is problematic
- Requires mutable module state
- Confusion between nil and not-loaded
- Doesn't solve circular dependencies cleanly
- Less clear than function-level requires

## Implementation Notes

### Where to Use Lazy Loading

**Always use lazy loading for**:
- Cross-module function calls (`utils`, `balances`, `intents`, `ucm`)
- Helper modules that might have circular dependencies
- Modules that use global state from other modules

**Don't use lazy loading for**:
- Built-in Lua libraries (`json`, `bint`)
- External dependencies (`ao`, `crypto`)
- Modules with no circular dependency risk
- Pure data or constants

Example:

```lua
-- Top-level requires (safe, no circular deps)
local json = require('json')
local bint = require('.bint')(512)

function myFunction()
    -- Lazy requires (circular dependency risk)
    local _utils = require('utils')
    local _balances = require('balances')
    
    -- Use both
    local data = json.decode(...)
    _utils.validate(data)
end
```

### Handling AO Updates

Lazy loading helps with AO updates in several ways:

1. **Module Loading Changes**: If AO changes how `require()` works, only affects runtime
2. **Global State Access**: Direct global access is more stable than module references
3. **Runtime Flexibility**: Can adapt to different AO versions at runtime
4. **Graceful Degradation**: Can check AO version and load conditionally

Example:

```lua
function ucm.createOrder(orderArgs)
    -- Works across AO versions that may change require() behavior
    local _intents = require('intents')
    
    -- Direct global access (stable across updates)
    Orders[orderArgs.orderId] = {...}
end
```

### Testing Benefits

Lazy loading makes testing easier:

```lua
-- test_ucm.lua
-- Mock modules by replacing globals before calling functions
_G.require = function(name)
    if name == 'intents' then
        return {
            createIntent = function() return 'mock-intent-id' end
        }
    end
    return _G._original_require(name)
end

-- Now call function - it will use mocked modules
ucm.createOrder({...})
```

### Performance Considerations

Lua caches `require()` results in `package.loaded`:

```lua
-- First call loads module
local utils1 = require('utils')  -- Loads and caches

-- Subsequent calls return cached table
local utils2 = require('utils')  -- Returns cached (fast)

-- utils1 and utils2 reference same table
assert(utils1 == utils2)  -- true
```

Therefore, repeated `require()` calls have minimal overhead (table lookup in cache).

### Debugging Tips

When debugging circular dependencies:

1. Check `package.loaded` to see what's cached
2. Use print statements in module top-level to track load order
3. Temporarily add assertions to verify module state
4. Use AO process logs to trace require() calls

## References

- [Lua `require()` Documentation](https://www.lua.org/manual/5.4/manual.html#pdf-require)
- [Lua Module Loading Caching](https://www.lua.org/manual/5.4/manual.html#pdf-package.loaded)
- AO Process Module System Documentation
- Source: All module files in `src/*.lua`

## Future Considerations

1. **Static Analysis**: Tools to detect circular dependencies at build time
2. **Module Map**: Visualize module dependency graph
3. **Load Metrics**: Track which modules are loaded by which functions
4. **Conditional Loading**: Load different modules based on feature flags
5. **Module Versions**: Support multiple versions of same module
6. **Preloading**: Option to preload critical modules for performance
7. **Module Registry**: Central registry of available modules and versions
8. **Dependency Documentation**: Auto-document which modules depend on which

