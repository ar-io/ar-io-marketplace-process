local intents = {}
local bint = require('.bint')(256)
local json = require('json')
local constants = require('constants')

--- Increment the global intent counter and return the new ID
--- @return IntentId intentId The new intent ID
function intents.incrementIntentCounter()
	IntentCounter = tostring(bint(IntentCounter) + bint(1))
	return tostring(IntentCounter)
end

-- TODO: expirationTime should be required and asserted
--- Calculate the listing fee based on duration
--- Minimum duration is 1 hour - shorter durations are charged the 1-hour rate
--- @param expirationTime BalanceAmount|number|nil The expiration timestamp (nil for no expiration)
--- @param currentTimestamp number The current timestamp in milliseconds
--- @return BalanceAmount|nil listingFee The calculated listing fee in mARIO (nil on error)
--- @return string|nil error Error message if validation fails (nil on success)
function intents.calculateListingFee(expirationTime, currentTimestamp)
	local listingFee = bint(constants.FEE.LISTING_FEE_ARIO)
	
	if not expirationTime then
		-- No expiration time, use base fee (1 hour minimum)
		return tostring(listingFee), nil
	end
	
	-- Validate expiration time is a number
	local expTime = tonumber(expirationTime)
	-- TODO: should be an assertion
	if not expTime then
		return nil, 'Expiration time must be a valid number'
	end
	
	-- Calculate listing duration (using regular numbers for timestamps)
	local listingDurationMs = expTime - currentTimestamp
	
	-- Validate duration is positive
	if listingDurationMs <= 0 then
		return nil, 'Expiration time must be in the future'
	end
	
	-- Validate duration doesn't exceed maximum (30 days)
	if listingDurationMs > constants.LISTING.MAX_EXPIRATION_MS then
		return nil, 'Expiration time cannot exceed 30 days'
	end
	
	-- TODO: if less than 1 hour, assert error. This
	-- Clamp minimum duration to 1 hour
	if listingDurationMs < constants.LISTING.MIN_EXPIRATION_MS then
		listingDurationMs = constants.LISTING.MIN_EXPIRATION_MS
	end
	
	-- Calculate fee based on duration (1 ARIO per hour)
	local listingDurationHours = listingDurationMs / constants.LISTING.MIN_EXPIRATION_MS -- Convert ms to hours
	local hoursPerFee = constants.FEE.LISTING_FEE_MULTIPLIER_HOURS -- 1 hour per fee (1 ARIO per hour)
	
	-- Calculate multiplier: ceiling of (hours / hoursPerFee)
	local feeMultiplier = math.ceil(listingDurationHours / hoursPerFee)
	if feeMultiplier < 1 then
		feeMultiplier = 1
	end
	
	listingFee = listingFee * bint(feeMultiplier)
	
	return tostring(listingFee), nil
end

--- Create an intent
--- @param msg Message The incoming message
--- @param orderParams OrderIntentParams User-provided order parameters (stored as-is; action in intent.action, swapToken always ARIO)
--- @param antProcessId TokenId The ANT process ID for this intent
--- @return Intent intent The created intent
function intents.createIntent(msg, orderParams, antProcessId)
	local balances = require('balances')
	
	-- Calculate TTL (24 hours from creation)
	local ttl = msg.Timestamp + constants.TIME.ONE_DAY_MS
	
	-- Calculate and charge listing fee
	local expirationTime = orderParams.expirationTime
	
	local listingFee, feeError = intents.calculateListingFee(expirationTime, msg.Timestamp)
	assert(not feeError, feeError)
	
	-- Validate and charge fee
	assert(
		balances.walletHasSufficientBalance(msg.From, listingFee),
		'Insufficient ARIO balance for listing fee. Required: ' .. listingFee
	)
	balances.transfer(TREASURY_ADDRESS, msg.From, listingFee, true)
	
	local intent = {
		intentId = intents.incrementIntentCounter(),
		initiator = msg.From,
		action = 'Create-Order', -- Only Create-Order is supported
		status = constants.INTENT_STATUSES.PENDING,
		createdAt = msg.Timestamp,
		ttl = ttl,
		resolvedAt = nil,
		completedAt = nil,
		failureReason = nil,
		orderParams = orderParams, -- Always a table from createIntentHandler
		antProcessId = antProcessId, -- ANT process ID set at creation
	}

	Intents[intent.intentId] = intent
	
	-- Schedule pruning for this intent's TTL
	intents.scheduleNextIntentsPruning(ttl)
	
	return intent
