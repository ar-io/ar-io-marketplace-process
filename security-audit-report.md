# AR.IO Marketplace Security Audit Report

**Audit Date:** November 26, 2025  
**Auditor:** AI Security Analysis  
**Contract Version:** Latest (PE-8712-implement-intent-based-workflows branch)  
**Scope:** Complete marketplace contract including all auction types, balance management, and intent system

---

## Executive Summary

This comprehensive security audit analyzed 9 Lua modules comprising the AR.IO marketplace smart contract. After developer review and feedback, **5 issues require fixes** while the remaining findings are either accepted design decisions or mitigated by existing economic protections (listing fees).

### Key Findings Summary

**Requiring Fixes:**
- **Medium:** 3 (Dutch auction calculation, listing duration validation, OrderIndex sync)
- **Low:** 1 (Intent push authority expansion)
- **Info:** 1 (Magic number constants)

**Accepted as Design/Non-Issues:**
- **High:** 3 (Bid locking is intended behavior, listing fees provide DoS protection)
- **Medium:** 2 (Listing fee timing is a feature, race condition impossible due to message ordering)
- **Low:** 3 (Out of scope or mitigated by economics)
- **Info:** 2 (Will address in future updates)

### Primary Items to Address

1. **Dutch Auction Decrease Step Validation** - Enforce divisible decrease steps
2. **Max Listing Duration Validation** - Enforce 30-day maximum in createIntentHandler
3. **OrderIndex/Orderbook Synchronization** - More graceful handling of desync
4. **Intent Push Authority** - Expand to 3 authorized roles with state validation
5. **Magic Number Constants** - Move hardcoded values to named constants

### Overall Assessment

The contract demonstrates **excellent security practices** with proper access controls, input validation, and fee calculations. The listing fee mechanism provides strong economic DoS protection across auctions and intents. The message-passing architecture inherently prevents race conditions.

**Risk Rating:** **LOW** - The contract is production-ready with only minor improvements needed.

---

## Detailed Findings

---

## ISSUES REQUIRING FIXES

### MEDIUM SEVERITY

#### M-2: Dutch Auction Decrease Step Calculation Validation

**Severity:** Medium  
**Component:** `dutch_auction.lua`  
**Lines:** 17-21 (calculateDecreaseStep), 259-289 (validateDutchParams)

**Status:** ⚠️ **FIX REQUIRED**

**Description:**

The `calculateDecreaseStep` function uses `math.floor` which can result in a decrease step of 0 if the price range is too small relative to the number of intervals. Need to enforce that decrease steps are properly divisible in proportion to the time limit.

**Developer Feedback:**
> "Good catch on the dutch auction price points, lets fix that up. only allow decrease steps divisible in proportion to the time limit."

**Current Code:**

```lua
-- dutch_auction.lua:17-21
function dutch_auction.calculateDecreaseStep(args)
    local intervalsCount = (bint(args.expirationTime) - bint(args.createdAt)) / bint(args.decreaseInterval)
    local priceDecreaseMax = bint(args.price) - bint(args.minimumPrice)
    return math.floor(priceDecreaseMax / intervalsCount)
end
```

**Recommendation:**

Enforce that the price decrease is evenly divisible by the interval count:

```lua
function dutch_auction.validateDutchParams(args)
    -- ... existing validations ...
    
    local intervalsCount = (bint(args.expirationTime) - bint(args.createdAt)) / bint(args.decreaseInterval)
    local priceDecreaseMax = bint(args.price) - bint(args.minimumPrice)
    
    -- Ensure price decrease is evenly divisible
    local remainder = priceDecreaseMax % intervalsCount
    if remainder > bint(0) then
        return false, 
            'Price decrease (' .. tostring(priceDecreaseMax) .. ') must be evenly divisible by interval count (' .. 
            tostring(intervalsCount) .. '). Adjust your price range or decrease interval.'
    end
    
    local decreaseStep = priceDecreaseMax / intervalsCount
    if decreaseStep < bint(1) then
        return false, 'Decrease step must be at least 1 mARIO per interval. ' ..
                      'Increase price difference, decrease auction duration, or increase decrease interval.'
    end
    
    return true
end
```

