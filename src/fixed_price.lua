local bint = require('.bint')(256)
local utils = require('utils')
local constants = require('constants')
local ucm = require('ucm')

local fixed_price = {}
local ORDER_STATUSES = constants.ORDER_STATUSES
local ORDER_TYPES = constants.ORDER_TYPES

--- Prune an expired fixed price order
--- @param order table The order to prune
function fixed_price.pruneExpiredOrder(order)
	order.status = ORDER_STATUSES.EXPIRED
	order.endedAt = order.expirationTime
end

-- Helper function to update VWAP data
<<<<<<< Updated upstream
local function updateVwapData(dominantToken, swapToken, matches, args, currentToken)
=======
--- @param pair Pair The pair object from orderbook
--- @param matches table[] Array of match records
--- @param args table Order arguments
--- @param currentToken string Current token ID
--- @return number Sum of volumes
function fixed_price.updateVwapData(pair, matches, args, currentToken)
>>>>>>> Stashed changes
	local sumVolumePrice, sumVolume = 0, 0
	if #matches > 0 then
		for _, match in ipairs(matches) do
			local volume = bint(match.quantity)
			local price = bint(match.price)
			sumVolumePrice = sumVolumePrice + (volume * price)
			sumVolume = sumVolume + volume
		end

		-- Calculate and store VWAP
		local vwap = sumVolumePrice / sumVolume
<<<<<<< Updated upstream
		Orderbook[dominantToken][swapToken].PriceData = {
=======
		pair.PriceData = {
>>>>>>> Stashed changes
			Vwap = tostring(math.floor(vwap)),
			Block = tostring(args.blockheight),
			DominantToken = currentToken,
			MatchLogs = matches,
		}
	end

	return sumVolume
end
-- Helper function to handle ARIO token orders: we are selling ANT token, so we need to add to orderbook
<<<<<<< Updated upstream
function fixed_price.handleArioOrder(args)
	-- Add the new order to the orderbook (buy now functionality)
	local orderId = args.orderId
	Orderbook[args.dominantToken][args.swapToken].orders[orderId] = {
=======
--- Handle ARIO-dominant order (buying ANT with ARIO) for fixed price
--- @param args table Order arguments
--- @param validPair string[] The validated pair [ARIO, ANT]
--- @param pair Pair The pair object from orderbook
function fixed_price.handleArioOrder(args, validPair, pair)
	-- Add the new order to the orderbook (buy now functionality)
	-- Use dictionary-style (lookup table) for efficient order management
	pair.orders[args.orderId] = {
>>>>>>> Stashed changes
		id = args.orderId,
		quantity = tostring(args.quantity),
		originalQuantity = tostring(args.quantity),
		creator = args.sender,
		token = args.dominantToken,
		dateCreated = args.createdAt,
		price = args.price and tostring(args.price),
		expirationTime = args.expirationTime,
<<<<<<< Updated upstream
		orderType = 'fixed',
=======
		orderType = ORDER_TYPES.FIXED,
		status = ORDER_STATUSES.ACTIVE,
		dominantToken = validPair[1],
		swapToken = validPair[2],
>>>>>>> Stashed changes
	}

	-- Add to index for O(1) lookup
	OrderIndex[args.orderId] = {
		dominantToken = validPair[1],
		swapToken = validPair[2],
	}

	-- Schedule pruning for expiration if needed
	if args.expirationTime then
		ucm.scheduleNextOrderbookPruning(args.expirationTime)
	end

	-- Notify sender of successful order creation
	utils.Send(args.msg, {
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
			Message = 'ARIO order added to orderbook for buy now!',
			['X-Group-ID'] = args.orderGroupId,
			OrderType = ORDER_TYPES.FIXED,
			ExpirationTime = args.expirationTime,
		},
	})
end

-- Helper function to handle ANT token orders: we are buying ANT token, so we need to match with an existing ANT sell order or fail
<<<<<<< Updated upstream
function fixed_price.handleAntOrder(args, validPair)
	-- Swap the pair to get [ANT, ARIO] since we're buying ANT with ARIO
	local antDominant = validPair[1]  -- ANT token (swap to become dominant)
	local arioSwap = validPair[2]  -- ARIO token (swap to become swap token)
	
	local pairData = Orderbook[antDominant] and Orderbook[antDominant][arioSwap]
	if not pairData then
		utils.handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = 'No matching orders found for immediate ANT trade - exact ARIO amount match required',
			Quantity = args.quantity,
			TransferToken = args.dominantToken,
			OrderGroupId = args.orderGroupId,
		})
		return
	end
	
	local currentOrders = pairData.orders
=======
--- Handle ANT-dominant order (selling ANT for ARIO) for fixed price
--- @param args table Order arguments
--- @param validPair string[] The validated pair [ANT, ARIO]
--- @param pair Pair The pair object from orderbook
function fixed_price.handleAntOrder(args, validPair, pair)
	local currentOrders = pair.orders
