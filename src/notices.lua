local notices = {}
local constants = require('constants')

-- Handler: Credit-Notice - Validates and creates orders
function notices.creditNoticeHandler(msg)
	local utils = require('utils')
	local intents = require('intents')
	local ucm = require('ucm')
	local balances = require('balances')

	if msg.Tags['X-Action'] == constants.ACTIONS.DEPOSIT then
		local isArioNotice = utils.isArioToken(msg.From)
		assert(isArioNotice, "Deposit must be from ARIO")
		balances.handleDeposit(msg)
		return
	end

	if not msg.Tags['X-Dominant-Token'] or msg.From ~= msg.Tags['X-Dominant-Token'] then
		return
	end

	local sender = msg.Tags.Sender
	local quantity = msg.Tags.Quantity

	-- Helper function to handle invalid transfers
	-- Only accept ARIO as fees, refund anything else (like ANT tokens)
	local function handleInvalidTransfer(errorMessage)
		if utils.isArioToken(msg.From) then
			-- Accept ARIO tokens as fees
			if quantity and utils.checkValidAmount(quantity) then
				utils.accrueFee(quantity)
			end
		else
			-- Refund non-ARIO tokens (like ANT)
			utils.refundAndError(msg, sender, errorMessage)
		end
	end

	-- BLOCK ARIO Credit-Notices with X-Order-Action (ARIO orders must use internal balance)
	if msg.Tags['X-Order-Action'] == 'Create-Order' and utils.isArioToken(msg.From) then
		handleInvalidTransfer('ARIO orders must use internal balance - deposit ARIO first, then call Create-Order')
		return
	end

	-- REQUIRE X-Intent-Id for ANT orders
	if not msg.Tags['X-Intent-Id'] then
		handleInvalidTransfer('X-Intent-Id required - create intent first')
		return
	end

	-- Validate intent ID format
	if not utils.isValidIntentId(msg.Tags['X-Intent-Id']) then
		handleInvalidTransfer('Invalid X-Intent-Id format')
		return
	end

	-- Validate intent exists
	---@type Intent|nil
	local intent = intents.getIntentById(msg.Tags['X-Intent-Id'])
	if not intent then
		handleInvalidTransfer('Intent already resolved or does not exist')
		return
	end

	-- Validate sender matches intent initiator
	if sender ~= intent.initiator then
		handleInvalidTransfer('Sender does not match intent initiator')
		return
	end
	
	-- Validate intent hasn't expired (parent intents have TTL)
	if intent.ttl and msg.Timestamp >= intent.ttl then
		handleInvalidTransfer('Intent has expired')
		return
	end

	-- Resolve parent intent (pending → active)
	intents.resolveIntent(msg.Tags['X-Intent-Id'], msg.Timestamp, msg)

	-- Check if sender is a valid address
	if not utils.checkValidAddress(sender) then
		handleInvalidTransfer('Sender must be a valid address')
		return
	end

	-- Check if quantity is a valid integer greater than zero
	if not utils.checkValidAmount(quantity) then
		handleInvalidTransfer('Quantity must be an integer greater than zero')
		return
	end

	-- Check if all required fields are present
	if not sender or not quantity then
		handleInvalidTransfer('Invalid arguments, required { Sender, Quantity }')
		return
	end

	-- If Order-Action then create the order
	if msg.Tags['X-Order-Action'] == 'Create-Order' then
		-- Validate that at least one token in the trade is ARIO
		local isArioValid, arioError = utils.validateArioInTrade(msg.From, msg.Tags['X-Swap-Token'])
		if not isArioValid then
			utils.refundAndError(msg, sender, arioError or 'At least one token in the trade must be ARIO')
			return
		end

		local orderArgs = {
			orderId = msg.Id,
			orderGroupId = msg.Tags['X-Group-ID'] or 'None',
			dominantToken = msg.From,
			swapToken = msg.Tags['X-Swap-Token'],
			sender = sender,
			quantity = quantity,
			createdAt = msg.Timestamp,
			blockheight = msg['Block-Height'],
			orderType = msg.Tags['X-Order-Type'] or 'fixed',
			expirationTime = msg.Tags['X-Expiration-Time'] and tonumber(msg.Tags['X-Expiration-Time']),
			minimumPrice = msg.Tags['X-Minimum-Price'],
			decreaseInterval = msg.Tags['X-Decrease-Interval'],
			requestedOrderId = msg.Tags['X-Requested-Order-Id'],
			msg = msg, -- Pass msg context for intent tracking
		}

		if msg.Tags['X-Price'] then
			orderArgs.price = msg.Tags['X-Price']
		end
		if msg.Tags['X-Transfer-Denomination'] then
			orderArgs.transferDenomination = msg.Tags['X-Transfer-Denomination']
		end

		-- Protect order creation to catch unexpected runtime errors
		-- Note: refundAndError calls within createOrder will throw errors that are caught here
		local ok, err = pcall(function()
			ucm.createOrder(orderArgs)
		end)
		if not ok then
			-- Only refund if error wasn't already handled by refundAndError
			-- (refundAndError throws errors containing the error message)
			-- If it's a different type of error, refund it
			if not string.find(tostring(err), 'required') and not string.find(tostring(err), 'must be') then
				utils.refundAndError(msg, sender, 'Order creation failed: ' .. tostring(err), 'Order-Error')
			end
			return
		end

		-- Order created successfully - complete the intent if no child intents
		local intent = intents.getIntentById(msg.Tags['X-Intent-Id'])
		local intentStatus = intent and intent.status or 'not-found'
		
		if intent and intent.type == 'parent' then
			-- Count pending child intents
			local hasPendingChildren = false
			for childId in pairs(intent.childIntentIds) do
				local child = intents.getIntentById(childId)
				if child and child.status == 'pending' then
					hasPendingChildren = true
					break
				end
			end

		-- If no pending children, complete the intent immediately
		if not hasPendingChildren then
			intents.updateIntentStatus(msg.Tags['X-Intent-Id'], 'completed', msg)
			intentStatus = 'completed'
			else
				intentStatus = 'active'
			end
		end

		-- Send acknowledgment with intent and order status
		utils.Send(msg, {
			Target = sender,
			Action = 'Credit-Notice-Processed',
			['Order-Id'] = msg.Id,
			['Intent-Id'] = msg.Tags['X-Intent-Id'],
			['Intent-Status'] = intentStatus,
			['Order-Status'] = 'listed',
		})
	end
