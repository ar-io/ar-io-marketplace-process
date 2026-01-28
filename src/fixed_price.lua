local bint = require('.bint')(256)
local utils = require('utils')
local constants = require('constants')
-- ucm is required at runtime to avoid circular dependency

local fixed_price = {}
local ORDER_STATUSES = constants.ORDER_STATUSES
local ORDER_TYPES = constants.ORDER_TYPES

--- Prune an expired fixed price order
--- @param order Order The order to prune
--- @param pair Pair The pair containing the order
--- @param dominantToken TokenId The dominant token ID
--- @param swapToken TokenId The swap token ID
--- @param msg Message The message context for transfers
function fixed_price.pruneExpiredOrder(order, pair, dominantToken, swapToken, msg)
	-- Mark order as expired
	order.status = ORDER_STATUSES.EXPIRED
	order.endedAt = order.expirationTime
	-- Return ANT to the creator (fixed price orders are always ANT sales)
	local ucm = require('ucm')
	ucm.transfer(order.creator, order.quantity, order.token, msg)
	-- Remove the order from the orderbook and index
	local orderId = order.id
	pair.orders[orderId] = nil
	OrderIndex[orderId] = nil
	-- Prune the pair if it's now empty
	ucm.pruneEmptyPair(dominantToken, swapToken)
end

-- Helper function to update VWAP (Volume-Weighted Average Price) data
-- VWAP is a trading benchmark calculated as (sum of volume × price) / total volume
-- This provides a fair average price based on actual trades, useful for price discovery and analytics
--- @param pair Pair The pair object from orderbook (priceData will be injected with vwap, block, dominantToken, matchLogs)
--- @param matches table[] Array of match records containing quantity and price for each trade
--- @param args table Order arguments containing blockheight for recording when the data was captured
--- @param currentToken TokenId Current token ID (the dominant token in the trading pair)
--- @return number Sum of volumes across all matches
function fixed_price.updateVwapData(pair, matches, args, currentToken)
	if #matches == 0 then
		return 0
	end

	local sumVolumePrice, sumVolume = bint(0), bint(0)
	for _, match in ipairs(matches) do
		local volume = bint(match.quantity)
		local price = bint(match.price)
		sumVolumePrice = sumVolumePrice + (volume * price)
		sumVolume = sumVolume + volume
	end

	-- Calculate and store VWAP using integer division
	local vwap = sumVolumePrice // sumVolume
	---@diagnostic disable-next-line: inject-field
	pair.priceData = {
		vwap = tostring(vwap),
		block = tostring(args.blockheight),
		dominantToken = currentToken,
		matchLogs = matches,
	}

	return sumVolume
end
-- Helper function to handle ARIO token orders: we are selling ANT token, so we need to add to orderbook
--- Handle ARIO-dominant order (buying ANT with ARIO) for fixed price
--- @param args table Order arguments
--- @param validPair TokenId[] The validated pair [ARIO, ANT]
--- @param pair Pair The pair object from orderbook
function fixed_price.handleArioOrder(args, validPair, pair)
	-- NOTE: No balance deduction here - ANT comes via Credit-Notice
	-- This creates a fixed-price order selling ANT for ARIO

	-- Add to index FIRST for O(1) lookup (safer update order)
	OrderIndex[args.orderId] = {
		dominantToken = validPair[1],
		swapToken = validPair[2],
	}

	-- Then add the new order to the orderbook (buy now functionality)
	-- Use dictionary-style (lookup table) for efficient order management
	pair.orders[args.orderId] = {
		id = args.orderId,
		quantity = tostring(args.quantity),
		originalQuantity = tostring(args.quantity),
		creator = args.sender,
		token = args.dominantToken,
		dateCreated = args.createdAt,
		price = args.price and tostring(args.price),
		expirationTime = args.expirationTime,
		orderType = ORDER_TYPES.FIXED,
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
			Message = 'ARIO order added to orderbook for buy now!',
			['Order-Type'] = ORDER_TYPES.FIXED,
			['Expiration-Time'] = args.expirationTime and tostring(args.expirationTime),
		},
})
end