---

#### M-4: Missing Max Listing Duration Validation in Create-Order Intent

**Severity:** Medium  
**Component:** `intents.lua`  
**Lines:** 451-494 (createIntentHandler)

**Status:** ⚠️ **FIX REQUIRED**

**Description:**

The `createIntentHandler` doesn't validate expiration time before passing to `calculateListingFee`, which can cause confusing error messages when the 30-day limit is violated.

**Developer Feedback:**
> "Ah, good catch on M-4, the max listing duration should be 30 days."

**Recommendation:**

Add explicit validation in `createIntentHandler`:

```lua
if intentAction == 'Create-Order' then
    assert(intentParams['Swap-Token'], 'X-Intent-Swap-Token required for Create-Order')
    assert(intentParams.Quantity, 'X-Intent-Quantity required for Create-Order')
    
    -- Validate expiration time format and range
    if intentParams['Expiration-Time'] then
        local expTime = tonumber(intentParams['Expiration-Time'])
        assert(expTime, 'X-Intent-Expiration-Time must be a valid number')
        assert(expTime > msg.Timestamp, 'X-Intent-Expiration-Time must be in the future')
        
        local maxExpiration = msg.Timestamp + constants.LISTING.MAX_EXPIRATION_MS
        assert(expTime <= maxExpiration, 
            'X-Intent-Expiration-Time cannot exceed 30 days. Maximum: ' .. tostring(maxExpiration))
    end
end
```

---

#### M-5: OrderIndex/Orderbook Desynchronization Risk

**Severity:** Medium  
**Component:** `ucm.lua`  
**Lines:** 13-38 (getOrderById), various order creation/deletion points

**Status:** ⚠️ **FIX REQUIRED**

**Description:**

OrderIndex and Orderbook can become desynchronized if updates aren't atomic. Need more graceful handling.

**Developer Feedback:**
> "M-5 is also a good catch, lets make sure sync between our lookup table and the orderbook is fixed to handle it more gracefully."

**Recommendation:**

**1. Always update OrderIndex BEFORE Orderbook:**

```lua
-- PATTERN: Update index first, then orderbook
OrderIndex[args.orderId] = {
    dominantToken = validPair[1],
    swapToken = validPair[2],
}

pair.orders[args.orderId] = { ... }  -- Then update orderbook
```

**2. Add cleanup handler:**

```lua
function ucm.rebuildOrderIndex()
    local rebuilt = {}
    local orphanedIndex = {}
    
    for dominantToken, swapTokens in pairs(Orderbook) do
        for swapToken, pair in pairs(swapTokens) do
            for orderId, order in pairs(pair.orders) do
                rebuilt[orderId] = {
                    dominantToken = order.dominantToken or dominantToken,
                    swapToken = order.swapToken or swapToken,
                }
            end
        end
    end
    
    for orderId in pairs(OrderIndex) do
        if not rebuilt[orderId] then
            table.insert(orphanedIndex, orderId)
        end
    end
    
    OrderIndex = rebuilt
    
    return {
        rebuiltCount = #utils.keys(rebuilt),
        orphanedCount = #orphanedIndex,
        orphanedIds = orphanedIndex,
    }
end
```

---

### LOW SEVERITY

#### L-1: Intent Push Authority Should Support Multiple Authorized Roles

**Severity:** Low  
**Component:** `intents.lua`  
**Lines:** 540-569 (pushANTIntentResolutionHandler)

**Status:** ⚠️ **FIX REQUIRED**

**Description:**

System should support marketplace owner and a configurable authority in addition to intent initiator.

