local intents = {}
local bint = require('.bint')(256)
local json = require('json')
local constants = require('constants')

-- Lazy load utils to avoid circular dependency (utils → intents → utils)
local function getUtils()
	return require('utils')
end

--- Increment the global intent counter and return the new ID
--- @return IntentId intentId The new intent ID
function intents.incrementIntentCounter()
	IntentCounter = tostring(bint(IntentCounter) + bint(1))
	return tostring(IntentCounter)
end

--- Calculate the listing fee based on duration
--- Minimum duration is 1 hour - shorter durations are charged the 1-hour rate
--- @param expirationTime BalanceAmount|number|nil The expiration timestamp (nil for no expiration)
--- @param currentTimestamp number The current timestamp in milliseconds
--- @return BalanceAmount|nil listingFee The calculated listing fee in mARIO (nil on error)
--- @return string|nil error Error message if validation fails (nil on success)
function intents.calculateListingFee(expirationTime, currentTimestamp)
	local listingFee = bint(constants.FEE.LISTING_FEE_ARIO)
	
	if not expirationTime then
		-- No expiration time, use base fee (1 day minimum)
		return tostring(listingFee), nil
	end
	
	-- Validate expiration time is a number
	local expTime = tonumber(expirationTime)
	if not expTime then
		return nil, 'Expiration time must be a valid number'
	end
	
	-- Calculate listing duration
	local listingDurationMs = bint(expTime) - bint(currentTimestamp)
	
	-- Validate duration is positive
	if listingDurationMs <= bint(0) then
		return nil, 'Expiration time must be in the future'
	end
	
	-- Validate duration doesn't exceed maximum (30 days)
	if listingDurationMs > bint(constants.LISTING.MAX_EXPIRATION_MS) then
		return nil, 'Expiration time cannot exceed 30 days'
	end
	
	-- Clamp minimum duration to 1 hour
	local minimumDurationMs = bint(constants.TIME.ONE_HOUR_MS)
	if listingDurationMs < minimumDurationMs then
		listingDurationMs = minimumDurationMs
	end
	
	-- Calculate fee based on duration
	local listingDurationHours = tonumber(tostring(listingDurationMs / bint(constants.TIME.ONE_HOUR_MS))) -- Convert ms to hours
	local hoursPerFee = constants.FEE.LISTING_FEE_MULTIPLIER_HOURS * 24 -- 24 hours per day
	
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
--- @param action string The action being performed (Create-Order, Cancel-Order, etc.)
--- @param forwardedTags table<string, any> Table of tags to forward with the intent
--- @return Intent intent The created intent
function intents.createIntent(msg, action, forwardedTags)
	local balances = require('balances')
	
	-- Calculate TTL (24 hours from creation)
	local ttl = msg.Timestamp + constants.TIME.ONE_DAY_MS
	
	-- For Create-Order actions, calculate and charge listing fee
	if action == 'Create-Order' then
		local expirationTime = forwardedTags and forwardedTags['Expiration-Time']
		
		-- Calculate listing fee
		local listingFee, feeError = intents.calculateListingFee(expirationTime, msg.Timestamp)
		assert(not feeError, feeError)
		
		-- Validate and charge fee
		assert(
			balances.walletHasSufficientBalance(msg.From, listingFee),
			'Insufficient ARIO balance for listing fee. Required: ' .. listingFee
		)
		balances.transfer(TREASURY_ADDRESS, msg.From, listingFee, true)
	end
	
	local intent = {
		intentId = intents.incrementIntentCounter(),
		initiator = msg.From,
		action = action,
		status = constants.INTENT_STATUSES.PENDING,
		createdAt = msg.Timestamp,
		ttl = ttl,
		resolvedAt = nil,
		completedAt = nil,
		failureReason = nil,
		forwardedTags = forwardedTags or {},
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
--- @param msg table|nil Optional message context for completion notices
--- @return boolean success Whether the resolution was successful
--- @return table|nil resolvedIntent The resolved intent data if pruned, nil otherwise
function intents.resolveIntent(intentId, timestamp, msg)
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
	local success, resolvedIntent = intents.resolveIntent(intentId, os.time(), msg)

	-- Send Intent-Resolved notice AFTER pruning succeeds
	if success and resolvedIntent and msg then
		local _utils = require('utils')
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
--- @param status string The new status
--- @param msg table|nil The message context (optional, for sending notices)
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
		intent.completedAt = os.time()
	end

	-- Use resolveIntent to handle pruning logic centrally for terminal states
	if status == constants.INTENT_STATUSES.COMPLETED or status == constants.INTENT_STATUSES.FAILED then
		local success, resolvedIntent = intents.resolveIntent(intentId, os.time(), msg)

		-- Send Intent-Resolved notice AFTER pruning succeeds
		if success and resolvedIntent and msg then
			getUtils().Send(msg, {
				Target = resolvedIntent.initiator,
				Action = 'Intent-Resolved',
				['Intent-Id'] = tostring(resolvedIntent.intentId),
				Status = resolvedIntent.status,
				['Intent-Action'] = resolvedIntent.action,
				['Failure-Reason'] = resolvedIntent.failureReason or '',
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

--- Create a send operation with intent tracking
--- Adds intent ID to the send if it exists in the context
--- @param sendParams table The send parameters (Target, Action, Tags, etc.)
--- @param handledMsg Message The original message context
--- @param forwardedTags table<string, any> Optional tags to forward (unused, kept for backwards compatibility)
--- @return table sendParams The send parameters with intent tracking added
function intents.createSendWithIntent(sendParams, handledMsg, forwardedTags)
	-- Extract intent from context
	local intentId = handledMsg.Tags and handledMsg.Tags['X-Intent-Id']

	if intentId then
		-- Validate intent ID format
		local _utils = require('utils')
		assert(_utils.isValidIntentId(intentId), 'Invalid X-Intent-Id format: ' .. tostring(intentId))

		-- Validate intent exists
		local intent = intents.getIntentById(intentId)
		if intent then
			-- Add intent ID to send params for tracking
			sendParams.Tags = sendParams.Tags or {}
			sendParams.Tags['X-Intent-Id'] = intentId

			-- Update intent status to "settling" if currently active
			if intent.status == constants.INTENT_STATUSES.ACTIVE then
				intents.updateIntentStatus(intentId, constants.INTENT_STATUSES.SETTLING, handledMsg)
			end
		end
	end

	return sendParams
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
function intents.createIntentHandler(msg)
	-- Extract X-Intent-* tags (Train-Case)
	local intentAction = msg.Tags['X-Intent-Action']
	assert(intentAction, 'X-Intent-Action required')

	local intentParams = {
		Action = intentAction,
		['Order-Type'] = msg.Tags['X-Intent-Order-Type'],
		['Swap-Token'] = msg.Tags['X-Intent-Swap-Token'],
		Quantity = msg.Tags['X-Intent-Quantity'],
		Price = msg.Tags['X-Intent-Price'],
		['Expiration-Time'] = msg.Tags['X-Intent-Expiration-Time'],
		['Minimum-Price'] = msg.Tags['X-Intent-Minimum-Price'],
		['Decrease-Interval'] = msg.Tags['X-Intent-Decrease-Interval'],
		['Requested-Order-Id'] = msg.Tags['X-Intent-Requested-Order-Id'],
		['Order-Id'] = msg.Tags['X-Intent-Order-Id'], -- Required for Cancel-Order and Settle-Auction
		['Dominant-Token'] = msg.Tags['X-Intent-Dominant-Token'],
	}

	-- Validate based on action type
	if intentAction == 'Create-Order' then
		-- Validate required parameters for Create-Order
		assert(intentParams['Swap-Token'], 'X-Intent-Swap-Token required for Create-Order')
		assert(intentParams.Quantity, 'X-Intent-Quantity required for Create-Order')

		-- Validate expiration time format and range
		if intentParams['Expiration-Time'] then
			local expTime = tonumber(intentParams['Expiration-Time'])
			assert(expTime, 'X-Intent-Expiration-Time must be a valid number')
			assert(expTime > msg.Timestamp, 'X-Intent-Expiration-Time must be in the future')
			
			local maxExpiration = msg.Timestamp + constants.LISTING.MAX_EXPIRATION_MS
			assert(expTime <= maxExpiration, 
				'X-Intent-Expiration-Time cannot exceed 30 days from now. Maximum allowed: ' .. tostring(maxExpiration))
		end

		-- Note: Full validation will happen in Credit-Notice handler
		-- This is just basic parameter presence check
	elseif intentAction == 'Cancel-Order' then
		assert(intentParams['Order-Id'], 'X-Intent-Order-Id required for Cancel-Order')
	elseif intentAction == 'Settle-Auction' then
		assert(intentParams['Order-Id'], 'X-Intent-Order-Id required for Settle-Auction')
	else
		error('Invalid action: ' .. tostring(intentAction))
	end

	-- Create parent intent
	local intent = intents.createIntent(msg, intentAction, intentParams)

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

	-- Get ANT process ID from intent (set during Credit-Notice)
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

-- Handler: State-Notice - Resolves intents based on ANT state
function intents.stateNoticeHandler(msg)
	local _utils = require('utils')
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

	-- Owner matches, resolve the intent
	intents.resolveIntent(intentId, msg.Timestamp, msg)

	-- Send acknowledgment to the intent initiator
	_utils.Send(msg, {
		Target = intent.initiator,
		Action = 'State-Notice-Processed',
		['Intent-Id'] = intentId,
		['ANT-Id'] = msg.From,
		['Owner'] = owner,
		['Intent-Status'] = 'resolved',
	})
end

return intents
