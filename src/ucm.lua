local bint = require('.bint')(256)

local utils = require('utils')
local activity = require('activity')
local json = require('json')

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

local ucm = {}

--- Transfer wrapper that handles intent tracking for marketplace transfers
--- @param msg Message The original message context
--- @param sendParams SendParams The parameters to pass to ao.send (must have Action = 'Transfer')
function ucm.transfer(msg, sendParams)
	local utils = require('utils')
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
			sendParams.Tags['X-Intent-Id'] = childIntent.IntentId

			-- Update parent status to "settling" if currently active
			if parent.Status == 'active' then
				intents.updateStatus(parentIntentId, 'settling')
			end
		end
	end

	-- Use utils.Send to actually send the message
	utils.Send(msg, sendParams)
end

-- Helper function to execute token transfers for order matching
function ucm.executeTokenTransfers(args, currentOrderEntry, validPair, calculatedSendAmount, calculatedFillAmount)
	local utils = require('utils')

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
	ucm.transfer(msg, {
		Target = validPair[1],
		Action = 'Transfer',
		Tags = {
			Recipient = currentOrderEntry.Creator,
			Quantity = tostring(calculatedSendAmount),
		},
	})

	-- Transfer swap tokens to the buyer (order sender)
	ucm.transfer(msg, {
		Target = args.swapToken,
		Action = 'Transfer',
		Tags = {
			Recipient = args.sender,
			Quantity = tostring(calculatedFillAmount),
		},
	})
end

function ucm.getPairIndex(pair)
	local pairIndex = -1

	for i, existingOrders in ipairs(Orderbook) do
		if
			(existingOrders.Pair[1] == pair[1] and existingOrders.Pair[2] == pair[2])
			or (existingOrders.Pair[1] == pair[2] and existingOrders.Pair[2] == pair[1])
		then
			pairIndex = i
			break
		end
	end

	return pairIndex
end