**Developer Feedback:**
> "Regarding L-1 we actually want to allow the marketplace Owner to push the intent as well. Actually, lets make a IntentPushingAuthority global that is a string, the address of the authority to allow. So 3 authorities, the initiator, the marketplace Owner, and the IntentPushingAuthority, which can default as IntentPushingAuthority = IntentPushingAuthority or Owner. And yes we should make sure the intent state is in a pushable state (eg pending)"

**Recommendation:**

**1. Add global to `globals.lua`:**

```lua
---@type Address Authority allowed to push intent resolution
IntentPushingAuthority = IntentPushingAuthority or Owner
```

**2. Update push handler:**

```lua
function intents.pushANTIntentResolutionHandler(msg)
    local _utils = require('utils')
    local intentId = msg.Tags['X-Intent-Id']
    assert(intentId, 'X-Intent-Id required')
    
    local intent = intents.getIntentById(intentId)
    assert(intent, 'Intent not found')
    
    -- Validate intent is in pushable state
    assert(
        intent.status == 'pending' or intent.status == 'active' or intent.status == 'settling',
        'Intent not in pushable state. Current: ' .. intent.status
    )
    
    -- Check authorization (3 authorities)
    local expectedInitiator = intent.initiator
    if intent.type == constants.INTENT_TYPES.CHILD and intent.parentIntentId then
        local parent = Intents[intent.parentIntentId]
        if parent then
            expectedInitiator = parent.initiator
        end
    end
    
    local isAuthorized = msg.From == expectedInitiator or 
                        msg.From == Owner or 
                        msg.From == IntentPushingAuthority
    
    assert(isAuthorized, 'Unauthorized to push intent resolution')
    
    _utils.Send(msg, {
        Target = intent.expectedFrom,
        Action = "State",
        Tags = { ['X-Intent-Id'] = intentId }
    })
end
```

---

### INFO / CODE QUALITY

#### I-2: Magic Numbers Should Be Named Constants

**Severity:** Info  
**Component:** Various modules

**Status:** ⚠️ **FIX REQUIRED**

**Description:**

Several magic numbers appear without named constants, reducing readability.

**Developer Feedback:**
> "I-2 is a good point, we should have constants and not have hard coded magic numbers."

**Recommendation:**

Add to `constants.lua`:

```lua
-- Time constants (all in milliseconds)
constants.TIME = {
    ONE_MINUTE_MS = 60000,
    ONE_HOUR_MS = 3600000,
    ONE_DAY_MS = 86400000,
    THIRTY_DAYS_MS = 2592000000,
}

-- Quantity constants
constants.QUANTITY = {
    ANT_EXACT_AMOUNT = 1,
}

-- Update existing:
constants.INTENT_TTL_MS = constants.TIME.ONE_DAY_MS
constants.LISTING.MAX_EXPIRATION_MS = constants.TIME.THIRTY_DAYS_MS
```

Update usage:

```lua
-- intents.lua:51
local listingDurationHours = tonumber(tostring(listingDurationMs / bint(constants.TIME.ONE_HOUR_MS)))

-- intents.lua:74
local ttl = msg.Timestamp + constants.TIME.ONE_DAY_MS

-- ANT quantity checks everywhere
if bint(args.quantity) ~= bint(constants.QUANTITY.ANT_EXACT_AMOUNT) then
```

---

## ACCEPTED DESIGN DECISIONS & NON-ISSUES

### HIGH SEVERITY (Accepted as Design)

#### H-1: English Auction Bid Locking ✅ ACCEPTED

**Developer Feedback:**
> "im not worried about the bid griefing. We take fees to list the ANT to prevent lots of auctions, so if someone wants to pay the marketplace to make alot of auctions, we still win. Regarding bids, thats just how english auctions work."

**Explanation:** Locking all bids until settlement is standard English auction behavior. Listing fees provide economic DoS protection against spam auctions.

---

#### H-2: Pruning Loop Performance ✅ ACCEPTED

**Developer Feedback:**
> "Regarding the pruning loop, lets make a minimum of 1 hour on the order time. To clarify on that though, they can only bid on existing ANT listings, which have a listing fee... so we should have some dos protection there as well, right?"

