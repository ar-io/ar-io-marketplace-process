local bint = require('.bint')(256)

local utils = require('utils')
local constants = require('constants')
--- Note: ucm is lazy-loaded within functions to avoid circular dependency
--- (ucm requires english_auction, and english_auction requires ucm)

local english_auction = {}
local ORDER_STATUSES = constants.ORDER_STATUSES
local ORDER_TYPES = constants.ORDER_TYPES

-- Helper function to validate auction is still active
function english_auction.isAuctionActive(expirationTime, currentTimestamp)
	return not utils.isExpired(expirationTime, currentTimestamp)
end

function english_auction.validateBidAmount(bidAmount, currentHighestBid, minimumBid)
	if not utils.checkValidAmount(bidAmount) then
		return false, 'Bid amount must be a positive integer'
	end

	-- If there is a current highest bid, enforce bidding rules
	if currentHighestBid then
		-- General Bidding Rules: Each new bid must be higher than the current highest bid
		if bint(bidAmount) <= bint(currentHighestBid) then
			return false, 'Bids equal to or lower than the current bid are not allowed'
		end

		-- Minimum Bid Increment: The next bid must be at least 1 ARIO higher than the current highest bid
		local minimumIncrement = bint(constants.AUCTION.MINIMUM_BID_INCREMENT)
		if bint(bidAmount) <= bint(currentHighestBid) + minimumIncrement then
			return false,
				'The next bid must be at least '
					.. constants.AUCTION.MINIMUM_BID_INCREMENT
					.. ' ARIO higher than the current highest bid'
		end
	else
		-- No current bids yet: enforce minimum starting price if provided
		if minimumBid and bint(bidAmount) < bint(minimumBid) then
			return false, 'Bid must be at least the minimum starting price'
		end
	end

	return true, nil
end

-- Helper function to return previous highest bid
function english_auction.returnPreviousBid(orderId, previousBidder, previousAmount, biddingToken, msg)
	if previousBidder and previousAmount and biddingToken then
		-- Send refund transfer to previous bidder
		local ucm = require('ucm')
		ucm.transfer(previousBidder, tostring(previousAmount), biddingToken, msg)

		-- Notify previous bidder of refund
		utils.Send(msg, {
			Target = previousBidder,
			Action = 'Bid-Returned',
			Tags = {
				Status = 'Success',
				OrderId = orderId,
				Amount = tostring(previousAmount),
				Message = 'Your previous bid has been returned as a higher bid was placed',
			},
		})
	end
end

