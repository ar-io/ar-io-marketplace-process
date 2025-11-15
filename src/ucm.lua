local bint = require('.bint')(256)

require('types')
local utils = require('utils')
local constants = require('constants')
local json = require('json')
<<<<<<< Updated upstream
local constants = require('constants')

-- Note: fixed_price, dutch_auction, and english_auction are lazy-loaded
-- within functions to avoid circular dependencies

if Name ~= 'ANT Marketplace' then
	Name = 'ANT Marketplace'
end

-- Orderbook {
-- 	Pair [TokenId, TokenId],
-- 	Orders {
-- 		Id,
-- 		Creator,
-- 		Quantity,
-- 		OriginalQuantity,
-- 		Token,
-- 		DateCreated,
-- 		Price
-- 		ExpirationTime
-- 		Type
-- 		MinimumPrice (dutch)
-- 		DecreaseInterval (dutch)
-- 		DecreaseStep (dutch)
-- 	} []
-- } []

if not Orderbook then
	Orderbook = {}
end
=======
local fixed_price = require('fixed_price')
local dutch_auction = require('dutch_auction')
local english_auction = require('english_auction')
>>>>>>> Stashed changes

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
--- @param msg Message The original message context
--- @param sendParams SendParams The parameters to pass to ao.send (must have Action = 'Transfer')
function ucm.transfer(msg, sendParams)
	local intents = require('intents')

	assert(sendParams.Action == 'Transfer', 'ucm.transfer only handles Transfer actions')

	-- Extract parent intent from context
	local parentIntentId = msg.Tags and msg.Tags['X-Intent-Id']

	if parentIntentId then
		-- Validate parent intent exists
		local parent = intents.getById(parentIntentId)
		if parent then
			-- Create child intent
			local childIntent = intents.createChild(
				parentIntentId,
				msg,
				sendParams.Target, -- token process we expect Debit-Notice from
				{
					Recipient = sendParams.Tags and sendParams.Tags.Recipient or nil,
					Quantity = sendParams.Tags and sendParams.Tags.Quantity or nil,
					Token = sendParams.Target,
				}
			)

			-- Add child intent ID to transfer
			sendParams.Tags = sendParams.Tags or {}
			sendParams.Tags['X-Intent-Id'] = childIntent.intentId

			-- Update parent status to "settling" if currently active
			if parent.status == 'active' then
				intents.updateStatus(parentIntentId, 'settling')
			end
		end
	end

	-- Use utils.Send to actually send the message
	utils.Send(msg, sendParams)
end

-- Helper function to execute token transfers for order matching
<<<<<<< Updated upstream
function ucm.executeTokenTransfers(args, currentOrderEntry, validPair, calculatedSendAmount, calculatedFillAmount)
=======
function ucm.executeTokenTransfers(args, currentOrderEntry, _, calculatedSendAmount, calculatedFillAmount)
>>>>>>> Stashed changes
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
	ucm.transfer(msg, {
		Target = args.dominantToken,
		Action = 'Transfer',
		Tags = {
			Recipient = currentOrderEntry.creator,
			Quantity = tostring(calculatedSendAmount),
		},
	})

	-- Transfer swap tokens to the buyer (order sender)
	-- The seller is sending swapToken, so we transfer that to the buyer
	ucm.transfer(msg, {
		Target = args.swapToken,
		Action = 'Transfer',
		Tags = {
			Recipient = args.sender,
			Quantity = tostring(calculatedFillAmount),
		},
	})
end

<<<<<<< Updated upstream
-- Helper function to get or create pair entry in orderbook
-- Returns the pair table and boolean indicating if it was created
local function getPairEntry(dominantToken, swapToken)
	-- Initialize first level if needed
	if not Orderbook[dominantToken] then
		Orderbook[dominantToken] = {}
	end

	-- Initialize second level if needed
	if not Orderbook[dominantToken][swapToken] then
		Orderbook[dominantToken][swapToken] = {
			pair = { dominantToken, swapToken },
			orders = {},
		}
		return Orderbook[dominantToken][swapToken], true
	end

	return Orderbook[dominantToken][swapToken], false
=======
--- Get a trading pair from the orderbook (directional)
--- @param dominantToken string The dominant token ID
--- @param swapToken string The swap token ID
--- @return Pair|nil The pair object or nil if not found
function ucm.getPair(dominantToken, swapToken)
	if Orderbook[dominantToken] and Orderbook[dominantToken][swapToken] then
		return Orderbook[dominantToken][swapToken]
	end
	return nil
>>>>>>> Stashed changes
end