end

--- Resolve an intent
--- Handles status transitions and pruning of intents in terminal states
--- @param intentId IntentId The intent ID to resolve
--- @param timestamp number The timestamp of resolution
--- @return boolean success Whether the resolution was successful
--- @return table|nil resolvedIntent The resolved intent data if pruned, nil otherwise
function intents.resolveIntent(intentId, timestamp)
	local intent = Intents[intentId]
	if not intent then
		return false
	end

	local resolvedIntent = nil

	-- Intent resolution (pending -> active)
	if intent.status == constants.INTENT_STATUSES.PENDING then
		intent.status = constants.INTENT_STATUSES.ACTIVE
		intent.resolvedAt = timestamp
	end

	-- Prune intents when they reach terminal states
	if intent.status == constants.INTENT_STATUSES.COMPLETED or intent.status == constants.INTENT_STATUSES.FAILED then
		-- Capture intent data BEFORE pruning
		resolvedIntent = {
			intentId = intent.intentId,
			initiator = intent.initiator,
			action = intent.action,
			status = intent.status,
			resolvedAt = timestamp,
			failureReason = intent.failureReason,
		}

		-- Delete intent
		Intents[intentId] = nil
	end

	return true, resolvedIntent
end

--- Fail an intent with a reason
--- @param intentId IntentId The intent ID to fail
--- @param reason string The failure reason
--- @param msg table|nil The message context (optional, for sending notices)
--- @return boolean success Whether the failure was recorded
function intents.failIntent(intentId, reason, msg)
	local _utils = require('utils')
	local intent = Intents[intentId]
	if not intent then
		return false
	end

	intent.status = constants.INTENT_STATUSES.FAILED
	intent.failureReason = reason

	-- Use resolveIntent to handle pruning logic centrally
	local success, resolvedIntent = intents.resolveIntent(intentId, os.time())

	-- Send Intent-Resolved notice AFTER pruning succeeds
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

--- Update intent status
--- @param intentId IntentId The intent ID
--- @param status "pending"|"active"|"settling"|"completed"|"resolved"|"failed" The new status
--- @param msg Message The message context for sending notices
--- @return boolean success Whether the update was successful
function intents.updateIntentStatus(intentId, status, msg)
	local _utils = require('utils')
	local intent = Intents[intentId]
	if not intent then
		return false
	end

	intent.status = status

	-- Set completedAt timestamp if moving to completed
	if status == constants.INTENT_STATUSES.COMPLETED then
		intent.completedAt = msg.Timestamp
	end

	-- Use resolveIntent to handle pruning logic centrally for terminal states
	if status == constants.INTENT_STATUSES.COMPLETED or status == constants.INTENT_STATUSES.FAILED then
		local success, resolvedIntent = intents.resolveIntent(intentId, msg.Timestamp)

		-- Send Intent-Resolved notice AFTER pruning succeeds
		if success and resolvedIntent then
			_utils.Send(msg, {
				Target = resolvedIntent.initiator,
				Action = 'Intent-Resolved',
				['Intent-Id'] = tostring(resolvedIntent.intentId),
				Status = resolvedIntent.status,
				['Intent-Action'] = resolvedIntent.action,
				['Failure-Reason'] = resolvedIntent.failureReason or 'unknown',
			})
		end
	end

	return true
end

--- Get intent by ID
--- @param intentId IntentId The intent ID
--- @return Intent|nil intent The intent or nil if not found
function intents.getIntentById(intentId)
	return Intents[intentId]
