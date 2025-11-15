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
function ucm.findOrderById(orderId)
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

--- Transfer wrapper that handles intent tracking for marketplace transfers
--- @param recipient string The recipient address
--- @param quantity string The amount to transfer
--- @param token string The token process ID
--- @param handledMsg Message The original message context
function ucm.transfer(recipient, quantity, token, handledMsg)
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

-- Helper function to execute token transfers for order matching
function ucm.executeTokenTransfers(args, currentOrderEntry, _, calculatedSendAmount, calculatedFillAmount)
	-- Optionally record fee (difference between original send amount and calculated amount)
	if args and args.originalSendAmount then
		local ok1, orig = pcall(function()
			return bint(args.originalSendAmount)
		end)
		local ok2, calc = pcall(function()
			return bint(calculatedSendAmount)
		end)
		if ok1 and ok2 and orig > calc then
			local fee = orig - calc
			AccruedFeesAmount = AccruedFeesAmount + tonumber(tostring(fee))
		end
	end

	-- Get msg context for intent tracking
	local msg = args.msg or { Tags = {} }

	-- Transfer tokens to the seller (order creator)
	-- The buyer is sending dominantToken, so we transfer that to the seller
	ucm.transfer(currentOrderEntry.creator, tostring(calculatedSendAmount), args.dominantToken, msg)

	-- Transfer swap tokens to the buyer (order sender)
	-- The seller is sending swapToken, so we transfer that to the buyer
	ucm.transfer(args.sender, tostring(calculatedFillAmount), args.swapToken, msg)
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

-- Helper function to validate ANT dominant token orders (selling ANT for ARIO)
function ucm.validateAntDominantOrder(args, validPair)
	-- ANT tokens can only be sold in quantities of exactly 1
	if bint(args.quantity) ~= bint(constants.AUCTION.ANT_EXACT_QUANTITY) then
		utils.handleError({
			target = args.sender,
			action = 'Validation-Error',
			message = 'ANT tokens can only be sold in quantities of exactly ' .. constants.AUCTION.ANT_EXACT_QUANTITY,
			quantity = args.quantity,
			transferToken = validPair[1],
			orderGroupId = args.orderGroupId,
		})
		return false
	end

	-- Price is required when selling ANT
	if not args.price then
		utils.handleError({
			target = args.sender,
			action = 'Validation-Error',
			message = 'Price is required when selling ANT tokens',
			quantity = args.quantity,
			transferToken = validPair[1],
			orderGroupId = args.orderGroupId,
		})
		return false
	end

	-- Validate expiration time is valid
	local isValidExpiration, expirationError = utils.checkValidExpirationTime(args.expirationTime, args.createdAt)
	if not isValidExpiration then
		utils.handleError({
			target = args.sender,
			action = 'Validation-Error',
			message = expirationError,
			quantity = args.quantity,
			transferToken = validPair[1],
			orderGroupId = args.orderGroupId,
		})
		return false
	end

	-- Validate price is valid
	local isValidPrice, priceError = utils.checkValidAmount(args.price)
	if not isValidPrice then
		utils.handleError({
			target = args.sender,
			action = 'Validation-Error',
			message = priceError,
			quantity = args.quantity,
			transferToken = validPair[1],
			orderGroupId = args.orderGroupId,
		})
		return false
	end

	return true
end

-- Helper function to validate ARIO dominant token orders (buying ANT with ARIO)
function ucm.validateArioDominantOrder(args, validPair)
	-- Currently no specific validation rules for ARIO dominant orders
	-- All general validations (quantity, pair, etc.) are handled in validateOrderParams
	-- This function is a placeholder for future ARIO-specific validation rules
	if not args.requestedOrderId then
		utils.handleError({
			target = args.sender,
			action = 'Validation-Error',
			message = 'Requested order ID is required',
			quantity = args.quantity,
			transferToken = validPair[1],
			orderGroupId = args.orderGroupId,
		})
		return false
	end

	return true
end

