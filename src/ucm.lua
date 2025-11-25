local bint = require('.bint')(256)

require('types')
local utils = require('utils')
local constants = require('constants')
local json = require('json')
local fixed_price = require('fixed_price')
local dutch_auction = require('dutch_auction')
local english_auction = require('english_auction')

local ucm = {}

--- Find order by ID using OrderIndex (O(1) lookup)
--- @param orderId string The order ID to find
--- @return table|nil order The order object or nil
--- @return table|nil pair The pair containing the order or nil
function ucm.getOrderById(orderId)
	local location = OrderIndex[orderId]
	if not location then
		return nil, nil
	end

	local pair = Orderbook[location.dominantToken] and Orderbook[location.dominantToken][location.swapToken]
	if not pair then
		-- Index is stale, clean it up
		OrderIndex[orderId] = nil
		return nil, nil
	end

	local order = pair.orders[orderId]
	if not order then
		-- Index is stale, clean it up
		OrderIndex[orderId] = nil
		return nil, nil
	end

	return order, pair
end

--- Schedule the next orderbook pruning if the given timestamp is sooner than the current scheduled time
--- @param timestamp number The timestamp to schedule pruning for
function ucm.scheduleNextOrderbookPruning(timestamp)
	if not timestamp then
		return
	end

	-- Initialize if needed
	if not Pruning then
		Pruning = { nextScheduledOrderbookPruning = nil }
	end

	-- Schedule if no prune scheduled or if this one is sooner
	if not Pruning.nextScheduledOrderbookPruning or timestamp < Pruning.nextScheduledOrderbookPruning then
		Pruning.nextScheduledOrderbookPruning = timestamp
	end
end

--- Prune expired orders from the orderbook and auto-settle expired English auctions
--- Returns early if it's not time to prune yet
--- @param now number The current timestamp
--- @param msg table The message context for settlements
function ucm.pruneOrderbook(now, msg)
	-- Return early if no pruning is scheduled or not time yet
	if not Pruning or not Pruning.nextScheduledOrderbookPruning or now < Pruning.nextScheduledOrderbookPruning then
		return
	end

	-- Track the next earliest expiration for rescheduling
	local nextExpiration = nil

	-- Iterate through all orders and update expired ones
	for dominantToken, swapTokens in pairs(Orderbook) do
		for swapToken, pair in pairs(swapTokens) do
			for _, order in pairs(pair.orders) do
				-- Only process active orders with expiration times
				if order.status == constants.ORDER_STATUSES.ACTIVE and order.expirationTime then
					local expirationTime = order.expirationTime

					if now >= expirationTime then
						-- Order has expired, route to appropriate module handler
						if order.orderType == constants.ORDER_TYPES.ENGLISH then
							english_auction.pruneExpiredAuction(order, pair, dominantToken, swapToken, now, msg)
						elseif order.orderType == constants.ORDER_TYPES.DUTCH then
							dutch_auction.pruneExpiredAuction(order)
						else
							-- Fixed price or other order types
							fixed_price.pruneExpiredOrder(order)
						end
					else
						-- Track the next expiration
						if not nextExpiration or expirationTime < nextExpiration then
							nextExpiration = expirationTime
						end
					end
				end
			end
		end
	end

	-- Schedule the next prune
	Pruning.nextScheduledOrderbookPruning = nextExpiration
end

--- Transfer wrapper that handles intent tracking for ANT and non-ARIO token transfers
--- Creates child intents for tracking transfer completion
--- NOTE: This function creates child intents. Use ONLY for ANT and other non-ARIO tokens.
--- For ARIO withdrawals, use ucm.transfer() (without intent tracking).
--- @param recipient string The recipient address
--- @param quantity string The amount to transfer
--- @param token string The token process ID
--- @param handledMsg Message The original message context
function ucm.transferWithIntent(recipient, quantity, token, handledMsg)
	local intents = require('intents')

	-- Construct send parameters for transfer
	local sendParams = {
		Target = token,
		Action = 'Transfer',
		Tags = {
			Recipient = recipient,
			Quantity = quantity,
		},
	}
	-- Add intent tracking
	sendParams = intents.createSendWithIntent(sendParams, handledMsg, {
		Recipient = recipient,
		Quantity = quantity,
		Token = token,
	})

	-- Use utils.Send to actually send the message
	utils.Send(handledMsg, sendParams)
end