-- Helper function to validate ANT dominant token orders (selling ANT for ARIO)
function ucm.validateAntDominantOrder(args, validPair)
	-- ANT tokens can only be sold in quantities of exactly 1
	if bint(args.quantity) ~= bint(constants.AUCTION.ANT_EXACT_QUANTITY) then
		utils.handleError({
			Target = args.sender,
			Action = 'Validation-Error',
			Message = 'ANT tokens can only be sold in quantities of exactly ' .. constants.AUCTION.ANT_EXACT_QUANTITY,
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId,
		})
		return false
	end

	-- Price is required when selling ANT
	if not args.price then
		utils.handleError({
			Target = args.sender,
			Action = 'Validation-Error',
			Message = 'Price is required when selling ANT tokens',
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId,
		})
		return false
	end

	-- Validate expiration time is valid
	local isValidExpiration, expirationError = utils.checkValidExpirationTime(args.expirationTime, args.createdAt)
	if not isValidExpiration then
		utils.handleError({
			Target = args.sender,
			Action = 'Validation-Error',
			Message = expirationError,
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId,
		})
		return false
	end

	-- Validate price is valid
	local isValidPrice, priceError = utils.checkValidAmount(args.price)
	if not isValidPrice then
		utils.handleError({
			Target = args.sender,
			Action = 'Validation-Error',
			Message = priceError,
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId,
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
			Target = args.sender,
			Action = 'Validation-Error',
			Message = 'Requested order ID is required',
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId,
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
			Target = args.sender,
			Action = 'Order-Error',
			Message = pairError or 'Error validating pair',
			Quantity = args.quantity,
			TransferToken = nil,
			OrderGroupId = args.orderGroupId,
		})
		return nil
	end

	-- 2. Validate ARIO is in trade (marketplace requirement)
	local isArioValid, arioError = utils.validateArioInTrade(args.dominantToken, args.swapToken)
	if not isArioValid then
		utils.handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = arioError or 'Invalid trade - ARIO must be involved',
			Quantity = args.quantity,
			TransferToken = nil,
			OrderGroupId = args.orderGroupId,
		})
		return nil
	end

	-- 3. Check quantity is positive integer
	if not utils.checkValidAmount(args.quantity) then
		utils.handleError({
			Target = args.sender,
			Action = 'Validation-Error',
			Message = 'Quantity must be an integer greater than zero',
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId,
		})
		return nil
	end

	-- 4. Check order type is supported
	if
		not args.orderType
		or args.orderType ~= 'fixed' and args.orderType ~= 'dutch' and args.orderType ~= 'english'
	then
		utils.handleError({
			Target = args.sender,
			Action = 'Validation-Error',
			Message = 'Order type must be "fixed" or "dutch" or "english"',
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId,
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
					Target = args.sender,
					Action = 'Validation-Error',
					Message = dutchError,
					Quantity = args.quantity,
					TransferToken = validPair[1],
					OrderGroupId = args.orderGroupId,
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

-- Helper function to ensure trading pair exists in orderbook
<<<<<<< Updated upstream
local function ensurePairExists(dominantToken, swapToken)
	local pairEntry = getPairEntry(dominantToken, swapToken)
	return pairEntry
end

local function handleAntOrderAuctions(args, validPair)
	if args.orderType == 'fixed' then
		local fixed_price = require('fixed_price')
		fixed_price.handleAntOrder(args, validPair)
	elseif args.orderType == 'dutch' then
		local dutch_auction = require('dutch_auction')
		dutch_auction.handleAntOrder(args, validPair)
	elseif args.orderType == 'english' then
		local english_auction = require('english_auction')
		english_auction.handleAntOrder(args, validPair)
=======
--- Ensure a trading pair exists in the orderbook, creating it if necessary
--- @param validPair string[] The pair as [dominantToken, swapToken]
--- @return Pair The pair object
function ucm.ensurePairExists(validPair)
	local dominantToken, swapToken = validPair[1], validPair[2]
	print('DEBUG ensurePairExists: Looking for pair', dominantToken, swapToken)

	-- Create dominantToken level if it doesn't exist
	if not Orderbook[dominantToken] then
		print('  Creating dominantToken level:', dominantToken)
		Orderbook[dominantToken] = {}
	end

	-- Create pair if it doesn't exist
	if not Orderbook[dominantToken][swapToken] then
		print('  Creating new pair:', dominantToken, '->', swapToken)
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
	print('DEBUG handleAntOrderAuctions: orderType=', args.orderType)
	if args.orderType == constants.ORDER_TYPES.FIXED then
		fixed_price.handleAntOrder(args, validPair, pair)
	elseif args.orderType == constants.ORDER_TYPES.DUTCH then
		print('DEBUG: Loading and calling dutch_auction.handleAntOrder')
		local dutch_auction = require('dutch_auction')
		print('DEBUG: dutch_auction module loaded, calling handleAntOrder')
		dutch_auction.handleAntOrder(args, validPair, pair)
		print('DEBUG: dutch_auction.handleAntOrder returned')
	elseif args.orderType == constants.ORDER_TYPES.ENGLISH then
		english_auction.handleAntOrder(args, validPair, pair)
>>>>>>> Stashed changes
	else
		utils.handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = 'Order type not implemented yet',
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId,
		})
	end
