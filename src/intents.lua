local intents = {}
local utils = require('utils')
local json = require('json')

-- Initialize global Intents storage if it doesn't exist
if not Intents then
	Intents = {}
end

--- Create a parent intent
--- @param msg Message The incoming message
--- @param action string The action being performed (Create-Order, Cancel-Order, etc.)
--- @param forwardedTags table<string, any> Table of tags to forward with the intent
--- @return ParentIntent intent The created parent intent
function intents.createParent(msg, action, forwardedTags)
	local intent = {
		IntentId = msg.Id,
		Type = 'parent',
		Initiator = msg.From,
		ParentIntentId = nil,
		ChildIntentIds = {}, -- map for O(1) lookup
		Action = action,
		Status = 'pending',
		CreatedAt = msg.Timestamp,
		ResolvedAt = nil,
		CompletedAt = nil,
		FailureReason = nil,
		ForwardedTags = forwardedTags or {},
	}

	Intents[intent.IntentId] = intent
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
		IntentId = childId,
		Type = 'child',
		Initiator = ao.id, -- marketplace process
		ParentIntentId = parentId,
		Action = 'Transfer',
		ExpectedMessage = 'Debit-Notice',
		ExpectedFrom = expectedFrom,
		Status = 'pending',
		CreatedAt = msg.Timestamp,
		ResolvedAt = nil,
		FailureReason = nil,
		ForwardedTags = forwardedTags or {},
	}

	-- Add to Intents table
	Intents[childId] = childIntent

	-- Add to parent's ChildIntentIds map
	local parent = Intents[parentId]
	if parent then
		parent.ChildIntentIds[childId] = true
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

	if intent.Type == 'parent' then
		-- Parent intent resolution (pending -> active)
		if intent.Status == 'pending' then
			intent.Status = 'active'
			intent.ResolvedAt = timestamp
		end
	elseif intent.Type == 'child' then
		-- Child intent resolution
		intent.Status = 'resolved'
		intent.ResolvedAt = timestamp
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

	intent.Status = 'failed'
	intent.FailureReason = reason

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

	intent.Status = status

	-- Set CompletedAt timestamp if moving to completed
	if status == 'completed' then
		intent.CompletedAt = os.time()
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
		if intent.Type == 'parent' and intent.Status == 'pending' then
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
		if intent.Status == status then
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
	if not parent or parent.Type ~= 'parent' then
		return false
	end

	for childId in pairs(parent.ChildIntentIds) do
		local child = Intents[childId]
		if not child or child.Status ~= 'resolved' then
			return false
		end
	end

	return true
end

-- Handler: Create-Intent
function intents.createIntentHandler(msg)
	local json = require('json')
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

	-- Return IntentId to user (handler wrapper will send as notice)
	return json.encode({
		['Intent-Id'] = intent.IntentId,
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
		'CreatedAt',
		page.limit,
		page.sortBy,
		page.sortOrder,
		page.filters -- { Initiator = "address", Status = "pending", Type = "parent" }
	)

	return json.encode(paginatedIntents)
end

-- Handler: Get-Intent-By-Id
function intents.getIntentByIdHandler(msg)
	local json = require('json')
	local utils = require('utils')
	local intentId = msg.Tags['Intent-Id']
	assert(intentId, 'Intent-Id required')

	local intent = intents.getById(intentId)
	assert(intent, 'Intent not found')

	-- If parent, include all child intents
	---@type table
	local response = utils.deepCopy(intent) or intent
	if intent.Type == 'parent' then
		---@diagnostic disable-next-line: inject-field
		response.Children = {}
		for childId in pairs(intent.ChildIntentIds) do
			---@diagnostic disable-next-line: inject-field
			response.Children[childId] = intents.getById(childId)
		end
	end

	return json.encode(response)
end

-- Handler: Get-Intent-Stats
function intents.getIntentStatsHandler(msg)
	local json = require('json')
	local stats = {
		Total = 0,
		ByStatus = {},
		ByType = {},
		ByAction = {},
	}

	for _, intent in pairs(Intents) do
		stats.Total = stats.Total + 1
		stats.ByStatus[intent.Status] = (stats.ByStatus[intent.Status] or 0) + 1
		stats.ByType[intent.Type] = (stats.ByType[intent.Type] or 0) + 1
		stats.ByAction[intent.Action] = (stats.ByAction[intent.Action] or 0) + 1
	end

	return json.encode(stats)
end

return intents