>>>>>>> Stashed changes
	local matches = {}
	local matchedOrderId = nil

	-- Attempt to match with existing orders for immediate trade
	for orderId, currentOrderEntry in pairs(currentOrders) do
		-- Check if order has expired
<<<<<<< Updated upstream
		if currentOrderEntry.expirationTime and bint(currentOrderEntry.expirationTime) < bint(args.createdAt) then
=======
		if utils.isExpired(currentOrderEntry.expirationTime, args.createdAt) then
>>>>>>> Stashed changes
			-- Skip expired orders
			goto continue
		end

		-- Check if the order is a fixed order
<<<<<<< Updated upstream
		if currentOrderEntry.orderType ~= 'fixed' then
=======
		if currentOrderEntry.orderType ~= ORDER_TYPES.FIXED then
>>>>>>> Stashed changes
			goto continue
		end

		-- Check if this is the specific order we're looking for
		if currentOrderEntry.id ~= args.requestedOrderId then
			goto continue
		end

		-- Check if we can still fill and the order has remaining quantity
		if bint(args.quantity) > bint(0) and bint(currentOrderEntry.quantity) > bint(0) then
			-- For ANT tokens, only allow complete trades - no partial amounts
			local fillAmount

			-- Accept sent amount >= listed price; refund any excess
			local requiredAmount = bint(currentOrderEntry.price)
			local sentAmount = bint(args.quantity)
			if sentAmount >= requiredAmount then
				-- User buys 1 ANT token
				fillAmount = bint(1) -- always 1 for ANT orders

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

				-- Apply fees and calculate final amounts based on required amount
				local calculatedSendAmount = utils.calculateSendAmount(requiredAmount)
				local calculatedFillAmount = utils.calculateFillAmount(fillAmount)

				-- Accrue fee based on the actual sent amount vs calculated
				local originalSendAmount = tostring(sentAmount)
				utils.sendFeeToTreasury(originalSendAmount, calculatedSendAmount, args.dominantToken, args.msg)

				-- Execute token transfers
				ucm.executeTokenTransfers(
					args,
					currentOrderEntry,
					validPair,
					calculatedSendAmount,
					calculatedFillAmount
				)

				-- Refund any excess ARIO sent over the required amount
				if sentAmount > requiredAmount then
					local refundAmount = sentAmount - requiredAmount
					ucm.transfer(args.msg, {
						Target = args.dominantToken,
						Action = 'Transfer',
						Tags = {
							Recipient = args.sender,
							Quantity = tostring(refundAmount),
						},
					})
				end

				-- Mark order as executed and update fields
				currentOrderEntry.status = ORDER_STATUSES.EXECUTED
				currentOrderEntry.endedAt = args.createdAt
				currentOrderEntry.sender = currentOrderEntry.creator
				currentOrderEntry.receiver = args.sender
				currentOrderEntry.buyer = args.sender
				currentOrderEntry.finalPrice = currentOrderEntry.price

				-- Record the match for response
				local match = {
					Id = currentOrderEntry.id,
					Quantity = calculatedFillAmount,
					Price = tostring(currentOrderEntry.price),
				}
				table.insert(matches, match)

				-- Mark the order ID for removal
				matchedOrderId = orderId
				break -- Only match with one order, no partial matching
			end
			-- If ARIO amount is less than price, skip and continue searching
		end

		::continue::
	end

	-- Remove the matched order from the orderbook
	if matchedOrderId then
<<<<<<< Updated upstream
		pairData.orders[matchedOrderId] = nil
	end

	-- Update VWAP and get total volume
	local sumVolume = updateVwapData(antDominant, arioSwap, matches, args, args.dominantToken)
=======
		pair.orders[matchedOrderId] = nil
		-- Remove from index
		OrderIndex[matchedOrderId] = nil
	end

	-- Update VWAP and get total volume
	local sumVolume = fixed_price.updateVwapData(pair, matches, args, args.dominantToken)
>>>>>>> Stashed changes

	-- Send success response if any matches occurred
	if sumVolume > 0 then
		utils.Send(args.msg, {
			Target = args.sender,
			Action = 'Order-Success',
			Tags = {
				OrderId = args.orderId,
				Status = 'Success',
				Handler = 'Create-Order',
				DominantToken = args.dominantToken,
				SwapToken = args.swapToken,
				Quantity = tostring(sumVolume),
				Price = args.price and tostring(args.price) or 'None',
				Message = 'ANT order executed immediately!',
				['X-Group-ID'] = args.orderGroupId or 'None',
			},
		})
	else
		-- No matches found for ANT token - return error
		utils.handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = 'No matching orders found for immediate ANT trade - exact ARIO amount match required',
			Quantity = args.quantity,
			TransferToken = args.dominantToken,
			OrderGroupId = args.orderGroupId,
		})
		return
	end
end

return fixed_price