-- Helper function to handle ANT token orders: we are buying ANT token, so we need to place bids on English auctions
--- Handle ANT-dominant order (selling ANT for ARIO) for English auction
--- @param args table Order arguments
--- @param _ string[] The validated pair [ANT, ARIO]
--- @param pair Pair The pair object from orderbook
function english_auction.handleAntOrder(args, _, pair)
	-- Check if orderId is provided (required for bid identification)
	if not args.orderId then
		utils.handleError({
			target = args.sender,
			action = 'Order-Error',
			message = 'Order ID is required for bidding',
			quantity = args.quantity,
			transferToken = args.dominantToken,
			orderGroupId = args.orderGroupId,
		})
		return
	end

	local currentOrders = pair.orders
	local targetOrder = nil

	-- Find the English auction order to bid on
	for _, order in pairs(currentOrders) do
		if order.orderType == ORDER_TYPES.ENGLISH and order.id == (args.requestedOrderId or args.orderId) then
			targetOrder = order
			break
		end
	end

	-- Check if the auction exists
	if not targetOrder then
		utils.handleError({
			target = args.sender,
			action = 'Order-Error',
			message = 'English auction not found',
			quantity = args.quantity,
			transferToken = args.dominantToken,
			orderGroupId = args.orderGroupId,
		})
		return
	end

	-- Ensure bidding is allowed only on active orders
	if targetOrder.status ~= ORDER_STATUSES.ACTIVE then
		utils.handleError({
			target = args.sender,
			action = 'Order-Error',
			message = 'Bidding allowed only on active orders',
			quantity = args.quantity,
			transferToken = args.dominantToken,
			orderGroupId = args.orderGroupId,
		})
		return
	end

	-- Check if auction has expired
	if not english_auction.isAuctionActive(targetOrder.expirationTime, args.createdAt) then
		utils.handleError({
			target = args.sender,
			action = 'Order-Error',
			message = 'Auction has expired',
			quantity = args.quantity,
			transferToken = args.dominantToken,
			orderGroupId = args.orderGroupId,
		})
		return
	end

	-- Validate bid amount - use args.quantity for ARIO-dominant orders (buying ANT)
	local bidAmount = args.quantity -- The amount of ARIO tokens sent by the user

	-- Determine minimum starting price from the target order for first bid validation
	local minimumStartingPrice = targetOrder.price

	local isValidBid, bidError =
		english_auction.validateBidAmount(bidAmount, targetOrder.highestBid, minimumStartingPrice)

	if not isValidBid then
		utils.handleError({
			target = args.sender,
			action = 'Validation-Error',
			message = bidError,
			quantity = args.quantity,
			transferToken = args.dominantToken,
			orderGroupId = args.orderGroupId,
		})
		return
	end

	-- Initialize bids if needed
	if not targetOrder.bids then
		targetOrder.bids = {}
	end

	-- Return previous highest bid if it exists
	if targetOrder.highestBidder and targetOrder.highestBid then
		english_auction.returnPreviousBid(
			targetOrder.id,
			targetOrder.highestBidder,
			targetOrder.highestBid,
			args.dominantToken,
			args.msg
		)
	end

	-- Store the new bid (using dictionary-style with user address as key)
	local newBid = {
		bidder = args.sender,
		amount = tostring(bidAmount), -- Use the quantity sent by user
		timestamp = args.createdAt,
		orderId = targetOrder.id,
	}

	targetOrder.bids[args.sender] = newBid

	-- Update highest bid
	targetOrder.highestBid = tostring(bidAmount) -- Use the quantity sent by user
	targetOrder.highestBidder = args.sender

	-- Notify sender of successful bid placement
	utils.Send(args.msg, {
		Target = args.sender,
		Action = 'Bid-Success',
		Tags = {
			Status = 'Success',
			OrderId = targetOrder.id,
			Handler = 'Create-Order',
			DominantToken = args.dominantToken,
			SwapToken = args.swapToken,
			BidAmount = tostring(bidAmount), -- Use the quantity sent by user
			Message = 'Bid placed successfully on English auction!',
			['X-Group-ID'] = args.orderGroupId,
			OrderType = ORDER_TYPES.ENGLISH,
		},
	})
end

--- Prune an expired English auction (auto-settle if it has bids)
--- @param order table The order to prune
--- @param pair table The pair containing the order
--- @param dominantToken string The dominant token ID
--- @param swapToken string The swap token ID
--- @param now number The current timestamp
--- @param msg table The message context
function english_auction.pruneExpiredAuction(order, pair, dominantToken, swapToken, now, msg)
	if order.highestBidder then
		-- English auction with bids - auto-settle it
		-- Wrap in pcall to handle any settlement errors gracefully
		local success, err = pcall(function()
			english_auction.settleAuction({
				order = order,
				pair = pair,
				dominantToken = dominantToken,
				swapToken = swapToken,
				timestamp = now,
				msg = msg,
				sender = nil, -- Auto-settlement has no sender
			})
		end)

		if not success then
			-- If settlement fails, mark as ready for manual settlement
			order.status = constants.ORDER_STATUSES.READY_FOR_SETTLEMENT
		end
	else
		-- English auction without bids - mark as expired
		order.status = constants.ORDER_STATUSES.EXPIRED
		order.endedAt = order.expirationTime
	end
end