end

--- Get all pending intents
--- @return Intent[] pending Array of pending intents
function intents.getPendingIntents()
	local pending = {}
	for _, intent in pairs(Intents) do
		if intent.status == constants.INTENT_STATUSES.PENDING then
			table.insert(pending, intent)
		end
	end
	return pending
end

--- Get intents by status
--- @param status string The status to filter by
--- @return Intent[] filtered Array of intents with the given status
function intents.getIntentsByStatus(status)
	local filtered = {}
	for _, intent in pairs(Intents) do
		if intent.status == status then
			table.insert(filtered, intent)
		end
	end
	return filtered
end

--- Validate that an intent exists
--- @param intentId IntentId The intent ID
--- @return boolean exists Boolean indicating if intent exists
function intents.validateIntentExists(intentId)
	return Intents[intentId] ~= nil
end

--- Get all intents as an array for pagination
--- @return Intent[] allIntents Array of all intents
function intents.getAllIntents()
	local allIntents = {}
	for _, intent in pairs(Intents) do
		table.insert(allIntents, intent)
	end
	return allIntents
end

--- Schedule the next intents pruning if the given timestamp is sooner than the current scheduled time
--- @param timestamp number The timestamp to schedule pruning for
function intents.scheduleNextIntentsPruning(timestamp)
	-- TODO: should be an assertion
	if not timestamp then
		return
	end

	-- Initialize if needed
	if not Pruning then
		Pruning = { nextScheduledIntentsPruning = nil }
	end

	-- Schedule if no prune scheduled or if this one is sooner
	if not Pruning.nextScheduledIntentsPruning or timestamp < Pruning.nextScheduledIntentsPruning then
		Pruning.nextScheduledIntentsPruning = timestamp
	end
end

--- Prune expired intents from the Intents table
--- Returns early if it's not time to prune yet
--- @param now number The current timestamp
function intents.pruneIntents(now)
	-- Return early if no pruning is scheduled or not time yet
	if not Pruning or not Pruning.nextScheduledIntentsPruning or now < Pruning.nextScheduledIntentsPruning then
		return
	end

	-- Track the next earliest TTL for rescheduling
	local nextTTL = nil

	-- Iterate through all intents and fail expired ones
	for intentId, intent in pairs(Intents) do
		if intent.ttl then
			if now >= intent.ttl then
				-- Intent has expired, fail it (no msg context for pruning)
				intents.failIntent(intentId, 'Intent expired (24h TTL)', nil)
			else
				-- Track the next expiration
				if not nextTTL or intent.ttl < nextTTL then
					nextTTL = intent.ttl
				end
			end
		end
	end

	-- Schedule the next prune
	Pruning.nextScheduledIntentsPruning = nextTTL
end