end

<<<<<<< Updated upstream
local function handleArioOrderAuctions(args, validPair)
	-- Check if the desired token is already being sold (prevent duplicate sell orders)
	local pairEntry = Orderbook[args.dominantToken] and Orderbook[args.dominantToken][args.swapToken]
	if pairEntry then
		for _, existingOrder in pairs(pairEntry.orders) do
			if existingOrder.token == args.dominantToken then
				utils.handleError({
					Target = args.sender,
					Action = 'Validation-Error',
					Message = 'This ANT token is already being sold - cannot create duplicate sell order',
					Quantity = args.quantity,
					TransferToken = validPair[1],
					OrderGroupId = args.orderGroupId,
				})
				return
			end
		end
	end

	if args.orderType == 'fixed' then
		local fixed_price = require('fixed_price')
		fixed_price.handleArioOrder(args)
	elseif args.orderType == 'dutch' then
		local dutch_auction = require('dutch_auction')
		dutch_auction.handleArioOrder(args)
	elseif args.orderType == 'english' then
		local english_auction = require('english_auction')
		english_auction.handleArioOrder(args)
=======
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
				Target = args.sender,
				Action = 'Validation-Error',
				Message = 'This ANT token is already being sold - cannot create duplicate sell order',
				Quantity = args.quantity,
				TransferToken = validPair[1],
				OrderGroupId = args.orderGroupId,
			})
			return
		end
	end

	if args.orderType == constants.ORDER_TYPES.FIXED then
		fixed_price.handleArioOrder(args, validPair, pair)
	elseif args.orderType == constants.ORDER_TYPES.DUTCH then
		local dutch_auction = require('dutch_auction')
		dutch_auction.handleArioOrder(args, validPair, pair)
	elseif args.orderType == constants.ORDER_TYPES.ENGLISH then
		english_auction.handleArioOrder(args, validPair, pair)
>>>>>>> Stashed changes
	else
		utils.handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = 'Order type not implemented yet',
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId,
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
<<<<<<< Updated upstream
	ensurePairExists(args.dominantToken, args.swapToken)
=======
	local pair = ucm.ensurePairExists(validPair)
>>>>>>> Stashed changes

	-- Check if the desired token is ARIO (add to orderbook) or ANT (immediate trade only)
	local isBuyingAnt = utils.isArioToken(args.dominantToken) -- If dominantToken is ARIO, we're buying ANT
	local isBuyingArio = not isBuyingAnt -- If dominantToken is not ARIO, we're selling ANT
<<<<<<< Updated upstream

	-- Handle ANT token orders - check for immediate trades only, don't add to orderbook
	if isBuyingAnt then
		handleAntOrderAuctions(args, validPair)
=======
	print(
		'DEBUG createOrder: dominantToken=',
		args.dominantToken,
		'isBuyingAnt=',
		isBuyingAnt,
		'orderType=',
		args.orderType
	)

	-- Handle ANT token orders - check for immediate trades only, don't add to orderbook
	if isBuyingAnt then
		print('DEBUG: Calling handleAntOrderAuctions')
		-- When buying ANT, we need to look for ANT sell orders in the ANT->ARIO pair (opposite direction)
		local oppositePair = { validPair[2], validPair[1] } -- [ANT, ARIO]
		local oppositePairObj = ucm.ensurePairExists(oppositePair)
		ucm.handleAntOrderAuctions(args, oppositePair, oppositePairObj)
>>>>>>> Stashed changes
		return
	end

	-- Handle ARIO token orders - add to orderbook for buy now
	if isBuyingArio then
<<<<<<< Updated upstream
		handleArioOrderAuctions(args, validPair)
=======
		ucm.handleArioOrderAuctions(args, validPair, pair)
>>>>>>> Stashed changes
		return
	end

	-- Placeholder for future order type handling
	utils.handleError({
		Target = args.sender,
		Action = 'Order-Error',
		Message = 'Order type not implemented yet',
		Quantity = args.quantity,
		TransferToken = validPair[1],
		OrderGroupId = args.orderGroupId,
	})
end