--- Settle an English auction with the winning bid
--- Optimized to accept pre-fetched order and pair data
--- @param args table Settlement arguments with order, pair, timestamp, msg, and optional sender
function english_auction.settleAuction(args)
	local order = args.order
	local pair = args.pair
	local orderId = order.id

	-- Execute the settlement
	-- For English auction settlement: seller gets ARIO tokens, buyer gets ANT tokens
	-- The Orderbook pair is [ANT_token_process, ARIO_token_process]
	-- We need validPair to be [ARIO_token_process, ANT_token_process] for correct transfers
	local validPair = { pair.Pair[2], pair.Pair[1] } -- Swap the order to get [ARIO, ANT]
	local winningBidAmount = bint(order.highestBid)
	local quantity = bint(order.quantity)

	-- Calculate amounts after fees
	local calculatedSendAmount = utils.calculateSendAmount(winningBidAmount)
	local calculatedFillAmount = utils.calculateFillAmount(quantity)

	utils.sendFeeToTreasury(winningBidAmount, calculatedSendAmount, validPair[1], args.msg)

	-- Execute token transfers
	local ucm = require('ucm')
	ucm.executeTokenTransfers({
		sender = order.highestBidder,
		quantity = tostring(quantity),
		price = order.highestBid,
		originalSendAmount = winningBidAmount,
		orderId = orderId,
		orderGroupId = 'auto-settlement',
		swapToken = order.token, -- ANT token process
		msg = args.msg,
	}, order, validPair, calculatedSendAmount, calculatedFillAmount)

	-- Record the settlement directly on the order
	order.settlement = {
		winner = order.highestBidder,
		winningBid = order.highestBid,
		quantity = tostring(quantity),
		timestamp = args.timestamp,
	}

	-- Mark order as executed and update fields
	order.status = ORDER_STATUSES.EXECUTED
	order.endedAt = args.timestamp
	order.sender = order.creator
	order.receiver = order.highestBidder
	order.buyer = order.highestBidder
	order.price = tostring(order.highestBid)
	order.finalPrice = tostring(order.highestBid)

	-- Remove the auction from orderbook
	pair.orders[orderId] = nil
	-- Remove from index
	OrderIndex[orderId] = nil

	-- Notify winner
	utils.Send(args.msg, {
		Target = order.highestBidder,
		Action = 'Auction-Won',
		Tags = {
			Status = 'Success',
			OrderId = orderId,
			WinningBid = order.highestBid,
			Quantity = tostring(quantity),
			Message = args.sender and 'You won the English auction!' or 'You won the English auction (auto-settled)!',
			OrderType = ORDER_TYPES.ENGLISH,
		},
	})

	-- Notify settler if this was a manual settlement
	if args.sender then
		utils.Send(args.msg, {
			Target = args.sender,
			Action = 'Settlement-Success',
			Tags = {
				Status = 'Success',
				OrderId = orderId,
				Winner = order.highestBidder,
				WinningBid = order.highestBid,
				Message = 'Auction settled successfully!',
				['X-Group-ID'] = args.orderGroupId or 'None',
			},
		})
	end
end

-- Helper function to handle ARIO token orders: we are selling ANT token, so we need to add to orderbook
--- Handle ARIO-dominant order (buying ANT with ARIO) for English auction
--- @param args table Order arguments
--- @param validPair string[] The validated pair [ARIO, ANT]
--- @param pair Pair The pair object from orderbook
function english_auction.handleArioOrder(args, validPair, pair)
	-- Add the new order to the orderbook (buy now functionality)
	pair.orders[args.orderId] = {
		id = args.orderId,
		quantity = tostring(args.quantity),
		originalQuantity = tostring(args.quantity),
		creator = args.sender,
		token = args.dominantToken,
		dateCreated = args.createdAt,
		price = args.price and tostring(args.price),
		expirationTime = args.expirationTime,
		orderType = ORDER_TYPES.ENGLISH,
		status = ORDER_STATUSES.ACTIVE,
		-- Initialize English auction specific fields
		bids = {},
		highestBid = nil,
		highestBidder = nil,
		dominantToken = validPair[1],
		swapToken = validPair[2],
	}

	-- Add to index for O(1) lookup
	OrderIndex[args.orderId] = {
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
			OrderId = args.orderId,
			Handler = 'Create-Order',
			DominantToken = args.dominantToken,
			SwapToken = args.swapToken,
			Quantity = tostring(args.quantity),
			Price = args.price and tostring(args.price),
			Message = 'ARIO order added to orderbook for English auction!',
			['X-Group-ID'] = args.orderGroupId,
			OrderType = ORDER_TYPES.ENGLISH,
			ExpirationTime = args.expirationTime,
		},
	})
end

return english_auction
