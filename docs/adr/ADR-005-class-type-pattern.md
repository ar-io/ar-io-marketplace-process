# ADR-005: Class Type Pattern for Typed Fields

## Status

Accepted

## Context

In Lua, especially within the AO environment, typing information for tables is often implicit. When working with complex data structures, developers have several options for expressing type information:

1. **Generic Table Types** - Using `table<string, any>` or similar generic annotations
2. **Inline Type Definitions** - Defining structure inline at point of use
3. **Class-Style Type Definitions** - Using named type aliases with explicit field definitions

Without explicit typing patterns, codebases suffer from:
- Poor IDE support and autocomplete
- Unclear data structure expectations
- Difficulty refactoring and maintaining code
- No compile-time or static analysis validation
- Increased cognitive load when reading unfamiliar code

The marketplace process manages complex state including orders, intents, balances, and auction data. Each of these entities has multiple fields with specific types and constraints. Clear type definitions are essential for:
- Understanding the shape of data structures
- Ensuring consistent field access across modules
- Enabling better tooling support (LSP, linters, type checkers)
- Documenting data contracts between modules

## Decision

We will use **class-style type definitions** for all data structures with named fields. Instead of generic `table<>` annotations, we define explicit type aliases with field-by-field type information.

### Pattern

```lua
-- types.lua

---@class Order
---@field orderId string The unique identifier for the order
---@field seller string The wallet address of the seller
---@field dominantToken string The token being sold
---@field swapToken string The token being purchased
---@field quantity string The amount of dominant token
---@field price string The price per unit (for fixed price orders)
---@field status "active" | "filled" | "cancelled" The current order status
---@field createdAt number Timestamp when order was created
---@field orderType "fixed" | "dutch" | "english" The type of order
---@field expirationTime? number Optional expiration timestamp

---@class Intent
---@field id string Unique identifier for the intent
---@field type "parent" | "child" | "standalone" The intent type
---@field status "pending" | "completed" | "failed" | "expired" Current status
---@field initiator string Wallet address that created the intent
---@field action string The action this intent represents
---@field createdAt number Timestamp of creation
---@field expiresAt number Expiration timestamp
---@field childIntentIds table<string, boolean> Map of child intent IDs
---@field parentIntentId? string Optional parent intent ID
---@field metadata table<string, any> Additional action-specific data
```

### Usage in Code

```lua
-- ucm.lua

---@param orderArgs Order
---@return string orderId
function ucm.createOrder(orderArgs)
    -- IDE now knows all fields of orderArgs
    local order = {
        orderId = orderArgs.orderId,
        seller = orderArgs.seller,
        dominantToken = orderArgs.dominantToken,
        -- etc...
    }
    Orders[order.orderId] = order
    return order.orderId
end

---@param orderId string
---@return Order|nil
function ucm.getOrder(orderId)
    return Orders[orderId]
end
```

### Benefits of Verbose Field Definitions

1. **IDE Autocomplete** - LSP can suggest field names and types
2. **Inline Documentation** - Field descriptions appear in IDE tooltips
3. **Type Checking** - Static analysis tools can validate field access
4. **Refactoring Safety** - Renaming fields shows all usage sites
5. **Discoverability** - New developers can explore data structures via IDE
6. **Validation** - Type checkers can catch invalid field access

### Type Definition Location

All shared types are defined in `src/types.lua` and imported where needed:

```lua
-- At top of module files
---@module 'types'
```

This provides a single source of truth for data structure definitions.

## Consequences

### Positive

1. **Developer Experience**: Significantly improved IDE support with autocomplete and type hints
2. **Documentation**: Type definitions serve as living documentation of data structures
3. **Maintainability**: Easier to understand code without reading entire implementation
4. **Refactoring**: Safe field renames and structure changes with IDE support
5. **Onboarding**: New developers can explore types without reading all code
6. **Static Analysis**: Tools like LuaLS can validate type correctness
7. **Error Prevention**: Catch typos and invalid field access during development
8. **Contract Clarity**: Clear interfaces between modules

### Negative