-- Helper function to validate order parameters
function ucm.validateOrderParams(args)
	-- 1. Check pair data
	local validPair, pairError = utils.validatePairData({ args.dominantToken, args.swapToken })
	if not validPair then
		utils.handleError({
			target = args.sender,
			action = 'Order-Error',
			message = pairError or 'Error validating pair',
			quantity = args.quantity,
			transferToken = nil,
			orderGroupId = args.orderGroupId,
		})
		return nil
	end

	-- 2. Validate ARIO is in trade (marketplace requirement)
	local isArioValid, arioError = utils.validateArioInTrade(args.dominantToken, args.swapToken)
	if not isArioValid then
		utils.handleError({
			target = args.sender,
			action = 'Order-Error',
			message = arioError or 'Invalid trade - ARIO must be involved',
			quantity = args.quantity,
			transferToken = nil,
			orderGroupId = args.orderGroupId,
		})
		return nil
	end

	-- 3. Check quantity is positive integer
	if not utils.checkValidAmount(args.quantity) then
		utils.handleError({
			target = args.sender,
			action = 'Validation-Error',
			message = 'Quantity must be an integer greater than zero',
			quantity = args.quantity,
			transferToken = validPair[1],
			orderGroupId = args.orderGroupId,
		})
		return nil
	end

	-- 4. Check order type is supported
	if
		not args.orderType
		or args.orderType ~= 'fixed' and args.orderType ~= 'dutch' and args.orderType ~= 'english'
	then
		utils.handleError({
			target = args.sender,
			action = 'Validation-Error',
			message = 'Order type must be "fixed" or "dutch" or "english"',
			quantity = args.quantity,
			transferToken = validPair[1],
			orderGroupId = args.orderGroupId,
		})
		return nil
	end
	-- 5. Check if it's ANT dominant (selling ANT) or ARIO dominant (buying ANT)
	local isAntDominant = not utils.isArioToken(args.dominantToken)

	if isAntDominant then
		-- ANT dominant: validate ANT-specific requirements
		if not ucm.validateAntDominantOrder(args, validPair) then
			return nil
		end

		-- Dutch auction specific validation
		if args.orderType == constants.ORDER_TYPES.DUTCH then
			local isValidDutch, dutchError = dutch_auction.validateDutchParams(args)
			if not isValidDutch then
				utils.handleError({
					target = args.sender,
					action = 'Validation-Error',
					message = dutchError,
					quantity = args.quantity,
					transferToken = validPair[1],
					orderGroupId = args.orderGroupId,
				})
				return nil
			end
		end
	else
		-- ARIO dominant: validate ARIO-specific requirements
		if not ucm.validateArioDominantOrder(args, validPair) then
			return nil
		end
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
		local dutch_auction = require('dutch_auction')
		dutch_auction.handleAntOrder(args, validPair, pair)
	elseif args.orderType == constants.ORDER_TYPES.ENGLISH then
		english_auction.handleAntOrder(args, validPair, pair)
	else
		utils.handleError({
			target = args.sender,
			action = 'Order-Error',
			message = 'Order type not implemented yet',
			quantity = args.quantity,
			transferToken = validPair[1],
			orderGroupId = args.orderGroupId,
		})
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
			utils.handleError({
				target = args.sender,
				action = 'Validation-Error',
				message = 'This ANT token is already being sold - cannot create duplicate sell order',
				quantity = args.quantity,
				transferToken = validPair[1],
				orderGroupId = args.orderGroupId,
			})
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
		utils.handleError({
			target = args.sender,
			action = 'Order-Error',
			message = 'Order type not implemented yet',
			quantity = args.quantity,
			transferToken = validPair[1],
			orderGroupId = args.orderGroupId,
		})
	end
end

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
	utils.handleError({
		target = args.sender,
		action = 'Order-Error',
		message = 'Order type not implemented yet',
		quantity = args.quantity,
		transferToken = validPair[1],
		orderGroupId = args.orderGroupId,
	})
end

