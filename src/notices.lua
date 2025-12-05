local notices = {}
local constants = require('constants')

-- Handler: Credit-Notice - Validates and creates orders
function notices.creditNoticeHandler(msg)
	local _utils = require('utils')
	local intents = require('intents')
	local ucm = require('ucm')
	local balances = require('balances')

	-- NOTE: this could be expanded in the future for more tokens
	if msg.Tags['X-Action'] == constants.ACTIONS.DEPOSIT then
		local isArioNotice = _utils.isArioToken(msg.From)
		assert(isArioNotice, "Deposit must be from ARIO")
		balances.handleDeposit(msg)
		return
	end

	local sender = msg.Tags.Sender
	local quantity = msg.Tags.Quantity
	assert(sender, "Sender is required")
	assert(quantity, "Quantity is required")

	-- Helper function to handle invalid transfers
	-- Only accept ARIO as fees, refund anything else (like ANT tokens)
	local function handleInvalidTransfer(errorMessage)
		if _utils.isArioToken(msg.From) then
			-- Accept ARIO tokens as fees
			if quantity and _utils.checkValidAmount(quantity) then
				_utils.accrueFee(quantity)
			end
		else
			-- Refund non-ARIO tokens (like ANT)
			_utils.refundAndNotifyError(msg, sender, errorMessage)
		end
	end

	-- BLOCK ARIO Credit-Notices with X-Order-Action (ARIO orders must use internal balance)
	if msg.Tags['X-Order-Action'] == 'Create-Order' and _utils.isArioToken(msg.From) then
		handleInvalidTransfer('ARIO orders must use internal balance - deposit ARIO first, then call Create-Order')
		return
	end

	-- REQUIRE X-Intent-Id for ANT orders
	if not msg.Tags['X-Intent-Id'] then
		handleInvalidTransfer('X-Intent-Id required - create intent first')
		return
	end

	-- Validate intent ID format
	if not _utils.isValidIntentId(msg.Tags['X-Intent-Id']) then
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

	-- Validate ANT process ID matches the intent (ANT ID was set during Create-Intent)
	if not _utils.isArioToken(msg.From) then
		if msg.From ~= intent.antProcessId then
			-- Fail the intent and refund the ANT
			intents.failIntent(msg.Tags['X-Intent-Id'], 'ANT process ID does not match intent. Expected: ' .. tostring(intent.antProcessId), msg)
			handleInvalidTransfer('ANT process ID does not match intent. Expected: ' .. tostring(intent.antProcessId))
			return
		end
	end

	-- Resolve intent (pending → active)
	intents.resolveIntent(msg.Tags['X-Intent-Id'], msg.Timestamp)

	-- Whitelist check for ANT order creation
	if not _utils.isArioToken(msg.From) and msg.Tags['X-Order-Action'] == 'Create-Order' then
		if not _utils.isWhitelisted(msg) then
			intents.failIntent(msg.Tags['X-Intent-Id'], 'ANT module not whitelisted', msg)
			return
		end
	end

	-- Check if sender is a valid address
	if not _utils.checkValidAddress(sender) then
		handleInvalidTransfer('Sender must be a valid address')
		return
	end

	-- Check if quantity is a valid integer greater than zero
	if not _utils.checkValidAmount(quantity) then
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
		-- Get order parameters from the intent (stored during Create-Intent)
		local orderParams = intent.orderParams or {}

		-- Swap token is always ARIO for intent-based ANT sell orders
		local swapToken = ARIO_TOKEN_PROCESS_ID

		-- Validate that at least one token in the trade is ARIO
		local isArioValid, arioError = _utils.validateArioInTrade(msg.From, swapToken)
		if not isArioValid then
			_utils.refundAndNotifyError(msg, sender, arioError or 'At least one token in the trade must be ARIO')
			return
		end

		-- Build order arguments from intent parameters and ANT transfer context
		local orderArgs = {
			orderId = msg.Id,
			dominantToken = intent.antProcessId, -- ANT process ID from intent (set during Create-Intent)
			swapToken = swapToken, -- Always ARIO for ANT sell orders
			sender = sender,
			quantity = quantity, -- From ANT transfer
			createdAt = msg.Timestamp,
			blockheight = msg['Block-Height'],
			orderType = orderParams.orderType or 'fixed',
			expirationTime = orderParams.expirationTime and tonumber(orderParams.expirationTime),
			minimumPrice = orderParams.minimumPrice,
			decreaseInterval = orderParams.decreaseInterval,
			price = orderParams.price,
			msg = msg, -- Pass msg context for intent tracking
		}

		if orderParams.price then
			orderArgs.price = orderParams.price
		end
		if msg.Tags['X-Transfer-Denomination'] then
			orderArgs.transferDenomination = msg.Tags['X-Transfer-Denomination']
		end

		-- Protect order creation to catch unexpected runtime errors
		-- Note: refundAndNotifyError calls within createOrder will throw errors that are caught here
		local ok = pcall(function()
			ucm.createOrder(orderArgs)
		end)
		if not ok then
			-- Error occurred - it was already handled by refundAndNotifyError which sends error notice
			-- Just return without double-handling
			return
		end

		-- Order created successfully - complete the intent
		local updatedIntent = intents.getIntentById(msg.Tags['X-Intent-Id'])
		local intentStatus = updatedIntent and updatedIntent.status or 'not-found'

		if updatedIntent then
			intents.updateIntentStatus(msg.Tags['X-Intent-Id'], 'completed', msg)
			intentStatus = 'completed'
		end

		-- Send acknowledgment with intent and order status
		_utils.Send(msg, {
			Target = sender,
			Action = 'Credit-Notice-Processed',
			['Order-Id'] = msg.Id,
			['Intent-Id'] = msg.Tags['X-Intent-Id'],
			['Intent-Status'] = intentStatus,
			['Order-Status'] = 'listed',
		})
	end
end

return notices