function ucm.settleAuction(args)
	-- Find the auction order using O(1) lookup
	local targetOrder, targetPair = ucm.findOrderById(args.orderId)

	if not targetOrder then
		utils.handleError({
			Target = args.sender,
			Action = 'Settlement-Error',
			Message = 'Auction order not found',
			Quantity = '0',
			TransferToken = nil,
			OrderGroupId = args.orderGroupId,
		})
		return
	end

	-- Validate it's an English auction
	if targetOrder.orderType ~= constants.ORDER_TYPES.ENGLISH then
		utils.handleError({
			Target = args.sender,
			Action = 'Settlement-Error',
			Message = 'Order is not an English auction',
			Quantity = '0',
			TransferToken = nil,
			OrderGroupId = args.orderGroupId,
		})
		return
	end

	-- Check if auction has bids
	if not targetOrder.highestBidder then
		utils.handleError({
			Target = args.sender,
			Action = 'Settlement-Error',
			Message = 'No bids found for auction',
			Quantity = '0',
			TransferToken = nil,
			OrderGroupId = args.orderGroupId,
		})
		return
	end

	-- Check if auction has expired
	if not utils.isExpired(targetOrder.expirationTime, args.timestamp) then
		utils.handleError({
			Target = args.sender,
			Action = 'Settlement-Error',
			Message = 'Auction has not expired yet',
			Quantity = '0',
			TransferToken = nil,
			OrderGroupId = args.orderGroupId,
		})
		return
	end

	-- Call the core settlement function with pre-fetched data
<<<<<<< Updated upstream
	local english_auction = require('english_auction')
=======
>>>>>>> Stashed changes
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

<<<<<<< Updated upstream
	-- Find and remove order from orderbook
	local orderFound = false
	for _, swapTokens in pairs(Orderbook) do
		for _, pairData in pairs(swapTokens) do
			local currentOrderEntry = pairData.orders[orderId]
			if currentOrderEntry then
				-- Return funds to the creator
				ucm.transfer(msg, {
					Target = currentOrderEntry.token,
					Action = 'Transfer',
					Tags = {
						Recipient = currentOrderEntry.creator,
						Quantity = currentOrderEntry.quantity,
					},
				})

				-- Remove the order from the orderbook
				pairData.orders[orderId] = nil
				orderFound = true
				break
			end
		end
		if orderFound then
			break
		end
=======
	-- Update order status before removing
	currentOrderEntry.status = constants.ORDER_STATUSES.CANCELLED
	currentOrderEntry.endedAt = msg.Timestamp

	-- Return funds to the creator
	ucm.transfer(msg, {
		Target = currentOrderEntry.token,
		Action = 'Transfer',
		Tags = {
			Recipient = currentOrderEntry.creator,
			Quantity = currentOrderEntry.quantity,
		},
	})

	-- Remove the order from the orderbook and index
	if pairData then
		pairData.orders[orderId] = nil
>>>>>>> Stashed changes
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
<<<<<<< Updated upstream
function ucm.info(_)
=======
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

>>>>>>> Stashed changes
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
<<<<<<< Updated upstream

	local pairData = Orderbook[msg.Tags.DominantToken] and Orderbook[msg.Tags.DominantToken][msg.Tags.SwapToken]

	if pairData then
		return json.encode({ Orderbook = pairData })
=======
	local pair = ucm.getPair(msg.Tags.DominantToken, msg.Tags.SwapToken)

	if pair then
		return json.encode({ Orderbook = pair })
>>>>>>> Stashed changes
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
<<<<<<< Updated upstream
	local pairData = Orderbook[msg.Tags.DominantToken] and Orderbook[msg.Tags.DominantToken][msg.Tags.SwapToken]

	if pairData then
		for _, order in pairs(pairData.orders) do
=======
	local pair = ucm.getPair(msg.Tags.DominantToken, msg.Tags.SwapToken)

	if pair then
		for _, order in pairs(pair.orders) do
>>>>>>> Stashed changes
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
<<<<<<< Updated upstream
function ucm.readPair(msg)
	local pairData = Orderbook[msg.Tags.DominantToken] and Orderbook[msg.Tags.DominantToken][msg.Tags.SwapToken]

	if pairData then
		return json.encode({
			Pair = pairData.pair,
			Orderbook = pairData,
=======
--- Read a specific trading pair
--- @param msg table Message with DominantToken and SwapToken tags
--- @return string|nil JSON-encoded pair info or nil if not found
function ucm.readPairHandler(msg)
	local pair = ucm.getPair(msg.Tags.DominantToken, msg.Tags.SwapToken)
	if pair then
		return json.encode({
			pair = pair.pair,
			orderbook = pair,
>>>>>>> Stashed changes
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
