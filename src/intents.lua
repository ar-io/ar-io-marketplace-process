local intents = {}
local bint = require('.bint')(256)
local utils = require('utils')
local json = require('json')
local constants = require('constants')

--- Increment the global intent counter and return the new ID
--- @return string intentId The new intent ID
function intents.incrementIntentCounter()
	IntentCounter = tostring(bint(IntentCounter) + bint(1))
	return tostring(IntentCounter)
end

--- Create a parent intent
--- @param msg Message The incoming message
--- @param action string The action being performed (Create-Order, Cancel-Order, etc.)
--- @param forwardedTags table<string, any> Table of tags to forward with the intent
--- @return ParentIntent intent The created parent intent
function intents.createParentIntent(msg, action, forwardedTags)
	local intent = {
		intentId = intents.incrementIntentCounter(),
		type = constants.INTENT_TYPES.PARENT,
		initiator = msg.From,
		parentIntentId = nil,
		childIntentIds = {}, -- map for O(1) lookup
		action = action,
		status = constants.INTENT_STATUSES.PENDING,
		createdAt = msg.Timestamp,
		resolvedAt = nil,
		completedAt = nil,
		failureReason = nil,
		forwardedTags = forwardedTags or {},
	}

	Intents[intent.intentId] = intent
	return intent
end

--- Create a child intent
--- @param parentId string The parent intent ID
--- @param msg Message The incoming message
--- @param expectedFrom string The process ID we expect a Debit-Notice from
--- @param forwardedTags table<string, any> Table of tags to forward with the intent
--- @return ChildIntent childIntent The created child intent
function intents.createChildIntent(parentId, msg, expectedFrom, forwardedTags)
	-- Validate parent intent exists
	local parent = Intents[parentId]
	assert(parent, 'Parent intent not found: ' .. tostring(parentId))

	local childIntent = {
		intentId = intents.incrementIntentCounter(),
		type = constants.INTENT_TYPES.CHILD,
		initiator = ao.id, -- marketplace process
		parentIntentId = parentId,
		action = constants.ACTIONS.TRANSFER,
		expectedMessage = constants.EXPECTED_MESSAGES.DEBIT_NOTICE,
		expectedFrom = expectedFrom,
		status = constants.INTENT_STATUSES.PENDING,
		createdAt = msg.Timestamp,
		resolvedAt = nil,
		failureReason = nil,
		forwardedTags = forwardedTags or {},
	}

	-- Add to Intents table
	Intents[childIntent.intentId] = childIntent

	-- Add to parent's childIntentIds map
	Intents[parentId].childIntentIds[childIntent.intentId] = true


	return childIntent
end

--- Resolve an intent
--- Handles status transitions and pruning of parent intents in terminal states
--- @param intentId string The intent ID to resolve
--- @param timestamp number The timestamp of resolution
--- @return boolean success Whether the resolution was successful
--- @return table|nil resolvedIntent The resolved intent data if pruned, nil otherwise
function intents.resolveIntent(intentId, timestamp)
	local intent = Intents[intentId]
	if not intent then
		return false
	end

	local resolvedIntent = nil

	if intent.type == constants.INTENT_TYPES.PARENT then
		-- Parent intent resolution (pending -> active)
		if intent.status == constants.INTENT_STATUSES.PENDING then
			intent.status = constants.INTENT_STATUSES.ACTIVE
			intent.resolvedAt = timestamp
		end
		
		-- Prune parent intents (and their children) when they reach terminal states
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

			-- Delete all child intents
			for childId in pairs(intent.childIntentIds) do
				Intents[childId] = nil
			end
			-- Delete parent intent
			Intents[intentId] = nil
		end
	elseif intent.type == constants.INTENT_TYPES.CHILD then
		-- Child intent resolution
		intent.status = constants.INTENT_STATUSES.RESOLVED
		intent.resolvedAt = timestamp
	end

	return true, resolvedIntent
end