function ucm.settleAuction(args)
	-- Find the auction order using O(1) lookup
	local targetOrder, targetPair = ucm.findOrderById(args.orderId)

	if not targetOrder then
		utils.handleError({
			target = args.sender,
			action = 'Settlement-Error',
			message = 'Auction order not found',
			quantity = '0',
			transferToken = nil,
			orderGroupId = args.orderGroupId,
		})
		return
	end

	-- Validate it's an English auction
	if targetOrder.orderType ~= constants.ORDER_TYPES.ENGLISH then
		utils.handleError({
			target = args.sender,
			action = 'Settlement-Error',
			message = 'Order is not an English auction',
			quantity = '0',
			transferToken = nil,
			orderGroupId = args.orderGroupId,
		})
		return
	end

	-- Check if auction has bids
	if not targetOrder.highestBidder then
		utils.handleError({
			target = args.sender,
			action = 'Settlement-Error',
			message = 'No bids found for auction',
			quantity = '0',
			transferToken = nil,
			orderGroupId = args.orderGroupId,
		})
		return
	end

	-- Check if auction has expired
	if not utils.isExpired(targetOrder.expirationTime, args.timestamp) then
		utils.handleError({
			target = args.sender,
			action = 'Settlement-Error',
			message = 'Auction has not expired yet',
			quantity = '0',
			transferToken = nil,
			orderGroupId = args.orderGroupId,
		})
		return
	end

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

-- Cancel an order
-- Accepts the original msg so we can keep consistent behavior and responses
function ucm.cancelOrderHandler(msg)
	-- Parse parameters from tags (Train-Case)
	local orderId = msg.Tags['Order-Id']
	local groupId = msg.Tags['X-Group-ID'] or 'None'

	assert(orderId, 'Invalid arguments, required { Order-Id }')

	-- Find order using O(1) lookup
	local currentOrderEntry, pairData = ucm.findOrderById(orderId)
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
	ucm.transfer(currentOrderEntry.creator, currentOrderEntry.quantity, currentOrderEntry.token, msg)

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
--- @param msg Message The incoming message
--- @return string JSON-encoded InfoResponse
---@diagnostic disable-next-line: unused-local
function ucm.infoHandler(msg)
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
			accruedFees = tostring(AccruedFeesAmount),
			arioTokenProcess = ARIO_TOKEN_PROCESS_ID,
		},
	})
end

-- Handler: Get-Orderbook-By-Pair
--- Get orderbook for a specific trading pair
--- @param msg table Message with DominantToken and SwapToken tags
--- @return string|nil JSON-encoded orderbook or nil if not found
function ucm.getOrderbookByPairHandler(msg)
	if not msg.Tags.DominantToken or not msg.Tags.SwapToken then
		return
	end
	local pair = ucm.getPair(msg.Tags.DominantToken, msg.Tags.SwapToken)

	if pair then
		return json.encode({ Orderbook = pair })
	end
end

-- Handler: Read-Orders
--- Read orders from a specific trading pair
--- @param msg table Message with DominantToken and SwapToken tags
--- @return string|nil JSON-encoded orders or nil if not found
function ucm.readOrdersHandler(msg)
	if msg.From ~= ao.id then
		return
	end

	local readOrders = {}
	local pair = ucm.getPair(msg.Tags.DominantToken, msg.Tags.SwapToken)

	if pair then
		for _, order in pairs(pair.orders) do
			if not msg.Tags.Creator or order.creator == msg.Tags.Creator then
				table.insert(readOrders, {
					id = order.id,
					creator = order.creator,
					quantity = order.quantity,
					price = order.price,
					dateCreated = order.dateCreated,
				})
			end
		end

		return json.encode(readOrders)
	end
end

-- Handler: Read-Pair
--- Read a specific trading pair
--- @param msg table Message with DominantToken and SwapToken tags
--- @return string|nil JSON-encoded pair info or nil if not found
function ucm.readPairHandler(msg)
	local pair = ucm.getPair(msg.Tags.DominantToken, msg.Tags.SwapToken)
	if pair then
		return json.encode({
			pair = pair.pair,
			orderbook = pair,
		})
	end
end

-- Handler: Settle-Auction
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

