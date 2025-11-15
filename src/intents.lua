local intents = {}
local utils = require('utils')
local json = require('json')
local constants = require('constants')

--- Create a parent intent
--- @param msg Message The incoming message
--- @param action string The action being performed (Create-Order, Cancel-Order, etc.)
--- @param forwardedTags table<string, any> Table of tags to forward with the intent
--- @return ParentIntent intent The created parent intent
function intents.createParent(msg, action, forwardedTags)
	local intent = {
		intentId = msg.Id,
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
function intents.createChild(parentId, msg, expectedFrom, forwardedTags)
	local childId = msg.Id .. '-child-' .. tostring(os.time()) .. '-' .. tostring(math.random(1000, 9999))

	local childIntent = {
		intentId = childId,
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
	Intents[childId] = childIntent

	-- Add to parent's childIntentIds map
	local parent = Intents[parentId]
	if parent then
		parent.childIntentIds[childId] = true
	end

	return childIntent
end

--- Resolve an intent
--- @param intentId string The intent ID to resolve
--- @param timestamp number The timestamp of resolution
--- @return boolean success Whether the resolution was successful
function intents.resolve(intentId, timestamp)
	local intent = Intents[intentId]
	if not intent then
		return false
	end

	if intent.type == constants.INTENT_TYPES.PARENT then
		-- Parent intent resolution (pending -> active)
		if intent.status == constants.INTENT_STATUSES.PENDING then
			intent.status = constants.INTENT_STATUSES.ACTIVE
			intent.resolvedAt = timestamp
		end
	elseif intent.type == constants.INTENT_TYPES.CHILD then
		-- Child intent resolution
		intent.status = constants.INTENT_STATUSES.RESOLVED
		intent.resolvedAt = timestamp
	end

	return true
end

--- Fail an intent with a reason
--- @param intentId string The intent ID to fail
--- @param reason string The failure reason
--- @return boolean success Whether the failure was recorded
function intents.fail(intentId, reason)
	local intent = Intents[intentId]
	if not intent then
		return false
	end

	intent.status = constants.INTENT_STATUSES.FAILED
	intent.failureReason = reason

	return true
end

--- Update intent status
--- @param intentId string The intent ID
--- @param status string The new status
--- @return boolean success Whether the update was successful
function intents.updateStatus(intentId, status)
	local intent = Intents[intentId]
	if not intent then
		return false
	end

	intent.status = status

	-- Set completedAt timestamp if moving to completed
	if status == constants.INTENT_STATUSES.COMPLETED then
		intent.completedAt = os.time()
	end

	return true
end

--- Get intent by ID
--- @param intentId string The intent ID
--- @return Intent|nil intent The intent or nil if not found
function intents.getById(intentId)
	return Intents[intentId]
end

--- Get all pending parent intents
--- @return ParentIntent[] pending Array of pending parent intents
function intents.getPending()
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
function intents.getByStatus(status)
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
function intents.validateExists(intentId)
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
function intents.areAllChildrenResolved(parentId)
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
	local intent = intents.createParent(msg, intentAction, intentParams)

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

	local intent = intents.getById(intentId)
	assert(intent, 'Intent not found')

	-- If parent, include all child intents
	---@type table
	local response = utils.deepCopy(intent) or intent
	if intent.type == constants.INTENT_TYPES.PARENT then
		---@diagnostic disable-next-line: inject-field
		response.Children = {}
		for childId in pairs(intent.childIntentIds) do
			---@diagnostic disable-next-line: inject-field
			response.Children[childId] = intents.getById(childId)
		end
	end

	return json.encode(response)
end

return intents