-- Helper function to validate ANT dominant token orders (selling ANT for ARIO)
local function validateAntDominantOrder(args, validPair)
	-- ANT tokens can only be sold in quantities of exactly 1
	if bint(args.quantity) ~= bint(1) then
		utils.handleError({
			Target = args.sender,
			Action = 'Validation-Error',
			Message = 'ANT tokens can only be sold in quantities of exactly 1',
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
local function validateArioDominantOrder(args, validPair)
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
local function validateOrderParams(args)
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
		if not validateAntDominantOrder(args, validPair) then
			return nil
		end

		-- Dutch auction specific validation
		if args.orderType == 'dutch' then
			local dutch_auction = require('dutch_auction')
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
		if not validateArioDominantOrder(args, validPair) then
			return nil
		end
	end

	return validPair
end

-- Helper function to ensure trading pair exists in orderbook
local function ensurePairExists(validPair)
	local pairIndex = ucm.getPairIndex(validPair)

	-- Create new pair entry if it doesn't exist
	if pairIndex == -1 then
		table.insert(Orderbook, { Pair = validPair, Orders = {} })
		pairIndex = ucm.getPairIndex(validPair)
	end

	return pairIndex
end

local function handleAntOrderAuctions(args, validPair, pairIndex)
	if args.orderType == 'fixed' then
		local fixed_price = require('fixed_price')
		fixed_price.handleAntOrder(args, validPair, pairIndex)
	elseif args.orderType == 'dutch' then
		local dutch_auction = require('dutch_auction')
		dutch_auction.handleAntOrder(args, validPair, pairIndex)
	elseif args.orderType == 'english' then
		local english_auction = require('english_auction')
		english_auction.handleAntOrder(args, validPair, pairIndex)
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

local function handleArioOrderAuctions(args, validPair, pairIndex)
	-- Check if the desired token is already being sold (prevent duplicate sell orders)
	local currentOrders = Orderbook[pairIndex].Orders
	for orderId, existingOrder in pairs(currentOrders) do
		if existingOrder.Token == args.dominantToken then
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

	if args.orderType == 'fixed' then
		local fixed_price = require('fixed_price')
		fixed_price.handleArioOrder(args, validPair, pairIndex)
	elseif args.orderType == 'dutch' then
		local dutch_auction = require('dutch_auction')
		dutch_auction.handleArioOrder(args, validPair, pairIndex)
	elseif args.orderType == 'english' then
		local english_auction = require('english_auction')
		english_auction.handleArioOrder(args, validPair, pairIndex)
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
	local validPair = validateOrderParams(args)
	if not validPair then
		return
	end

	-- Ensure trading pair exists in orderbook
	local pairIndex = ensurePairExists(validPair)

	if pairIndex > -1 then
		-- Check if the desired token is ARIO (add to orderbook) or ANT (immediate trade only)
		local isBuyingAnt = utils.isArioToken(args.dominantToken) -- If dominantToken is ARIO, we're buying ANT
		local isBuyingArio = not isBuyingAnt -- If dominantToken is not ARIO, we're selling ANT

		-- Handle ANT token orders - check for immediate trades only, don't add to orderbook
		if isBuyingAnt then
			handleAntOrderAuctions(args, validPair, pairIndex)
			return
		end

		-- Handle ARIO token orders - add to orderbook for buy now
		if isBuyingArio then
			handleArioOrderAuctions(args, validPair, pairIndex)
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
		return
	else
		-- Pair not found in orderbook (shouldn't happen after creation)
		utils.handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = 'Pair not found',
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId,
		})
	end
end

function ucm.settleAuction(args)
	local english_auction = require('english_auction')
	english_auction.settleAuction(args)
end

-- Cancel an order
-- Accepts the original msg so we can keep consistent behavior and responses
function ucm.cancelOrder(msg)
	-- Parse parameters from tags (Train-Case)
	local orderId = msg.Tags['Order-Id']
	local groupId = msg.Tags['X-Group-ID'] or 'None'

	assert(orderId, 'Invalid arguments, required { Order-Id }')

	local activityData = activity.findOrderById(orderId, msg.Timestamp)
	assert(activityData, 'Order not found')

	-- Check if the sender is the order creator
	assert(msg.From == activityData.Sender, 'Unauthorized to cancel this order')

	-- Block cancellation of English auctions that have bids
	assert(
		not (activityData.OrderType == 'english' and activityData.Bids and #activityData.Bids > 0),
		'You cannot cancel an English auction that has bids'
	)

	-- Only allow cancelling active or expired orders
	assert(
		activityData.Status == 'active' or activityData.Status == 'expired',
		'Order cannot be cancelled because it is not active or expired'
	)

	-- Find and remove order from orderbook
	local orderFound = false
	for pairIdx, pairData in ipairs(Orderbook) do
		local currentOrderEntry = pairData.Orders[orderId]
		if currentOrderEntry then
			-- Return funds to the creator
			ucm.transfer(msg, {
				Target = currentOrderEntry.Token,
				Action = 'Transfer',
				Tags = {
					Recipient = currentOrderEntry.Creator,
					Quantity = currentOrderEntry.Quantity,
				},
			})

			-- Remove the order from the orderbook
			Orderbook[pairIdx].Orders[orderId] = nil
			orderFound = true
			break
		end
	end

	if orderFound then
		-- Record cancellation internally
		activity.recordCancelledOrder({
			Id = orderId,
			DominantToken = activityData.DominantToken,
			SwapToken = activityData.SwapToken,
			Sender = msg.From,
			Receiver = nil,
			Quantity = tostring(activityData.Quantity),
			Price = tostring(activityData.Price),
			CreatedAt = msg.Timestamp,
			EndedAt = msg.Timestamp,
			CancellationTime = msg.Timestamp,
		})

		return json.encode({
			Status = 'Success',
			Message = 'Order cancelled',
			['X-Group-ID'] = groupId,
			['Order-Id'] = orderId,
		})
	end

	assert(orderFound, 'Order not found in orderbook')
end

-- Handler: Info
function ucm.info(msg)
	return json.encode({
		Name = Name,
		Orderbook = Orderbook,
	})
end

-- Handler: Get-Orderbook-By-Pair
function ucm.getOrderbookByPair(msg)
	if not msg.Tags.DominantToken or not msg.Tags.SwapToken then
		return
	end
	local pairIndex = ucm.getPairIndex({ msg.Tags.DominantToken, msg.Tags.SwapToken })

	if pairIndex > -1 then
		return json.encode({ Orderbook = Orderbook[pairIndex] })
	end
end

-- Handler: Read-Orders
function ucm.readOrders(msg)
	if msg.From ~= ao.id then
		return
	end

	local readOrders = {}
	local pairIndex = ucm.getPairIndex({ msg.Tags.DominantToken, msg.Tags.SwapToken })

	if pairIndex > -1 then
		for orderId, order in pairs(Orderbook[pairIndex].Orders) do
			if not msg.Tags.Creator or order.Creator == msg.Tags.Creator then
				table.insert(readOrders, {
					id = order.Id,
					creator = order.Creator,
					quantity = order.Quantity,
					price = order.Price,
					CreatedAt = order.CreatedAt,
				})
			end
		end

		return json.encode(readOrders)
	end
end

-- Handler: Read-Pair
function ucm.readPair(msg)
	local pairIndex = ucm.getPairIndex({ msg.Tags.DominantToken, msg.Tags.SwapToken })
	if pairIndex > -1 then
		return json.encode({
			Pair = tostring(pairIndex),
			Orderbook = Orderbook[pairIndex],
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

	-- Use internal activity lookup instead of messaging
	local foundOrder = activity.findOrderById(orderId, msg.Timestamp)
	assert(foundOrder, 'Order not found')

	assert(
		foundOrder.Status == 'ready-for-settlement',
		'Order is not ready for settlement. Status: ' .. tostring(foundOrder.Status)
	)

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
	local utils = require('utils')
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

return ucm
