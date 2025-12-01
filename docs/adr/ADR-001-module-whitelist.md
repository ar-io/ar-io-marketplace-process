# ADR-001: Module Whitelist for ANT Trading

## Status

Accepted

## Context

The ARNS Marketplace enables trading of Arweave Name Tokens (ANTs) for ARIO tokens through a decentralized order book system. ANTs are external processes that can be transferred to the marketplace, listed for sale, and eventually transferred to buyers. The marketplace relies on two key interactions with ANT processes:

1. **Credit-Notice**: When an ANT is transferred to the marketplace for listing
2. **State-Notice**: When the marketplace queries ANT ownership to verify successful transfers

These interactions assume that ANT processes follow the standard token specification and respond truthfully to queries. However, there is no inherent guarantee that arbitrary processes will behave correctly or honestly. A malicious or buggy ANT process could:

- Provide false ownership information in State-Notices
- Fail to execute transfers properly
- Respond with incorrect or inconsistent state data
- Cause marketplace state corruption or fund loss

Without a trust mechanism, the marketplace is vulnerable to trading in unreliable or malicious assets.

## Decision

We will implement a **module whitelist** system that restricts ANT trading to processes running approved module code. The whitelist will:

1. **Track approved modules** in a global `WhitelistedModules` table keyed by module ID (Arweave transaction address)
2. **Verify ANT messages** by checking the `From-Module` tag against the whitelist
3. **Fail intents for non-whitelisted ANTs** without refunding tokens, as users should not send non-whitelisted assets
4. **Apply only to ANT interactions**, not to ARIO deposits or intent creation

### Implementation Details

#### Whitelist Storage
```lua
-- Global state in globals.lua
WhitelistedModules = WhitelistedModules or {}  -- { [moduleId]: boolean }
```

#### Whitelist Management
```lua
-- In ucm.lua
function ucm.whitelistModule(moduleId)
function ucm.unwhitelistModule(moduleId)
function ucm.whitelistModuleHandler(msg)
function ucm.unwhitelistModuleHandler(msg)
```

#### Whitelist Verification
```lua
-- In utils.lua
function utils.isWhitelisted(msg)
    local fromModule = msg.Tags["From-Module"]
    if not fromModule then
        return false
    end
    return WhitelistedModules[fromModule] == true
end
```

#### Enforcement Points

1. **Credit-Notice Handler** (`notices.creditNoticeHandler`)
   - Applied when ANT tokens (non-ARIO) are sent with `X-Order-Action: Create-Order`
   - Fails the intent if module is not whitelisted
   - ARIO Credit-Notices are unaffected (use address verification)

2. **State-Notice Handler** (`intents.stateNoticeHandler`)
   - Applied when ANT processes respond to ownership queries
   - Fails the intent if module is not whitelisted
   - Prevents completion of transfers involving non-whitelisted ANTs

### What is NOT Whitelisted

- **Intent creation**: Users can freely create intents; the whitelist only blocks execution
- **ARIO deposits**: Continue using existing address-based verification
- **ARIO orders**: Use internal balance system, unaffected by whitelist

## Consequences

### Positive

1. **Security**: Prevents trading of malicious or unreliable ANT processes
2. **Trust**: Ensures all traded ANTs follow verified module implementations
3. **Data integrity**: Protects marketplace state from corrupt or false data
4. **User protection**: Prevents users from losing funds to bad actors
5. **Auditability**: Whitelist provides a clear record of approved modules
6. **Flexibility**: Whitelist can be updated as new trusted modules are released

### Negative

1. **Centralization**: Requires marketplace owner to curate the whitelist
2. **Maintenance burden**: New legitimate ANT modules must be manually whitelisted
3. **User friction**: Users with non-whitelisted ANTs cannot trade immediately
4. **Permission barrier**: Creates a gatekeeping mechanism for ANT trading

### Neutral

1. **No refunds for non-whitelisted assets**: Design choice to discourage sending untrusted assets
2. **Intent failure is final**: Once an intent fails due to whitelist, tokens are not automatically returned
3. **Module-based not process-based**: Trusts the module code, not individual process instances

## Alternatives Considered

### 1. Process-based Whitelist
Instead of whitelisting modules (code), whitelist individual ANT process IDs.

**Rejected because**: 
- Doesn't scale to many ANT instances
- Requires whitelisting every new ANT individually
- Module-based approach is more maintainable

### 2. Signature Verification
Require ANT processes to sign responses with a trusted key.

**Rejected because**:
- More complex implementation
- Requires key management infrastructure
- Module whitelist is simpler and equally effective

### 3. No Whitelist (Trust Any Process)
Allow any process to trade on the marketplace.

**Rejected because**:
- Exposes marketplace and users to significant risk
- No protection against malicious ANTs
- Could result in fund loss or state corruption

### 4. Stake-based Trust System
Require ANT processes to stake tokens as a bond for good behavior.

**Rejected because**:
- Overly complex for the current use case
- Requires additional economic mechanisms
- Module whitelist achieves the goal more simply

## Implementation Notes

- The `From-Module` tag is populated by the AO message system and represents the source code (Arweave transaction) that the sending process is running
- Whitelist management handlers require owner permissions (to be implemented)
- The whitelist is stored in process state and persists across messages
- Empty `From-Module` tags result in `isWhitelisted()` returning false

## References

- [AO Token Specification](https://github.com/permaweb/ao/tree/main/blueprints)
- ARNS Marketplace Specification: `docs/spec.md`
- Intent-based Workflows: Feature branch PE-8712

## Future Considerations

1. **Multi-signature whitelist management**: Require multiple approvers for whitelist changes
2. **Time-locked whitelist updates**: Add delay between whitelist approval and activation
3. **Automated module verification**: Tools to verify module code before whitelisting
4. **Whitelist governance**: Community-driven whitelist curation process
5. **Temporary whitelist entries**: Support for trial periods or expiring whitelist entries

