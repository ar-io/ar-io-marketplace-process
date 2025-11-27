local utils = require('utils')
local constants = require('constants')
local bint = require('.bint')(256)
-- ucm is required at runtime to avoid circular dependency

local dutch_auction = {}
local ORDER_STATUSES = constants.ORDER_STATUSES
local ORDER_TYPES = constants.ORDER_TYPES

--- Prune an expired Dutch auction
--- @param order table The order to prune
function dutch_auction.pruneExpiredAuction(order)
	order.status = ORDER_STATUSES.EXPIRED
	order.endedAt = order.expirationTime
end

function dutch_auction.calculateDecreaseStep(args)
	local intervalsCount = (bint(args.expirationTime) - bint(args.createdAt)) / bint(args.decreaseInterval)
	local priceDecreaseMax = bint(args.price) - bint(args.minimumPrice)
	return math.floor(priceDecreaseMax / intervalsCount)
end

--- Handle ARIO-dominant order (buying ANT with ARIO) for Dutch auction
--- @param args table Order arguments
--- @param validPair TokenId[] The validated pair [ARIO, ANT]
--- @param pair Pair The pair object from orderbook
function dutch_auction.handleArioOrder(args, validPair, pair)
	-- NOTE: No balance deduction here - ANT comes via Credit-Notice
	-- This creates a Dutch auction selling ANT for ARIO
	
	local decreaseStep = dutch_auction.calculateDecreaseStep(args)

	-- Add to index FIRST for O(1) lookup (safer update order)
	OrderIndex[args.orderId] = {
		dominantToken = validPair[1],
		swapToken = validPair[2],
	}

	-- Then add to orderbook using dictionary-style (lookup table) for efficient order management
	pair.orders[args.orderId] = {
		id = args.orderId,
		quantity = tostring(args.quantity),
		originalQuantity = tostring(args.quantity),
		creator = args.sender,
		token = args.dominantToken,
		dateCreated = args.createdAt,
		price = args.price and tostring(args.price),
		expirationTime = args.expirationTime,
		orderType = ORDER_TYPES.DUTCH,
		minimumPrice = args.minimumPrice and tostring(args.minimumPrice),
		decreaseInterval = args.decreaseInterval and tostring(args.decreaseInterval),
		decreaseStep = tostring(decreaseStep),
		status = ORDER_STATUSES.ACTIVE,
		dominantToken = validPair[1],
		swapToken = validPair[2],
	}

	-- Schedule pruning for expiration if needed
	if args.expirationTime then
		local ucm = require('ucm')
		ucm.scheduleNextOrderbookPruning(args.expirationTime)
	end

	-- Notify sender of successful order creation
	utils.Send(args.msg, {
		Target = args.sender,
		Action = 'Order-Success',
		Tags = {
			Status = 'Success',
			['Order-Id'] = args.orderId,
			Handler = 'Create-Order',
			['Dominant-Token'] = args.dominantToken,
			['Swap-Token'] = args.swapToken,
			Quantity = tostring(args.quantity),
			Price = args.price and tostring(args.price),
			Message = 'ARIO order added to orderbook for Dutch auction!',
			['X-Group-ID'] = args.orderGroupId,
			['Order-Type'] = ORDER_TYPES.DUTCH,
		},
	})
end