end

-- Handler: Debit-Notice - Resolves child intents when transfers complete
function notices.debitNoticeHandler(msg)
	local utils = require('utils')
	local intents = require('intents')

	local intentId = msg.Tags['X-Intent-Id']
	if not intentId then
		return
	end

	-- Validate intent ID format
	if not utils.isValidIntentId(intentId) then
		return
	end

	local intent = intents.getIntentById(intentId)
	if not intent then
		return
	end

	-- Validate this is expected Debit-Notice
	if intent.type == constants.INTENT_TYPES.CHILD and intent.expectedFrom == msg.From then
		-- Resolve child intent (will auto-complete parent if all children resolved)
		intents.resolveIntent(intentId, msg.Timestamp, msg)

		-- Get parent status for acknowledgment
		local parent = intents.getIntentById(intent.parentIntentId)
		local parentStatus = parent and parent.status or 'not-found'

		-- Send acknowledgment with intent status
		utils.Send(msg, {
			Target = intent.initiator,
			Action = 'Debit-Notice-Processed',
			['Intent-Id'] = intentId,
			['Parent-Intent-Id'] = intent.parentIntentId,
			['Parent-Intent-Status'] = parentStatus,
			['Child-Intent-Status'] = 'resolved',
		})
	end
end

-- Handler: Transfer-Error - Handles transfer failures
-- Transfer-Error is the token spec aligned error notice sent when a transfer fails
function notices.transferErrorHandler(msg)
	local utils = require('utils')
	local intents = require('intents')

	local intentId = msg.Tags['X-Intent-Id']
	if not intentId then
		return
	end

	-- Validate intent ID format
	if not utils.isValidIntentId(intentId) then
		return
	end

	local intent = intents.getIntentById(intentId)
	if not intent or intent.type ~= constants.INTENT_TYPES.CHILD then
		return
	end

	-- Extract failure reason
	local reason = msg.Tags.Message or msg.Tags.Error or msg.Data or 'Transfer failed'

	-- Fail child intent with reason
	intents.failIntent(intentId, reason, msg)

	-- Cascade failure to parent
	if intent.parentIntentId then
		local parent = intents.getIntentById(intent.parentIntentId)
		if parent then
			intents.failIntent(intent.parentIntentId, 'Child transfer failed: ' .. reason, msg)
		end
	end
end

return notices