-- Handler: Create-Intent
-- This handler is only for ANT sell orders (Create-Order only)
-- ARIO buy orders don't use intents - they use Create-Order handler directly
-- Action is always 'Create-Order' (assumed, not required as parameter)
function intents.createIntentHandler(msg)
	local _utils = require('utils')
	
	-- Validate ANT ID is provided and valid
	local antId = msg.Tags['X-Intent-ANT-Id']
	assert(antId, 'X-Intent-ANT-Id required')
	assert(_utils.checkValidAddress(antId), 'X-Intent-ANT-Id must be a valid Arweave ID (43 characters)')
	
	-- Check for existing intents with the same ANT ID (one intent per ANT)
	for _, intent in pairs(Intents) do
		if intent.antProcessId == antId then
			-- Only block if intent is in non-terminal state
			if intent.status == constants.INTENT_STATUSES.PENDING or 
			   intent.status == constants.INTENT_STATUSES.ACTIVE or 
			   intent.status == constants.INTENT_STATUSES.SETTLING then
				error('An intent already exists for this ANT ID. Intent ID: ' .. intent.intentId)
			end
		end
	end
	
	-- Extract order parameters from X-Intent-* tags (Train-Case)
	---@type OrderIntentParams
	local orderParams = {
		-- Order configuration
		orderType = msg.Tags['X-Intent-Order-Type'], -- nil = defaults to 'fixed', or 'dutch'/'english'
		quantity = msg.Tags['X-Intent-Quantity'], -- Required: amount to trade (usually '1' for ANT)
		price = msg.Tags['X-Intent-Price'], -- Required: asking price or starting bid
		expirationTime = msg.Tags['X-Intent-Expiration-Time'], -- Required: Unix timestamp (min 1h, max 30 days, rounded up to nearest hour)
		
		-- Dutch auction only: price decay parameters
		minimumPrice = msg.Tags['X-Intent-Minimum-Price'], -- nil unless order-type is 'dutch'
		decreaseInterval = msg.Tags['X-Intent-Decrease-Interval'], -- nil unless order-type is 'dutch'
	}
	
	-- Determine order type (default to 'fixed')
	local orderType = orderParams.orderType or 'fixed'
	
	-- Validate common required parameters (all order types)
	assert(orderParams.quantity, 'X-Intent-Quantity required')
	assert(orderParams.price, 'X-Intent-Price required')
	assert(orderParams.expirationTime, 'X-Intent-Expiration-Time required')

	-- Validate expiration time format and range
	local expTime = tonumber(orderParams.expirationTime)
	assert(expTime, 'X-Intent-Expiration-Time must be a valid number')
	assert(expTime > msg.Timestamp, 'X-Intent-Expiration-Time must be in the future')
	
	local maxExpiration = msg.Timestamp + constants.LISTING.MAX_EXPIRATION_MS
	assert(expTime <= maxExpiration, 
		'X-Intent-Expiration-Time cannot exceed 30 days from now. Maximum allowed: ' .. tostring(maxExpiration))
	
	-- Validate order type-specific parameters
	if orderType == 'dutch' then
		assert(orderParams.minimumPrice, 'X-Intent-Minimum-Price required for dutch auction')
		assert(orderParams.decreaseInterval, 'X-Intent-Decrease-Interval required for dutch auction')
	elseif orderType == 'english' then
		-- English auctions only need the common parameters (price is starting bid)
		-- No additional validation needed here
	elseif orderType == 'fixed' then
		-- Fixed price orders only need the common parameters
		-- No additional validation needed here
	else
		error('Invalid order type: ' .. tostring(orderType) .. '. Must be fixed, dutch, or english')
	end

	-- Note: Full validation will happen in Credit-Notice or State-Notice handler
	-- This is just basic parameter presence check

	-- Create intent for Create-Order (action='Create-Order' and swapToken=ARIO added internally)
	local intent = intents.createIntent(msg, orderParams, antId)

	-- Return intentId to user (handler wrapper will send as notice)
	return json.encode({
		['Intent-Id'] = intent.intentId,
		Status = 'Success',
	})
end

-- Handler: Get-Paginated-Intents
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
		page.filters -- { initiator = "address", status = "pending" }
	)

	return json.encode(paginatedIntents)
end

-- Handler: Get-Intent-By-Id
function intents.getIntentByIdHandler(msg)
	local intentId = msg.Tags['Intent-Id']
	assert(intentId, 'Intent-Id required')

	local intent = intents.getIntentById(intentId)
	assert(intent, 'Intent not found')

	return json.encode(intent)
end