1. **Verbosity**: Type annotations add more lines of code
2. **Maintenance Burden**: Type definitions must be updated when structures change
3. **Learning Curve**: Developers must learn LuaDoc annotation syntax
4. **No Runtime Validation**: Annotations are compile-time only, no runtime checks
5. **Duplication Risk**: Type definitions can drift from actual implementation
6. **Initial Setup**: Requires upfront effort to define all types

### Neutral

1. **No Runtime Cost**: Annotations are comments, no performance impact
2. **Optional Enforcement**: Developers can ignore annotations if desired
3. **Tooling Dependent**: Benefits require LSP/type checker setup
4. **Convention Based**: Relies on team discipline to maintain consistency

## Alternatives Considered

### 1. Generic Table Types

Use simple `table<string, any>` annotations:

```lua
---@param order table<string, any>
function ucm.createOrder(order)
    -- No field-level type information
end
```

**Rejected because**:
- Provides no field-level information
- No autocomplete for field names
- No validation of field access
- Loses all structure information
- Defeats the purpose of type annotations

### 2. Inline Type Definitions

Define structure inline at each usage:

```lua
---@param order { orderId: string, seller: string, quantity: string }
function ucm.createOrder(order)
    -- Type defined inline
end
```

**Rejected because**:
- Duplicates type definitions across codebase
- Difficult to maintain consistency
- Verbose at call sites
- No single source of truth
- Complicates refactoring

### 3. No Type Annotations

Rely on runtime behavior and code comments:

```lua
-- order should have orderId, seller, quantity fields
function ucm.createOrder(order)
    -- Hope for the best
end
```

**Rejected because**:
- No IDE support
- No static validation
- Comments often become outdated
- Poor developer experience
- Increases bugs from typos

### 4. External Type Definition Files

Use separate `.d.lua` or type definition files:

```lua
-- types.d.lua (separate from implementation)
---@class Order
---@field orderId string
```

**Rejected because**:
- Separates types from code
- Adds file management overhead
- Not standard in Lua ecosystem
- Complicates module loading
- Current approach is simpler

## Implementation Notes

### LuaDoc Annotation Syntax

We use LuaLS (Lua Language Server) annotation syntax:

```lua
---@class TypeName
---@field fieldName type description
```

**Field Type Syntax**:
- `string`, `number`, `boolean` - Primitive types
- `table<K, V>` - Generic tables
- `Type1 | Type2` - Union types
- `Type?` - Optional fields (nil allowed)
- `"literal1" | "literal2"` - String literal unions

### Type File Organization

`src/types.lua` contains all shared type definitions:

```lua
-- Core entity types
---@class Order
---@class Intent
---@class Balance
---@class Auction

-- Helper types
---@class PriceInfo
---@class TransferInfo

-- Action parameter types
---@class CreateOrderParams
---@class CreateIntentParams
```

### Importing Types

At the top of module files:

```lua
---@module 'types'
```

This makes all types from `types.lua` available for annotation.

### Optional Fields

Use `?` suffix for optional fields:

```lua
---@class Order
---@field expirationTime? number  -- Can be nil
```

### Union Types for Status Fields

Use string literals for enum-like fields:

```lua
---@class Intent
---@field status "pending" | "completed" | "failed" | "expired"
```

This provides autocomplete for valid status values and validates assignments.

## References

- [LuaLS Annotations](https://luals.github.io/wiki/annotations/)
- [LuaCATS Type System](https://luals.github.io/wiki/annotations/#type-annotations)
- Source: `src/types.lua` - Type definitions
- AO Documentation on Lua types

## Future Considerations

1. **Runtime Validation**: Add optional runtime type checking for development
2. **Type Generation**: Auto-generate types from schema definitions
3. **Strict Mode**: Enable strict type checking in CI/CD
4. **Type Testing**: Unit tests that validate type definitions match reality
5. **Documentation Generation**: Auto-generate docs from type annotations
6. **Migration Scripts**: Tools to update types when structures change
7. **Type Coverage Metrics**: Track percentage of code with type annotations
8. **Cross-Module Validation**: Ensure type consistency across module boundaries