-- Helper function to handle ANT token orders: we are buying ANT token, so we need to match with an existing ANT sell order or fail
--- Handle ANT-dominant order (selling ANT for ARIO) for fixed price
--- @param args table Order arguments
--- @param _validPair TokenId[] The validated pair [ANT, ARIO]
--- @param pair Pair The pair object from orderbook
function fixed_price.handleAntOrder(args, _validPair, pair)
	local currentOrders = pair.orders
	local matches = {}
	local matchedOrderId = nil

	-- Attempt to match with existing orders for immediate trade
	for orderId, currentOrderEntry in pairs(currentOrders) do
		-- Check if order has expired
		if utils.isExpired(currentOrderEntry.expirationTime, args.createdAt) then
			-- Skip expired orders
			goto continue
		end

		-- Check if the order is a fixed order
		if currentOrderEntry.orderType ~= ORDER_TYPES.FIXED then
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
		fillAmount = bint(constants.QUANTITY.ANT_EXACT_AMOUNT) -- always 1 for ANT orders

		-- Validate we have a valid fill amount
		if fillAmount <= bint(0) then
			utils.refundAndNotifyError(args.msg, args.sender, 'No amount to fill', 'Order-Error')
			return
		end

			-- Apply fees and calculate final amounts based on required amount
			local calculatedSendAmount = utils.calculateSendAmount(requiredAmount)
			local calculatedFillAmount = utils.calculateFillAmount(fillAmount)

			-- Accrue fee based on the actual sent amount vs calculated
			local originalSendAmount = tostring(sentAmount)
			utils.sendFeeToTreasury(originalSendAmount, calculatedSendAmount, args.dominantToken, args.msg)

			-- Execute token transfers
			local ucm = require('ucm')
			ucm.executeTokenTransfers({
				sender = args.sender,
				dominantToken = args.dominantToken,
				swapToken = args.swapToken,
				originalSendAmount = originalSendAmount,
				msg = args.msg,
				currentOrderEntry = currentOrderEntry,
				calculatedSendAmount = calculatedSendAmount,
				calculatedFillAmount = calculatedFillAmount,
			})

		-- Refund any excess sent over the required amount
		if sentAmount > requiredAmount then
			local refundAmount = sentAmount - requiredAmount
			if utils.isArioToken(args.dominantToken) then
				-- ARIO: Refund to buyer's internal balance (was already deducted by balances.transfer)
				local balances = require('balances')
				balances.increaseBalance(args.sender, tostring(refundAmount))
			else
				-- ANT: Refund via external transfer
				ucm.transfer(args.sender, tostring(refundAmount), args.dominantToken, args.msg)
			end
		end

			-- Mark order as executed and update fields
			currentOrderEntry.status = ORDER_STATUSES.EXECUTED
			currentOrderEntry.endedAt = args.createdAt
			currentOrderEntry.sender = currentOrderEntry.creator
			currentOrderEntry.receiver = args.sender
			---@diagnostic disable-next-line: inject-field
			currentOrderEntry.buyer = args.sender
			---@diagnostic disable-next-line: inject-field
			currentOrderEntry.finalPrice = currentOrderEntry.price

				-- Record the match for response
				local match = {
					id = currentOrderEntry.id,
					quantity = calculatedFillAmount,
					price = tostring(currentOrderEntry.price),
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

	-- Update VWAP and get total volume
	local sumVolume = fixed_price.updateVwapData(pair, matches, args, args.dominantToken)

	-- Send success response if any matches occurred
	if sumVolume > 0 then
		utils.Send(args.msg, {
			Target = args.sender,
			Action = 'Order-Success',
			Tags = {
				['Order-Id'] = args.orderId,
				Status = 'Success',
				Handler = 'Create-Order',
				['Dominant-Token'] = args.dominantToken,
				['Swap-Token'] = args.swapToken,
				Quantity = tostring(sumVolume),
				Price = args.price and tostring(args.price) or 'None',
				Message = 'ANT order executed immediately!',
			},
		})
	else
		-- No matches found for ANT token - return error
		utils.refundAndNotifyError(
			args.msg,
			args.sender,
			'No matching orders found for immediate ANT trade - exact ARIO amount match required',
			'Order-Error'
		)
		return
	end
end

return fixed_price