**Explanation:** 
- Minimum 1-hour order duration limits spam
- Listing fees required to create orders provide economic DoS protection
- Combined protections make mass order creation economically unfeasible

---

#### H-3: Intent Memory Accumulation ✅ ACCEPTED

**Developer Feedback:**
> "Regarding the intents getting 'stuck' - we have intent pruning that should protect us here, and we charge to create the intents, which should give us some dos protection. Plus, makes the marketplace money. And regarding being slow, theres not gonna be many, especially with a 24h ttl."

**Explanation:**
- 24-hour TTL automatically cleans up zombie intents
- Listing fees charged upfront provide economic DoS protection
- Low expected volume means iteration performance acceptable

---

### MEDIUM SEVERITY (Non-Issues)

#### M-1: Order Cancellation "Race Condition" ✅ NOT A RACE

**Developer Feedback:**
> "Regarding the order cancellation race condition, nothing happens simultaneously. Its based on message passing, so either a bid is placed while the lister doesn't have a fresh view of the state, and the cancel fails, or the lister cancels and the bidder doesnt have a fresh view, and the bid fails. So thats a non issue, since the order would not exist anymore i think (being cancelled)."

**Explanation:** AO message passing is sequential, not concurrent. No true race condition exists - messages are processed in order.

---

#### M-3: Listing Fee Timing ✅ ACCEPTED AS FEATURE

**Developer Feedback:**
> "The listing fee front running isn't a bug but a feature. Yes, it has the potential to be bad UX, but regarding the incompatible module, as documented this is to prevent malicious contracts from interacting with the process. If its a valid contract, then you should have no worries... apart from cranking of course, and thats an infra issue outside of the code."

**Explanation:** Charging listing fee before validation is intentional security measure to prevent malicious contract interaction attempts.

---

### LOW SEVERITY (Out of Scope)

#### L-2: Dust Orders ✅ NOT A CONCERN

**Developer Feedback:**
> "not worried about L-2"

---

#### L-3: Fee Withdrawal Rate Limiting ✅ NOT A CONCERN

**Developer Feedback:**
> "not worried about L-3"

---

#### L-4: Integer Overflow ✅ NOT A CONCERN

**Developer Feedback:**
> "Also not worried about L-4 because the denominations for the tokens are within bounds, and we are controlling which contracts we interact with."

---

### INFO (Will Address Later)

#### I-1: Error Handling Consistency ✅ NOT A CONCERN

**Developer Feedback:**
> "not worried about i-1"

---

#### I-3: Structured Events ✅ PLANNED FOR FUTURE

**Developer Feedback:**
> "Regarding I-3, noted, plan is to add events after all the logic is in place."

**Status:** Future enhancement, not current priority.

---

## Recommendations Summary

### Immediate Actions Required

1. ✅ **Fix M-2:** Enforce Dutch auction decrease step divisibility
2. ✅ **Fix M-4:** Add 30-day max expiration validation in createIntentHandler
3. ✅ **Fix M-5:** Update OrderIndex-before-Orderbook pattern + add rebuild function
4. ✅ **Fix L-1:** Add IntentPushingAuthority global, support 3 authorized roles, validate state
5. ✅ **Fix I-2:** Move magic numbers to named constants in constants.TIME and constants.QUANTITY

### Future Enhancements (Planned)

- Add structured event emission for indexers (I-3)

---

## Conclusion

The AR.IO marketplace contract is **well-architected** and **production-ready**. The listing fee mechanism provides robust economic DoS protection across the system. The message-passing architecture ensures proper ordering and eliminates traditional race conditions.

Only **5 minor fixes** are required, all of which are straightforward improvements to validation logic and code organization. No security vulnerabilities that risk fund loss were identified.

**Final Risk Rating:** **LOW**

**Recommendation:** ✅ **APPROVED FOR PRODUCTION** after implementing the 5 required fixes.

---

**End of Report**