--- Direct transfer without intent tracking (for ARIO withdrawals)
--- @param recipient string The recipient address
--- @param quantity string The amount to transfer
--- @param token string The token process ID
--- @param handledMsg Message The original message context
function ucm.transfer(recipient, quantity, token, handledMsg)
	utils.Send(handledMsg, {
		Target = token,
		Action = 'Transfer',
		Tags = {
			Recipient = recipient,
			Quantity = quantity,
		},
	})
end

--- Execute token transfers for order matching
--- Handles both internal ARIO balance and external ANT transfers
--- NOTE: ARIO Credit-Notices for orders are blocked - ARIO here means internal balance only
--- @param args ExecuteTokenTransfersArgs Token transfer arguments
function ucm.executeTokenTransfers(args)
	local balances = require('balances')
	local msg = args.msg or { Tags = {} }

	-- Transfer dominant token (what buyer is sending) to the seller (order creator)
	if utils.isArioToken(args.dominantToken) then
		-- ARIO: Internal balance transfer
		-- Deduct FULL amount from buyer (including fee), add calculated amount to seller
		local fullAmount = args.originalSendAmount or args.calculatedSendAmount
		balances.reduceBalance(args.sender, tostring(fullAmount))
		balances.increaseBalance(args.currentOrderEntry.creator, tostring(args.calculatedSendAmount))
	else
		-- ANT: External transfer via Credit-Notice with intent tracking
		-- (ANT came via Credit-Notice, now goes to seller)
		ucm.transferWithIntent(args.currentOrderEntry.creator, tostring(args.calculatedSendAmount), args.dominantToken, msg)
	end

	-- Transfer swap token (what buyer is receiving) from seller to buyer
	if utils.isArioToken(args.swapToken) then
		-- ARIO: seller's internal balance → buyer's internal balance
		balances.transfer(args.sender, args.currentOrderEntry.creator, tostring(args.calculatedFillAmount), true)
	else
		-- ANT: External transfer via Credit-Notice with intent tracking
		-- (ANT from seller's Credit-Notice, now goes to buyer)
		ucm.transferWithIntent(args.sender, tostring(args.calculatedFillAmount), args.swapToken, msg)
	end
end

--- Get a trading pair from the orderbook (directional)
--- @param dominantToken string The dominant token ID
--- @param swapToken string The swap token ID
--- @return Pair|nil The pair object or nil if not found
function ucm.getPair(dominantToken, swapToken)
	if Orderbook[dominantToken] and Orderbook[dominantToken][swapToken] then
		return Orderbook[dominantToken][swapToken]
	end
	return nil
end

--- Validate ANT dominant token orders (selling ANT for ARIO)
--- Throws error if validation fails
--- @param args table Order arguments containing quantity, price, expirationTime, createdAt, sender, orderGroupId
--- @param _validPair string[] The validated pair [ANT, ARIO]
function ucm.validateAntDominantOrder(args, _validPair)
	-- ANT tokens can only be sold in quantities of exactly 1
	if bint(args.quantity) ~= bint(constants.AUCTION.ANT_EXACT_QUANTITY) then
		utils.refundAndError(
			args.msg,
			args.sender,
			'ANT tokens can only be sold in quantities of exactly ' .. constants.AUCTION.ANT_EXACT_QUANTITY
		)
		return
	end

	-- Price is required when selling ANT
	if not args.price then
		utils.refundAndError(args.msg, args.sender, 'Price is required when selling ANT tokens')
		return
	end

	-- Validate expiration time is valid
	local isValidExpiration, expirationError = utils.checkValidExpirationTime(args.expirationTime, args.createdAt)
	if not isValidExpiration then
		utils.refundAndError(args.msg, args.sender, expirationError)
		return
	end

	-- Validate price is valid
	local isValidPrice, priceError = utils.checkValidAmount(args.price)
	if not isValidPrice then
		utils.refundAndError(args.msg, args.sender, priceError or 'Unknown price error')
		return
	end
	return true
end

--- Validate ARIO dominant token orders (buying ANT with ARIO)
--- Throws error if validation fails
--- @param args table Order arguments containing requestedOrderId, sender, quantity, orderGroupId
--- @param _validPair string[] The validated pair [ARIO, ANT]
function ucm.validateArioDominantOrder(args, _validPair)
	-- Currently no specific validation rules for ARIO dominant orders
	-- All general validations (quantity, pair, etc.) are handled in validateOrderParams
	-- This function is a placeholder for future ARIO-specific validation rules
	if not args.requestedOrderId then
		utils.refundAndError(args.msg, args.sender, 'Requested order ID is required')
		return
	end
	return true
end

--- Validate order parameters
--- @param args table Order arguments containing dominantToken, swapToken, quantity, orderType, sender, orderGroupId
--- @return string[]|nil validPair The validated pair [dominantToken, swapToken] or nil if validation fails
function ucm.validateOrderParams(args)
	-- 1. Check pair data
	local validPair, pairError = utils.validatePairData({ args.dominantToken, args.swapToken })
	if not validPair then
		utils.refundAndError(args.msg, args.sender, pairError or 'Error validating pair', 'Order-Error')
		return
	end

	-- 2. Validate ARIO is in trade (marketplace requirement)
	local isArioValid, arioError = utils.validateArioInTrade(args.dominantToken, args.swapToken)
	if not isArioValid then
		utils.refundAndError(args.msg, args.sender, arioError or 'Invalid trade - ARIO must be involved', 'Order-Error')
		return
	end

	-- 3. Check quantity is positive integer
	if not utils.checkValidAmount(args.quantity) then
		utils.refundAndError(args.msg, args.sender, 'Quantity must be an integer greater than zero')
		return
	end

	-- 4. Check order type is supported
	if
		not args.orderType
		or (args.orderType ~= 'fixed' and args.orderType ~= 'dutch' and args.orderType ~= 'english')
	then
		utils.refundAndError(args.msg, args.sender, 'Order type must be "fixed" or "dutch" or "english"')
		return
	end

	-- 5. Check if it's ANT dominant (selling ANT) or ARIO dominant (buying ANT)
	local isAntDominant = not utils.isArioToken(args.dominantToken)

	if isAntDominant then
		-- ANT dominant: validate ANT-specific requirements
		ucm.validateAntDominantOrder(args, validPair)

		-- Dutch auction specific validation
		if args.orderType == constants.ORDER_TYPES.DUTCH then
			local isValidDutch, dutchError = dutch_auction.validateDutchParams(args)
			if not isValidDutch then
				utils.refundAndError(args.msg, args.sender, dutchError)
				return
			end
		end
	else
		-- ARIO dominant: validate ARIO-specific requirements
		ucm.validateArioDominantOrder(args, validPair)
	end

	return validPair
end

--- Ensure a trading pair exists in the orderbook, creating it if necessary
--- @param validPair string[] The pair as [dominantToken, swapToken]
--- @return Pair The pair object
function ucm.ensurePairExists(validPair)
	local dominantToken, swapToken = validPair[1], validPair[2]

	-- Create dominantToken level if it doesn't exist
	if not Orderbook[dominantToken] then
		Orderbook[dominantToken] = {}
	end

	-- Create pair if it doesn't exist
	if not Orderbook[dominantToken][swapToken] then
		Orderbook[dominantToken][swapToken] = {
			pair = validPair,
			orders = {},
		}
	end

	return Orderbook[dominantToken][swapToken]
end

--- Handle ANT-dominant orders (selling ANT for ARIO) for different auction types
--- @param args table Order arguments
--- @param validPair string[] The validated pair [ANT, ARIO]
--- @param pair Pair The pair object from orderbook
function ucm.handleAntOrderAuctions(args, validPair, pair)
	if args.orderType == constants.ORDER_TYPES.FIXED then
		fixed_price.handleAntOrder(args, validPair, pair)
	elseif args.orderType == constants.ORDER_TYPES.DUTCH then
		local dutch_auction_module = require('dutch_auction')
		dutch_auction_module.handleAntOrder(args, validPair, pair)
	elseif args.orderType == constants.ORDER_TYPES.ENGLISH then
		args.pair = pair
		english_auction.handleAntOrder(args)
	else
		utils.refundAndError(args.msg, args.sender, 'Order type not implemented yet', 'Order-Error')
		return
	end
end

--- Handle ARIO-dominant orders (buying ANT with ARIO) for different auction types
--- @param args table Order arguments
--- @param validPair string[] The validated pair [ARIO, ANT]
--- @param pair Pair The pair object from orderbook
function ucm.handleArioOrderAuctions(args, validPair, pair)
	-- Check if the desired token is already being sold (prevent duplicate sell orders)
	local currentOrders = pair.orders
	for _, existingOrder in pairs(currentOrders) do
		if existingOrder.token == args.dominantToken then
			utils.refundAndError(
				args.msg,
				args.sender,
				'This ANT token is already being sold - cannot create duplicate sell order'
			)
			return
		end
	end

	if args.orderType == constants.ORDER_TYPES.FIXED then
		fixed_price.handleArioOrder(args, validPair, pair)
	elseif args.orderType == constants.ORDER_TYPES.DUTCH then
		dutch_auction.handleArioOrder(args, validPair, pair)
	elseif args.orderType == constants.ORDER_TYPES.ENGLISH then
		english_auction.handleArioOrder(args, validPair, pair)
	else
		utils.refundAndError(args.msg, args.sender, 'Order type not implemented yet', 'Order-Error')
		return
	end
end

--- Create a new order in the orderbook
--- @param args table Order arguments containing all necessary fields for order creation
function ucm.createOrder(args)
	-- Validate order parameters
	local validPair = ucm.validateOrderParams(args)
	if not validPair then
		return
	end

	-- Ensure trading pair exists in orderbook
	local pair = ucm.ensurePairExists(validPair)

	-- Check if the desired token is ARIO (add to orderbook) or ANT (immediate trade only)
	local isBuyingAnt = utils.isArioToken(args.dominantToken) -- If dominantToken is ARIO, we're buying ANT
	local isBuyingArio = not isBuyingAnt -- If dominantToken is not ARIO, we're selling ANT

	-- Handle ANT token orders - check for immediate trades only, don't add to orderbook
	if isBuyingAnt then
		-- When buying ANT, we need to look for ANT sell orders in the ANT->ARIO pair (opposite direction)
		local oppositePair = { validPair[2], validPair[1] } -- [ANT, ARIO]
		local oppositePairObj = ucm.ensurePairExists(oppositePair)
		ucm.handleAntOrderAuctions(args, oppositePair, oppositePairObj)
		return
	end

	-- Handle ARIO token orders - add to orderbook for buy now
	if isBuyingArio then
		ucm.handleArioOrderAuctions(args, validPair, pair)
		return
	end

	-- Placeholder for future order type handling
	utils.refundAndError(args.msg, args.sender, 'Order type not implemented yet', 'Order-Error')
	return
end

--- Handler: Create-Order (for ARIO orders via direct message using internal balance)
--- ANT orders must come via Credit-Notice
--- @param msg Message The message containing order parameters
--- @return string jsonResponse JSON-encoded response with status and order ID
function ucm.createOrderHandler(msg)
	local json = require('json')
	
	-- Parse order parameters
	local swapToken = msg.Tags['Swap-Token']
	local quantity = msg.Tags.Quantity
	local orderType = msg.Tags['Order-Type'] or 'fixed'
	local price = msg.Tags.Price
	local expirationTime = msg.Tags['Expiration-Time'] and tonumber(msg.Tags['Expiration-Time'])
	
	assert(swapToken, 'Swap-Token is required')
	assert(quantity, 'Quantity is required')
	assert(utils.checkValidAmount(quantity), 'Quantity must be a positive integer')
	
	-- Validate that sender has ARIO token process ID as dominantToken
	-- For ARIO orders, we're offering ARIO from internal balance to get the swap token
	local dominantToken = ARIO_TOKEN_PROCESS_ID
	
	-- Validate that at least one token is ARIO
	local isArioValid, arioError = utils.validateArioInTrade(dominantToken, swapToken)
	assert(isArioValid, arioError or 'At least one token in the trade must be ARIO')
	
	local orderArgs = {
		orderId = msg.Id,
		orderGroupId = msg.Tags['Group-ID'] or 'None',
		dominantToken = dominantToken,
		swapToken = swapToken,
		sender = msg.From,
		quantity = quantity,
		createdAt = msg.Timestamp,
		blockheight = msg['Block-Height'],
		orderType = orderType,
		expirationTime = expirationTime,
		minimumPrice = msg.Tags['Minimum-Price'],
		decreaseInterval = msg.Tags['Decrease-Interval'],
		requestedOrderId = msg.Tags['Requested-Order-Id'],
		msg = msg,
	}
	
	if price then
		orderArgs.price = price
	end
	if msg.Tags['Transfer-Denomination'] then
		orderArgs.transferDenomination = msg.Tags['Transfer-Denomination']
	end
	
	-- Create the order (will use internal balance via handleArioOrder)
	ucm.createOrder(orderArgs)
	
	return json.encode({
		Status = 'Success',
		Message = 'ARIO order created using internal balance',
		['Order-Id'] = msg.Id,
		['Group-ID'] = orderArgs.orderGroupId,
	})
end

--- Settle an expired English auction
--- @param args table Settlement arguments containing orderId, sender, timestamp, orderGroupId, dominantToken, swapToken, msg
function ucm.settleAuction(args)
	-- Find the auction order using O(1) lookup
	local targetOrder, targetPair = ucm.getOrderById(args.orderId)
	assert(targetOrder, 'Auction order not found')

	-- Validate it's an English auction
	assert(targetOrder.orderType == constants.ORDER_TYPES.ENGLISH, 'Order is not an English auction')

	-- Check if auction has bids
	assert(targetOrder.highestBidder, 'No bids found for auction')

	-- Check if auction has expired
	assert(utils.isExpired(targetOrder.expirationTime, args.timestamp), 'Auction has not expired yet')

	-- Call the core settlement function with pre-fetched data
	english_auction.settleAuction({
		order = targetOrder,
		pair = targetPair,
		dominantToken = args.dominantToken,
		swapToken = args.swapToken,
		timestamp = args.timestamp,
		msg = args.msg,
		sender = args.sender,
		orderGroupId = args.orderGroupId,
	})
end

--- Cancel an order
--- Accepts the original msg so we can keep consistent behavior and responses
--- @param msg Message The message containing Order-Id and X-Group-ID tags
--- @return string jsonResponse JSON-encoded response with status and order ID
function ucm.cancelOrderHandler(msg)
	-- Parse parameters from tags (Train-Case)
	local orderId = msg.Tags['Order-Id']
	local groupId = msg.Tags['X-Group-ID'] or 'None'

	assert(orderId, 'Invalid arguments, required { Order-Id }')

	-- Find order using O(1) lookup
	local currentOrderEntry, pairData = ucm.getOrderById(orderId)
	assert(currentOrderEntry, 'Order not found')

	-- Check if the sender is the order creator
	assert(msg.From == currentOrderEntry.creator, 'Unauthorized to cancel this order')

	-- Block cancellation of English auctions that have bids
	assert(
		not (currentOrderEntry.orderType == constants.ORDER_TYPES.ENGLISH and currentOrderEntry.highestBidder),
		'You cannot cancel an English auction that has bids'
	)

	-- Only allow cancelling active or expired orders
	assert(
		currentOrderEntry.status == constants.ORDER_STATUSES.ACTIVE
			or currentOrderEntry.status == constants.ORDER_STATUSES.EXPIRED,
		'Order cannot be cancelled because it is not active or expired'
	)

	-- Update order status before removing
	currentOrderEntry.status = constants.ORDER_STATUSES.CANCELLED
	currentOrderEntry.endedAt = msg.Timestamp

	-- Return funds to the creator
	local balances = require('balances')
	
	-- Check if this order has locked balance (internal ARIO balance order)
	local lockedBalance = balances.getOrderLockedBalance(orderId, currentOrderEntry.creator)
	
	if bint(lockedBalance) > 0 then
		-- Internal balance order: Unlock and return to creator
		balances.unlockBalanceFromOrder(orderId, currentOrderEntry.creator, currentOrderEntry.creator, lockedBalance)
	else
		-- External transfer order (ANT via Credit-Notice): Transfer back with intent tracking
		ucm.transferWithIntent(currentOrderEntry.creator, currentOrderEntry.quantity, currentOrderEntry.token, msg)
	end

	-- Remove the order from the orderbook and index
	if pairData then
		pairData.orders[orderId] = nil
	end
	OrderIndex[orderId] = nil

	return json.encode({
		Status = 'Success',
		Message = 'Order cancelled',
		['X-Group-ID'] = groupId,
		['Order-Id'] = orderId,
	})
end

-- Handler: Info
--- Returns comprehensive information about the marketplace state
--- @param _msg Message The incoming message
--- @return string JSON-encoded InfoResponse
function ucm.infoHandler(_msg)
	-- Count orders by status
	local totalOrders = 0
	local totalPairs = 0
	local activeCount = 0
	local readyCount = 0
	local executedCount = 0
	local cancelledCount = 0
	local expiredCount = 0

	for _, swapTokens in pairs(Orderbook) do
		for _, pair in pairs(swapTokens) do
			totalPairs = totalPairs + 1
			for _, order in pairs(pair.orders) do
				totalOrders = totalOrders + 1
				if order.status == constants.ORDER_STATUSES.ACTIVE then
					activeCount = activeCount + 1
				elseif order.status == constants.ORDER_STATUSES.READY_FOR_SETTLEMENT then
					readyCount = readyCount + 1
				elseif order.status == constants.ORDER_STATUSES.EXECUTED then
					executedCount = executedCount + 1
				elseif order.status == constants.ORDER_STATUSES.CANCELLED then
					cancelledCount = cancelledCount + 1
				elseif order.status == constants.ORDER_STATUSES.EXPIRED then
					expiredCount = expiredCount + 1
				end
			end
		end
	end

	-- Collect intent statistics
	local intentStats = {
		total = 0,
		byStatus = {},
		byType = {},
		byAction = {},
	}

	for _, intent in pairs(Intents) do
		intentStats.total = intentStats.total + 1
		intentStats.byStatus[intent.status] = (intentStats.byStatus[intent.status] or 0) + 1
		intentStats.byType[intent.type] = (intentStats.byType[intent.type] or 0) + 1
		intentStats.byAction[intent.action] = (intentStats.byAction[intent.action] or 0) + 1
	end

	return json.encode({
		name = Name,
		processId = ao.id,
		activity = {
			totalOrders = totalOrders,
			activeOrders = activeCount,
			readyForSettlement = readyCount,
			executedOrders = executedCount,
			cancelledOrders = cancelledCount,
			expiredOrders = expiredCount,
			listedOrders = activeCount + readyCount,
		},
		intents = intentStats,
		ucm = {
			totalPairs = totalPairs,
			accruedFees = tostring(utils.getAccruedFees()),
			arioTokenProcess = ARIO_TOKEN_PROCESS_ID,
		},
	})
end

--- Handler: Settle-Auction
--- Settle an expired English auction by Order-Id
--- @param msg Message The message containing Order-Id, Dominant-Token, Swap-Token, and X-Group-ID tags
--- @return string jsonResponse JSON-encoded response with status and order ID
function ucm.settleAuctionHandler(msg)
	-- Parse parameters from tags (Train-Case)
	local orderId = msg.Tags['Order-Id']
	local dominantToken = msg.Tags['Dominant-Token']
	local swapToken = msg.Tags['Swap-Token']

	assert(orderId, 'Order-Id is required')

	local settleArgs = {
		orderId = orderId,
		sender = msg.From,
		timestamp = msg.Timestamp,
		orderGroupId = msg.Tags['X-Group-ID'] or 'None',
		dominantToken = dominantToken,
		swapToken = swapToken,
		msg = msg, -- Pass msg context for intent tracking
	}

	ucm.settleAuction(settleArgs)
	return json.encode({ Status = 'Success', Message = 'Auction settled', ['Order-Id'] = orderId })
end

--- Handler: Withdraw-Fees
--- Withdraw accrued marketplace fees (owner only)
--- @param msg Message The message from the process owner
--- @return string jsonResponse JSON-encoded response with status and withdrawn amount
function ucm.withdrawFeesHandler(msg)
	-- Only the process owner can withdraw fees
	assert(msg.From == msg.Owner, 'Unauthorized: only process owner can withdraw fees')

	local amount = utils.getAccruedFees()
	assert(amount and amount > 0, 'No fees available to withdraw')

	-- transfer fees to requester
	-- Note: Withdraw-Fees does not use intent tracking as it's an admin operation
	-- and not part of a multi-step workflow
	utils.Send(msg, {
		Target = ARIO_TOKEN_PROCESS_ID,
		Action = 'Transfer',
		Tags = {
			Recipient = msg.From,
			Quantity = tostring(amount),
		},
	})

	utils.resetAccruedFees()

	return json.encode({
		Status = 'Success',
		Message = 'Fees withdrawn',
		Amount = tostring(amount),
	})
end

-- Handler: Get-Order
--- Get a single order by ID
--- @param msg table Message with Order-Id tag
function ucm.getOrderHandler(msg)
	local orderId = msg.Tags['Order-Id']
	assert(orderId, 'Order-Id is required')

	-- Find order using O(1) lookup
	local foundOrder, _ = ucm.getOrderById(orderId)
	assert(foundOrder, 'Order not found')

	-- Return raw order (status, dominantToken, swapToken, bids already on order)
	-- The onAfterHandler will send the Get-Order-Notice with this data
	return json.encode(foundOrder)
end

--- Helper function to check if an order matches the status filter
--- @param order table The order to check
--- @param statusFilter string|nil The status filter to apply
--- @return boolean includeOrder Whether the order should be included
function ucm.matchesStatusFilter(order, statusFilter)
	if not statusFilter or statusFilter == constants.ORDER_STATUS_FILTERS.ALL then
		return true
	elseif statusFilter == constants.ORDER_STATUS_FILTERS.LISTED then
		return order.status == constants.ORDER_STATUSES.ACTIVE
			or order.status == constants.ORDER_STATUSES.READY_FOR_SETTLEMENT
	elseif statusFilter == constants.ORDER_STATUS_FILTERS.COMPLETED then
		return order.status == constants.ORDER_STATUSES.EXECUTED
			or order.status == constants.ORDER_STATUSES.CANCELLED
			or order.status == constants.ORDER_STATUSES.EXPIRED
	elseif statusFilter == constants.ORDER_STATUSES.ACTIVE then
		return order.status == constants.ORDER_STATUSES.ACTIVE
	elseif statusFilter == constants.ORDER_STATUSES.READY_FOR_SETTLEMENT then
		return order.status == constants.ORDER_STATUSES.READY_FOR_SETTLEMENT
	elseif statusFilter == constants.ORDER_STATUSES.EXECUTED then
		return order.status == constants.ORDER_STATUSES.EXECUTED
	elseif statusFilter == constants.ORDER_STATUSES.CANCELLED then
		return order.status == constants.ORDER_STATUSES.CANCELLED
	elseif statusFilter == constants.ORDER_STATUSES.EXPIRED then
		return order.status == constants.ORDER_STATUSES.EXPIRED
	else
		-- Default to listed if unknown status
		return order.status == constants.ORDER_STATUSES.ACTIVE
			or order.status == constants.ORDER_STATUSES.READY_FOR_SETTLEMENT
	end
end

-- Handler: Get-Orders
--- Get multiple orders with flexible filtering
--- @param msg table Message with optional Status, Ids, Dominant-Token, Swap-Token tags and pagination
function ucm.getOrdersHandler(msg)
	local page = utils.parsePaginationTags(msg)

	local statusFilter = msg.Tags.Status
	local idsFilter = utils.parseIdsFilter(msg.Tags.Ids)
	local dominantToken = msg.Tags['Dominant-Token']
	local swapToken = msg.Tags['Swap-Token']

	local ordersArray = {}

	-- If trading pair is specified, only look in that specific pair
	if dominantToken and swapToken then
		local pair = ucm.getPair(dominantToken, swapToken)
		if pair then
			-- If specific IDs are requested
			if idsFilter then
				for orderId, order in pairs(pair.orders) do
					if idsFilter[orderId] then
						table.insert(ordersArray, order)
					end
				end
			else
				-- Get all orders in this pair, applying status filter
				for _, order in pairs(pair.orders) do
					if ucm.matchesStatusFilter(order, statusFilter) then
						table.insert(ordersArray, order)
					end
				end
			end
		end
	else
		-- No pair specified, search all pairs
		-- If specific IDs are requested
		if idsFilter then
			-- Search for orders by ID
			for _, swapTokens in pairs(Orderbook) do
				for _, pair in pairs(swapTokens) do
					for orderId, order in pairs(pair.orders) do
						if idsFilter[orderId] then
							table.insert(ordersArray, order)
						end
					end
				end
			end
		else
			-- Get orders by status filter
			-- Iterate through all orders and filter by status
			for _, swapTokens in pairs(Orderbook) do
				for _, pair in pairs(swapTokens) do
					for _, order in pairs(pair.orders) do
						if ucm.matchesStatusFilter(order, statusFilter) then
							table.insert(ordersArray, order)
						end
					end
				end
			end
		end
	end

	local paginatedOrders = utils.paginateTableWithCursor(
		ordersArray,
		page.cursor,
		'CreatedAt',
		page.limit,
		page.sortBy,
		page.sortOrder,
		page.filters
	)

	-- Return paginated orders as JSON
	-- The onAfterHandler will send the Get-Orders-Notice with this data
	return json.encode(paginatedOrders)
end

return ucm
