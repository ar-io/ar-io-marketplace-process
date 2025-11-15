local utils = require('utils')
local activity = require('activity')
local bint = require('.bint')(256)

-- Note: ucm is lazy-loaded within functions to avoid circular dependency
-- (ucm requires dutch_auction, and dutch_auction requires ucm)

local dutch_auction = {}

function dutch_auction.calculateDecreaseStep(args)
	local intervalsCount = (bint(args.expirationTime) - bint(args.createdAt)) / bint(args.decreaseInterval)
	local priceDecreaseMax = bint(args.price) - bint(args.minimumPrice)
	return math.floor(priceDecreaseMax / intervalsCount)
end

function dutch_auction.handleArioOrder(args)
	local decreaseStep = dutch_auction.calculateDecreaseStep(args)

	local orderId = args.orderId
	Orderbook[args.dominantToken][args.swapToken].orders[orderId] = {
		id = args.orderId,
		quantity = tostring(args.quantity),
		originalQuantity = tostring(args.quantity),
		creator = args.sender,
		token = args.dominantToken,
		dateCreated = args.createdAt,
		price = args.price and tostring(args.price),
		expirationTime = args.expirationTime,
		orderType = 'dutch',
		minimumPrice = args.minimumPrice and tostring(args.minimumPrice),
		decreaseInterval = args.decreaseInterval and tostring(args.decreaseInterval),
		decreaseStep = tostring(decreaseStep),
	}

	activity.recordListedOrder({
		Id = args.orderId,
		DominantToken = args.dominantToken,
		SwapToken = args.swapToken,
		Sender = args.sender,
		Receiver = nil,
		Quantity = tostring(args.quantity),
		Price = args.price and tostring(args.price),
		ExpirationTime = args.expirationTime,
		CreatedAt = args.createdAt,
		OrderType = 'dutch',
		MinimumPrice = args.minimumPrice and tostring(args.minimumPrice),
		DecreaseInterval = args.decreaseInterval and tostring(args.decreaseInterval),
		DecreaseStep = tostring(decreaseStep),
	})

	-- Notify sender of successful order creation
	ao.send({
		Target = args.sender,
		Action = 'Order-Success',
		Tags = {
			Status = 'Success',
			OrderId = args.orderId,
			Handler = 'Create-Order',
			DominantToken = args.dominantToken,
			SwapToken = args.swapToken,
			Quantity = tostring(args.quantity),
			Price = args.price and tostring(args.price),
			Message = 'ARIO order added to orderbook for Dutch auction!',
			['X-Group-ID'] = args.orderGroupId,
			OrderType = 'dutch',
		},
	})
end

function dutch_auction.handleAntOrder(args, validPair)
	-- Swap the pair to get [ARIO, ANT] since we're buying ANT with ARIO
	local arioDominant = validPair[2] -- ARIO token
	local antSwap = validPair[1] -- ANT token

	local pairData = Orderbook[antSwap] and Orderbook[antSwap][arioDominant]
	if not pairData then
		utils.handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = 'No matching Dutch auction order found for immediate ANT trade',
			Quantity = args.quantity,
			TransferToken = args.dominantToken,
			OrderGroupId = args.orderGroupId,
		})
		return
	end

	local currentOrders = pairData.orders
	local matches = {}
	local matchedOrderId = nil

	-- Attempt to match with existing Dutch orders for immediate trade
	for orderId, currentOrderEntry in pairs(currentOrders) do
		-- Check if order has expired
		if currentOrderEntry.expirationTime and bint(currentOrderEntry.expirationTime) < bint(args.createdAt) then
			-- Skip expired orders
			goto continue
		end

		-- Check if the order is a Dutch auction order
		if currentOrderEntry.orderType ~= 'dutch' then
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
			local fillAmount = bint(1) -- 1 ANT token (always 1 for ANT orders)
			-- Validate we have a valid fill amount
			if fillAmount <= bint(0) then
				utils.handleError({
					Target = args.sender,
					Action = 'Order-Error',
					Message = 'No amount to fill',
					Quantity = args.quantity,
					TransferToken = args.dominantToken,
					OrderGroupId = args.orderGroupId,
				})
				return
			end

			-- Check if sent amount is sufficient for current price

			local requiredAmount = currentPrice
			local sentAmount = bint(args.quantity) -- User pays the current Dutch auction price

			if sentAmount < requiredAmount then
				utils.handleError({
					Target = args.sender,
					Action = 'Order-Error',
					Message = 'Insufficient payment for current Dutch auction price',
					Quantity = args.quantity, -- Refund the ARIO amount that was sent
					TransferToken = args.dominantToken, -- Send to ARIO token process (dominantToken)
					OrderGroupId = args.orderGroupId,
					RequiredAmount = tostring(requiredAmount),
					SentAmount = tostring(sentAmount),
				})
				return
			end

			args.executionPrice = tostring(currentPrice)

			-- Apply fees and calculate final amounts
			local calculatedSendAmount = utils.calculateSendAmount(requiredAmount)
			local calculatedFillAmount = utils.calculateFillAmount(fillAmount)

			utils.sendFeeToTreasury(requiredAmount, calculatedSendAmount, args.dominantToken, args.msg)

			-- Execute token transfers
			local ucm = require('ucm')
			ucm.executeTokenTransfers(args, currentOrderEntry, validPair, calculatedSendAmount, calculatedFillAmount)

			-- Handle refund if sent amount was more than required
			if sentAmount > requiredAmount then
				local refundAmount = sentAmount - requiredAmount
				ucm.transfer(args.msg, {
					Target = args.dominantToken, -- ARIO token process (dominantToken)
					Action = 'Transfer',
					Tags = {
						Recipient = args.sender,
						Quantity = tostring(refundAmount),
					},
				})
			end

			-- Record the match
			local match = activity.recordMatch(args, currentOrderEntry, validPair, calculatedFillAmount)
			table.insert(matches, match)

			-- Mark the order ID for removal
			matchedOrderId = orderId
			break -- Only match with one order, no partial matching
		end

		::continue::
	end

	-- Remove the matched order from the orderbook
	if matchedOrderId then
		pairData.orders[matchedOrderId] = nil
	end

	-- Send success response if any matches occurred
	if #matches > 0 then
		ao.send({
			Target = args.sender,
			Action = 'Order-Success',
			Tags = {
				OrderId = args.orderId,
				Status = 'Success',
				Handler = 'Create-Order',
				DominantToken = args.dominantToken,
				SwapToken = args.swapToken,
				Quantity = tostring(args.quantity),
				Price = args.price and tostring(args.price) or 'None',
				Message = 'ANT order executed immediately in Dutch auction!',
				['X-Group-ID'] = args.orderGroupId or 'None',
				OrderType = 'dutch',
			},
		})
	else
		-- No matches found for ANT token - return error
		utils.handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = 'No matching Dutch auction order found for immediate ANT trade',
			Quantity = args.quantity,
			TransferToken = args.dominantToken,
			OrderGroupId = args.orderGroupId,
		})
		return
	end
end

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

	local decreaseStep = dutch_auction.calculateDecreaseStep(args)

	if decreaseStep < 1 then
		return false, 'Decrease step must be at least 1. Price difference is too small for the given time intervals.'
	end

	return true
end

return dutch_auction