function intents.pushANTIntentResolutionHandler(msg)
	local _utils = require('utils')
	local intentId = msg.Tags['X-Intent-Id']
	assert(intentId, 'X-Intent-Id required')

	local intent = intents.getIntentById(intentId)
	assert(intent, 'Intent not found')

	-- Validate intent is in pushable state
	assert(
		intent.status == constants.INTENT_STATUSES.PENDING or 
		intent.status == constants.INTENT_STATUSES.ACTIVE or 
		intent.status == constants.INTENT_STATUSES.SETTLING,
		'Intent is not in a pushable state. Current status: ' .. intent.status
	)

	-- Check against the intent's initiator
	local expectedInitiator = intent.initiator
	
	-- Check if sender is authorized (3 authorities: initiator, Owner, or IntentPushingAuthority)
	local isAuthorized = msg.From == expectedInitiator or 
	                     msg.From == Owner or 
	                     msg.From == IntentPushingAuthority
	
	assert(isAuthorized, 
		'Unauthorized to push intent resolution. Only intent initiator, process owner, or intent pushing authority can push.')

	-- Get ANT process ID from intent (set during Create-Intent)
	local antId = intent.antProcessId
	assert(antId, 'No ANT process ID associated with this intent')

	_utils.Send(msg, {
		Target = antId,
		Action = "State",
		Tags = {
			['X-Intent-Id'] = intentId,
		}
	})
end


-- Handler: State-Notice - Creates order after validating ANT ownership
function intents.stateNoticeHandler(msg)
	local _utils = require('utils')
	local ucm = require('ucm')
	
	local intentId = msg.Tags['X-Intent-Id']
	assert(intentId, 'X-Intent-Id required')
	assert(_utils.isValidIntentId(intentId), 'Invalid X-Intent-Id format')
	local intent = intents.getIntentById(intentId)
	assert(intent, 'Intent not found')
	assert(msg.From == intent.antProcessId, 'Sender does not match intent ANT process ID')

	-- Whitelist check for ANT State-Notice
	if not _utils.isWhitelisted(msg) then
		intents.failIntent(intentId, 'ANT module not whitelisted', msg)
		return
	end

	local antState = _utils.safeDecodeJson(msg.Data)
	assert(antState, 'Invalid State-Notice data')
	local owner = antState.Owner
	assert(owner == ao.id, 'Marketplace does not own this ANT')

	-- Owner matches, resolve the intent (pending → active)
	intents.resolveIntent(intentId, msg.Timestamp)
	
	-- Get order parameters from the intent (stored during Create-Intent)
	local orderParams = intent.orderParams or {}
	
	-- Swap token is always ARIO for intent-based ANT sell orders
	local swapToken = ARIO_TOKEN_PROCESS_ID
	
	-- Build order arguments from intent parameters
	local orderArgs = {
		orderId = msg.Id, -- Use State-Notice message ID as order ID
		dominantToken = intent.antProcessId, -- ANT process ID from intent (set during Create-Intent)
		swapToken = swapToken, -- Always ARIO for ANT sell orders
		sender = intent.initiator, -- Intent creator is the seller
		quantity = orderParams.quantity, -- From intent parameters
		createdAt = msg.Timestamp,
		blockheight = msg['Block-Height'],
		orderType = orderParams.orderType or 'fixed',
		expirationTime = orderParams.expirationTime and tonumber(orderParams.expirationTime),
		minimumPrice = orderParams.minimumPrice,
		decreaseInterval = orderParams.decreaseInterval,
		price = orderParams.price,
		msg = msg, -- Pass msg context for intent tracking
	}
	
	-- Protect order creation to catch unexpected runtime errors
	local ok, err = pcall(function()
		ucm.createOrder(orderArgs)
	end)
	
	if not ok then
		-- Order creation failed - fail the intent
		intents.failIntent(intentId, 'Order creation failed: ' .. tostring(err), msg)
		return
	end
	
	-- Order created successfully - complete the intent
	intents.updateIntentStatus(intentId, constants.INTENT_STATUSES.COMPLETED, msg)
	
	-- Send acknowledgment to the intent initiator
	_utils.Send(msg, {
		Target = intent.initiator,
		Action = 'State-Notice-Processed',
		['Intent-Id'] = intentId,
		['Order-Id'] = msg.Id,
		['ANT-Id'] = msg.From,
		['Owner'] = owner,
		['Intent-Status'] = constants.INTENT_STATUSES.COMPLETED,
		['Order-Status'] = 'listed',
	})
end

return intents