--- Handle ANT-dominant order (selling ANT for ARIO) for Dutch auction
--- @param args table Order arguments
--- @param _validPair TokenId[] The validated pair [ANT, ARIO]
--- @param pair Pair The pair object from orderbook
function dutch_auction.handleAntOrder(args, _validPair, pair)
	local currentOrders = pair.orders
	local matches = {}
	local matchedOrderId = nil

	-- Attempt to match with existing Dutch orders for immediate trade
	for orderId, currentOrderEntry in pairs(currentOrders) do
		-- Check if order has expired
		if utils.isExpired(currentOrderEntry.expirationTime, args.createdAt) then
			-- Skip expired orders
			goto continue
		end

		-- Check if the order is a Dutch auction order
		if currentOrderEntry.orderType ~= ORDER_TYPES.DUTCH then
			goto continue
		end

		-- Check if this is the specific order we're looking for
		if currentOrderEntry.id ~= args.requestedOrderId then
			goto continue
		end

		-- Calculate current price based on time passed since order creation
		local timePassed = bint(args.createdAt) - bint(currentOrderEntry.dateCreated)
		local intervalsPassed = math.floor(timePassed / bint(currentOrderEntry.decreaseInterval))
		local intervalsBint = bint(intervalsPassed)
		local decreaseStepBint = bint(currentOrderEntry.decreaseStep)
		local priceReduction = intervalsBint * decreaseStepBint
		local currentPrice = bint(currentOrderEntry.price) - priceReduction
		-- Ensure price doesn't go below minimum
		if currentPrice < bint(currentOrderEntry.minimumPrice) then
			currentPrice = bint(currentOrderEntry.minimumPrice)
		end

		-- Check if the user sent enough ARIO to pay for 1 ANT token at the current Dutch auction price
		if bint(args.quantity) >= currentPrice then
		local fillAmount = bint(constants.QUANTITY.ANT_EXACT_AMOUNT) -- 1 ANT token (always 1 for ANT orders)
		-- Validate we have a valid fill amount
		if fillAmount <= bint(0) then
			utils.refundAndError(args.msg, args.sender, 'No amount to fill', 'Order-Error')
			return
		end

		-- Check if sent amount is sufficient for current price
		local requiredAmount = currentPrice
		local sentAmount = bint(args.quantity) -- User pays the current Dutch auction price

		if sentAmount < requiredAmount then
			utils.refundAndError(
				args.msg,
				args.sender,
				'Insufficient payment for current Dutch auction price. Required: '
					.. tostring(requiredAmount)
					.. ', Sent: '
					.. tostring(sentAmount),
				'Order-Error'
			)
			return
		end

			args.executionPrice = tostring(currentPrice)

			-- Apply fees and calculate final amounts
			local calculatedSendAmount = utils.calculateSendAmount(requiredAmount)
			local calculatedFillAmount = utils.calculateFillAmount(fillAmount)

		utils.sendFeeToTreasury(requiredAmount, calculatedSendAmount, args.dominantToken, args.msg)

		-- Execute token transfers
		local ucm = require('ucm')
		ucm.executeTokenTransfers({
			sender = args.sender,
			dominantToken = args.dominantToken,
			swapToken = args.swapToken,
			originalSendAmount = args.originalSendAmount,
			msg = args.msg,
			currentOrderEntry = currentOrderEntry,
			calculatedSendAmount = calculatedSendAmount,
			calculatedFillAmount = calculatedFillAmount,
		})

	-- Handle refund if sent amount was more than required
	if sentAmount > requiredAmount then
		local refundAmount = sentAmount - requiredAmount
		local _utils = require('utils')
		if _utils.isArioToken(args.dominantToken) then
			-- ARIO: Refund to buyer's internal balance (was already deducted by balances.transfer)
			local balances = require('balances')
			balances.increaseBalance(args.sender, tostring(refundAmount))
		else
			-- ANT: Refund via external transfer with intent tracking
			ucm.transferWithIntent(args.sender, tostring(refundAmount), args.dominantToken, args.msg)
		end
	end

			-- Mark order as executed and update fields
			currentOrderEntry.status = ORDER_STATUSES.EXECUTED
			currentOrderEntry.endedAt = args.createdAt
			currentOrderEntry.sender = currentOrderEntry.creator
			currentOrderEntry.receiver = args.sender
			---@diagnostic disable-next-line: inject-field
			currentOrderEntry.buyer = args.sender
			currentOrderEntry.price = currentPrice
			---@diagnostic disable-next-line: inject-field
			currentOrderEntry.finalPrice = tostring(currentPrice)

			-- Record the match for response
			local match = {
				Id = currentOrderEntry.id,
				Quantity = calculatedFillAmount,
				Price = tostring(currentPrice),
			}
			table.insert(matches, match)
			-- Mark the order ID for removal
			matchedOrderId = orderId
			break -- Only match with one order, no partial matching
		end

		::continue::
	end

	-- Remove the matched order from the orderbook
	if matchedOrderId then
		local matchedOrder = pair.orders[matchedOrderId]
		if matchedOrder then
			-- Store tokens before removing the order
			local dominantToken = matchedOrder.dominantToken
			local swapToken = matchedOrder.swapToken
			
			pair.orders[matchedOrderId] = nil
			-- Remove from index
			OrderIndex[matchedOrderId] = nil
			
			-- Prune the pair if it's now empty
			local ucm = require('ucm')
			ucm.pruneEmptyPair(dominantToken, swapToken)
		end
	end

	-- Send success response if any matches occurred
	if #matches > 0 then
		utils.Send(args.msg, {
			Target = args.sender,
			Action = 'Order-Success',
			Tags = {
				['Order-Id'] = args.orderId,
				Status = 'Success',
				Handler = 'Create-Order',
				['Dominant-Token'] = args.dominantToken,
				['Swap-Token'] = args.swapToken,
				Quantity = tostring(args.quantity),
				Price = args.price and tostring(args.price) or 'None',
				Message = 'ANT order executed immediately in Dutch auction!',
				['X-Group-ID'] = args.orderGroupId or 'None',
				['Order-Type'] = ORDER_TYPES.DUTCH,
			},
		})
	else
		-- No matches found for ANT token - return error
		utils.refundAndError(
			args.msg,
			args.sender,
			'No matching Dutch auction order found for immediate ANT trade',
			'Order-Error'
		)
		return
	end