--- Fail an intent with a reason
--- @param intentId string The intent ID to fail
--- @param reason string The failure reason
--- @return boolean success Whether the failure was recorded
function intents.failIntent(intentId, reason)
	local intent = Intents[intentId]
	if not intent then
		return false
	end

	intent.status = constants.INTENT_STATUSES.FAILED
	intent.failureReason = reason

	-- Use resolveIntent to handle pruning logic centrally
	local success, resolvedIntent = intents.resolveIntent(intentId, os.time())

	-- Send Intent-Resolved notice AFTER pruning succeeds
	if success and resolvedIntent then
		ao.send({
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
--- @param intentId string The intent ID
--- @param status string The new status
--- @return boolean success Whether the update was successful
function intents.updateIntentStatus(intentId, status)
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
		local success, resolvedIntent = intents.resolveIntent(intentId, os.time())

		-- Send Intent-Resolved notice AFTER pruning succeeds
		if success and resolvedIntent then
			ao.send({
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
--- @param intentId string The intent ID
--- @return Intent|nil intent The intent or nil if not found
function intents.getIntentById(intentId)
	return Intents[intentId]
end

--- Create a send operation with intent tracking
--- Creates a child intent if a parent intent exists and updates parent status
--- @param sendParams table The send parameters (Target, Action, Tags, etc.)
--- @param handledMsg Message The original message context
--- @param forwardedTags table<string, any> Optional tags to forward with the child intent
--- @return table sendParams The send parameters with intent tracking added
function intents.createSendWithIntent(sendParams, handledMsg, forwardedTags)
	-- Extract parent intent from context
	local parentIntentId = handledMsg.Tags and handledMsg.Tags['X-Intent-Id']

	if parentIntentId then
		-- Validate intent ID format
		assert(utils.isValidIntentId(parentIntentId), 'Invalid X-Intent-Id format: ' .. tostring(parentIntentId))
		
		-- Validate parent intent exists
		local parent = intents.getIntentById(parentIntentId)
		if parent then
			-- Create child intent
			local childIntent = intents.createChildIntent(
				parentIntentId,
				handledMsg,
				sendParams.Target, -- process we expect response from
				forwardedTags or {}
			)

			-- Add child intent ID to send params
			sendParams.Tags = sendParams.Tags or {}
			sendParams.Tags['X-Intent-Id'] = childIntent.intentId

			-- Update parent status to "settling" if currently active
			if parent.status == constants.INTENT_STATUSES.ACTIVE then
				intents.updateIntentStatus(parentIntentId, constants.INTENT_STATUSES.SETTLING)
			end
		end
	end

	return sendParams
end

--- Get all pending parent intents
--- @return ParentIntent[] pending Array of pending parent intents
function intents.getPendingIntents()
	local pending = {}
	for _, intent in pairs(Intents) do
		if intent.type == constants.INTENT_TYPES.PARENT and intent.status == constants.INTENT_STATUSES.PENDING then
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
--- @param intentId string The intent ID
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

--- Check if all child intents are resolved
--- @param parentId string The parent intent ID
--- @return boolean allResolved Boolean indicating if all children are resolved
function intents.areAllChildrenIntentsResolved(parentId)
	local parent = Intents[parentId]
	if not parent or parent.type ~= constants.INTENT_TYPES.PARENT then
		return false
	end

	for childId in pairs(parent.childIntentIds) do
		local child = Intents[childId]
		if not child or child.status ~= constants.INTENT_STATUSES.RESOLVED then
			return false
		end
	end

	return true
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
		['Order-Id'] = msg.Tags['X-Intent-Order-Id'],
		['Dominant-Token'] = msg.Tags['X-Intent-Dominant-Token'],
	}

	-- Validate based on action type
	if intentAction == 'Create-Order' then
		-- Validate required parameters for Create-Order
		assert(intentParams['Swap-Token'], 'X-Intent-Swap-Token required for Create-Order')
		assert(intentParams.Quantity, 'X-Intent-Quantity required for Create-Order')

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
	local intent = intents.createParentIntent(msg, intentAction, intentParams)

	-- Return intentId to user (handler wrapper will send as notice)
	return json.encode({
		['Intent-Id'] = intent.intentId,
		Status = 'Success',
	})
end

-- Handler: Get-Paginated-Intents
function intents.getPaginatedIntentsHandler(msg)
	local page = utils.parsePaginationTags(msg)

	local intentsArray = intents.getAllIntents()

	local paginatedIntents = utils.paginateTableWithCursor(
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

-- Handler: Get-Intent-By-Id
function intents.getIntentByIdHandler(msg)
	local intentId = msg.Tags['Intent-Id']
	assert(intentId, 'Intent-Id required')

	local intent = intents.getIntentById(intentId)
	assert(intent, 'Intent not found')

	-- If parent, include all child intents
	---@type table
	local response = utils.deepCopy(intent) or intent
	if intent.type == constants.INTENT_TYPES.PARENT then
		---@diagnostic disable-next-line: inject-field
		response.children = {}
		for childId in pairs(intent.childIntentIds) do
			---@diagnostic disable-next-line: inject-field
			response.children[childId] = intents.getIntentById(childId)
		end
	end

	return json.encode(response)
end

return intents