-- Handler: Withdraw-Fees
function ucm.withdrawFeesHandler(msg)
	-- Only the process owner can withdraw fees
	assert(msg.From == msg.Owner, 'Unauthorized: only process owner can withdraw fees')

	local amount = AccruedFeesAmount
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

	AccruedFeesAmount = 0

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

	if not orderId then
		utils.Send(msg, {
			Target = msg.From,
			Action = 'Input-Error',
			Message = 'Order-Id parameter is required',
		})
		return
	end

	-- Find order using O(1) lookup
	local foundOrder, _ = ucm.findOrderById(orderId)

	if not foundOrder then
		utils.Send(msg, {
			Target = msg.From,
			Action = 'Order-Not-Found',
			Message = 'Order with ID ' .. orderId .. ' not found',
		})
		return
	end

	-- Return raw order (status, dominantToken, swapToken, bids already on order)
	local response = foundOrder

	if msg.Tags.Functioninvoke or msg.Tags.FunctionInvoke then
		msg.reply({ Data = json.encode(response) })
	else
		utils.Send(msg, {
			Target = msg.From,
			Action = 'Read-Success',
			Data = json.encode(response),
		})
	end
end

-- Handler: Get-Orders
--- Get multiple orders with flexible filtering
--- @param msg table Message with optional Status, Ids tags and pagination
function ucm.getOrdersHandler(msg)
	local page = utils.parsePaginationTags(msg)

	-- Support both 'status' and 'type' for backward compatibility
	local statusFilter = msg.Tags.Status or msg.Tags.status
	local idsParam = msg.Tags.Ids or msg.Tags.ids

	local ordersArray = {}

	-- If specific IDs are requested
	if idsParam then
		local ids = {}
		for id in string.gmatch(idsParam, '([^,]+)') do
			ids[id:match('^%s*(.-)%s*$')] = true -- trim whitespace
		end

		-- Search for orders by ID
		for _, swapTokens in pairs(Orderbook) do
			for _, pair in pairs(swapTokens) do
				for orderId, order in pairs(pair.orders) do
					if ids[orderId] then
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
					local includeOrder = false

					if not statusFilter or statusFilter == 'all' then
						includeOrder = true
					elseif statusFilter == 'listed' then
						-- Active and ready-for-settlement orders
						includeOrder = order.status == constants.ORDER_STATUSES.ACTIVE
							or order.status == constants.ORDER_STATUSES.READY_FOR_SETTLEMENT
					elseif statusFilter == 'completed' then
						-- Completed orders (executed, cancelled, expired)
						includeOrder = order.status == constants.ORDER_STATUSES.EXECUTED
							or order.status == constants.ORDER_STATUSES.CANCELLED
							or order.status == constants.ORDER_STATUSES.EXPIRED
					elseif statusFilter == constants.ORDER_STATUSES.ACTIVE or statusFilter == 'active' then
						includeOrder = order.status == constants.ORDER_STATUSES.ACTIVE
					elseif
						statusFilter == constants.ORDER_STATUSES.READY_FOR_SETTLEMENT
						or statusFilter == 'ready-for-settlement'
					then
						includeOrder = order.status == constants.ORDER_STATUSES.READY_FOR_SETTLEMENT
					elseif statusFilter == constants.ORDER_STATUSES.EXECUTED or statusFilter == 'executed' then
						includeOrder = order.status == constants.ORDER_STATUSES.EXECUTED
					elseif statusFilter == constants.ORDER_STATUSES.CANCELLED or statusFilter == 'cancelled' then
						includeOrder = order.status == constants.ORDER_STATUSES.CANCELLED
					elseif statusFilter == constants.ORDER_STATUSES.EXPIRED or statusFilter == 'expired' then
						includeOrder = order.status == constants.ORDER_STATUSES.EXPIRED
					else
						-- Default to listed if unknown status
						includeOrder = order.status == constants.ORDER_STATUSES.ACTIVE
							or order.status == constants.ORDER_STATUSES.READY_FOR_SETTLEMENT
					end

					if includeOrder then
						table.insert(ordersArray, order)
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

	utils.Send(msg, {
		Target = msg.From,
		Action = 'Read-Success',
		Data = json.encode(paginatedOrders),
	})
end

return ucm