end

--- Validate Dutch auction specific parameters
--- @param args table Order arguments containing minimumPrice, decreaseInterval, expirationTime, and price
--- @return boolean success True if validation passes, false otherwise
--- @return string? error Optional error message if validation fails
function dutch_auction.validateDutchParams(args)
	if not args.minimumPrice then
		return false, 'Minimum price must be provided'
	end

	local isValidMinimumPrice, minimumPriceError = utils.checkValidAmount(args.minimumPrice)
	if not isValidMinimumPrice then
		return false, minimumPriceError
	end

	if not args.decreaseInterval then
		return false, 'Decrease interval must be provided'
	end

	local isValidDecreaseInterval, decreaseIntervalError = utils.checkValidAmount(args.decreaseInterval)
	if not isValidDecreaseInterval then
		return false, decreaseIntervalError
	end

	if args.expirationTime and (bint(args.decreaseInterval) >= bint(args.expirationTime)) then
		return false, 'Decrease interval must be less than expiration time'
	end

	-- Calculate intervals and price decrease
	local intervalsCount = (bint(args.expirationTime) - bint(args.createdAt)) / bint(args.decreaseInterval)
	local priceDecreaseMax = bint(args.price) - bint(args.minimumPrice)
	
	-- Ensure price decrease is evenly divisible by interval count
	local remainder = priceDecreaseMax % intervalsCount
	if remainder > bint(0) then
		return false, 
			'Price decrease (' .. tostring(priceDecreaseMax) .. ' mARIO) must be evenly divisible by interval count (' .. 
			tostring(intervalsCount) .. '). Adjust your price range or decrease interval to ensure even price drops.'
	end
	
	local decreaseStep = priceDecreaseMax / intervalsCount

	if decreaseStep < bint(1) then
		return false, 'Decrease step must be at least 1 mARIO per interval. ' ..
		              'Increase price difference, decrease auction duration, or increase decrease interval.'
	end

	return true
end

return dutch_auction
