local bint = require('.bint')(256)

local utils = require('utils')
local activity = require('activity')

-- Note: ucm is lazy-loaded within functions to avoid circular dependency
-- (ucm requires english_auction, and english_auction requires ucm)

local english_auction = {}

-- Initialize bid storage if it doesn't exist
if not EnglishAuctionBids then
	EnglishAuctionBids = {}
end

-- Helper function to get auction bids for a specific order
local function getAuctionBids(orderId)
	if not EnglishAuctionBids[orderId] then
		EnglishAuctionBids[orderId] = {
			Bids = {},
			HighestBid = nil,
			HighestBidder = nil,
		}
	end
	return EnglishAuctionBids[orderId]
end

-- Helper function to get existing auction bids (doesn't create if doesn't exist)
local function getExistingAuctionBids(orderId)
	return EnglishAuctionBids[orderId]
end

-- Helper function to validate auction is still active
local function isAuctionActive(expirationTime, currentTimestamp)
	if not expirationTime then
		return true
	end
	return bint(expirationTime) > bint(currentTimestamp)
end

local function validateBidAmount(bidAmount, currentHighestBid, minimumBid)
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
		local minimumIncrement = bint(1)
		if bint(bidAmount) <= bint(currentHighestBid) + minimumIncrement then
			return false, 'The next bid must be at least 1 ARIO higher than the current highest bid'
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
local function returnPreviousBid(orderId, previousBidder, previousAmount, biddingToken, msg)
	if previousBidder and previousAmount and biddingToken then
		-- Send refund transfer to previous bidder
		local ucm = require('ucm')
		ucm.transfer(msg, {
			Target = biddingToken,
			Action = 'Transfer',
			Tags = {
				Recipient = previousBidder,
				Quantity = tostring(previousAmount),
			},
		})

		-- Notify previous bidder of refund
		ao.send({
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
function english_auction.handleAntOrder(args, validPair)
	-- Check if orderId is provided (required for bid identification)
	if not args.orderId then
		utils.handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = 'Order ID is required for bidding',
			Quantity = args.quantity,
			TransferToken = args.dominantToken,
			OrderGroupId = args.orderGroupId,
		})
		return
	end

	-- Swap the pair to get [ANT, ARIO] since we're buying ANT with ARIO
	local antDominant = validPair[1] -- ANT token
	local arioSwap = validPair[2] -- ARIO token

	local pairData = Orderbook[antDominant] and Orderbook[antDominant][arioSwap]
	if not pairData then
		utils.handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = 'English auction not found',
			Quantity = args.quantity,
			TransferToken = args.dominantToken,
			OrderGroupId = args.orderGroupId,
		})
		return
	end

	local currentOrders = pairData.orders
	local targetOrder = nil

	-- Find the English auction order to bid on
	for _, order in pairs(currentOrders) do
		if order.orderType == 'english' and order.id == (args.requestedOrderId or args.orderId) then
			targetOrder = order
			break
		end
	end

	-- Check if the auction exists
	if not targetOrder then
		utils.handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = 'English auction not found',
			Quantity = args.quantity,
			TransferToken = args.dominantToken,
			OrderGroupId = args.orderGroupId,
		})
		return
	end

	-- Ensure bidding is allowed only on active orders (via internal Activity state)
	local activityData = activity.findOrderById(targetOrder.id, args.createdAt)
	print('activityData', activityData and activityData.Status or 'nil')
	if not activityData or activityData.Status ~= 'active' then
		utils.handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = 'Bidding allowed only on active orders',
			Quantity = args.quantity,
			TransferToken = args.dominantToken,
			OrderGroupId = args.orderGroupId,
		})
		return
	end

	-- Check if auction has expired
	if not isAuctionActive(targetOrder.expirationTime, args.createdAt) then
		utils.handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = 'Auction has expired',
			Quantity = args.quantity,
			TransferToken = args.dominantToken,
			OrderGroupId = args.orderGroupId,
		})
		return
	end

	-- Get existing auction bids for validation
	local targetAuctionId = args.requestedOrderId or args.orderId
	local existingBids = getExistingAuctionBids(targetAuctionId)

	-- Validate bid amount - use args.quantity for ARIO-dominant orders (buying ANT)
	local bidAmount = args.quantity -- The amount of ARIO tokens sent by the user

	-- Determine minimum starting price from the target order for first bid validation
	local minimumStartingPrice = targetOrder.price

	local isValidBid, bidError =
		validateBidAmount(bidAmount, existingBids and existingBids.HighestBid or nil, minimumStartingPrice)

	if not isValidBid then
		utils.handleError({
			Target = args.sender,
			Action = 'Validation-Error',
			Message = bidError,
			Quantity = args.quantity,
			TransferToken = args.dominantToken,
			OrderGroupId = args.orderGroupId,
		})
		return
	end

	-- Get auction bids (only after validation passes)
	local auctionBids = getAuctionBids(targetAuctionId)

	-- Return previous highest bid if it exists
	if auctionBids.HighestBidder and auctionBids.HighestBid then
		returnPreviousBid(
			targetAuctionId,
			auctionBids.HighestBidder,
			auctionBids.HighestBid,
			args.dominantToken,
			args.msg
		)
	end

	-- Store the new bid
	local newBid = {
		Bidder = args.sender,
		Amount = tostring(bidAmount), -- Use the quantity sent by user
		Timestamp = args.createdAt,
		OrderId = targetAuctionId,
	}

	table.insert(auctionBids.Bids, newBid)

	-- Update highest bid
	auctionBids.HighestBid = tostring(bidAmount) -- Use the quantity sent by user
	auctionBids.HighestBidder = args.sender

	-- Record bid internally
	activity.recordAuctionBid({
		OrderId = targetAuctionId,
		Bidder = args.sender,
		Amount = tostring(bidAmount),
		Timestamp = args.createdAt,
		DominantToken = args.dominantToken,
		SwapToken = args.swapToken,
		BidType = 'english_auction',
	})

	-- Notify sender of successful bid placement
	ao.send({
		Target = args.sender,
		Action = 'Bid-Success',
		Tags = {
			Status = 'Success',
			OrderId = targetAuctionId,
			Handler = 'Create-Order',
			DominantToken = args.dominantToken,
			SwapToken = args.swapToken,
			BidAmount = tostring(bidAmount), -- Use the quantity sent by user
			Message = 'Bid placed successfully on English auction!',
			['X-Group-ID'] = args.orderGroupId,
			OrderType = 'english',
		},
	})
end

-- Helper function to settle English auction
function english_auction.settleAuction(args)
	local orderId = args.orderId
	local auctionBids = getExistingAuctionBids(orderId)

	-- Check if auction has bids
	if not auctionBids or not auctionBids.HighestBidder then
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

	-- Find the auction order using the provided tokens
	local targetOrder = nil
	local antToken = args.dominantToken -- ANT is the dominant token in the orderbook
	local arioToken = args.swapToken -- ARIO is the swap token

	-- Look for order in nested map structure
	if Orderbook[antToken] and Orderbook[antToken][arioToken] then
		targetOrder = Orderbook[antToken][arioToken].orders[orderId]
	end

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

	-- Check if auction has expired
	if isAuctionActive(targetOrder.expirationTime, args.timestamp) then
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

	-- Execute the settlement
	-- For English auction settlement: seller gets ARIO tokens, buyer gets ANT tokens
	-- The Orderbook pair is [ANT_token_process, ARIO_token_process]
	-- We need validPair to be [ARIO_token_process, ANT_token_process] for correct transfers
	local validPair = { arioToken, antToken } -- Swap the order to get [ARIO, ANT]
	local winningBidAmount = bint(auctionBids.HighestBid)
	local quantity = bint(targetOrder.quantity)

	-- Calculate amounts after fees
	local calculatedSendAmount = utils.calculateSendAmount(winningBidAmount)
	local calculatedFillAmount = utils.calculateFillAmount(quantity)

	utils.sendFeeToTreasury(winningBidAmount, calculatedSendAmount, validPair[1], args.msg)

	-- Execute token transfers
	local ucm = require('ucm')
	ucm.executeTokenTransfers({
		sender = auctionBids.HighestBidder,
		quantity = tostring(quantity),
		price = auctionBids.HighestBid,
		originalSendAmount = winningBidAmount, -- to compute and accrue fee
		orderId = orderId,
		orderGroupId = args.orderGroupId,
		swapToken = targetOrder.token, -- ANT token process for the second transfer
		msg = args.msg, -- Pass msg context for intent tracking
	}, targetOrder, validPair, calculatedSendAmount, calculatedFillAmount)

	-- Record the settlement
	local settlement = {
		OrderId = orderId,
		Winner = auctionBids.HighestBidder,
		WinningBid = auctionBids.HighestBid,
		Quantity = tostring(quantity),
		Timestamp = args.timestamp,
		DominantToken = args.dominantToken,
		SwapToken = args.swapToken,
	}

	activity.recordAuctionSettlement(settlement)

	-- Also mark order as executed/completed internally so it appears in completed orders
	activity.recordExecutedOrder({
		Id = orderId,
		DominantToken = validPair[2],
		SwapToken = validPair[1],
		Sender = targetOrder.creator,
		Receiver = auctionBids.HighestBidder,
		Quantity = tostring(quantity),
		Price = tostring(auctionBids.HighestBid),
		CreatedAt = targetOrder.dateCreated,
		EndedAt = args.timestamp,
		ExecutionTime = args.timestamp,
	})

	-- Remove the auction from orderbook
	Orderbook[antToken][arioToken].orders[orderId] = nil

	-- Clear auction bids
	EnglishAuctionBids[orderId] = nil

	-- Notify winner
	ao.send({
		Target = auctionBids.HighestBidder,
		Action = 'Auction-Won',
		Tags = {
			Status = 'Success',
			OrderId = orderId,
			WinningBid = auctionBids.HighestBid,
			Quantity = tostring(quantity),
			Message = 'You won the English auction!',
			['X-Group-ID'] = args.orderGroupId,
		},
	})

	-- Notify settler
	ao.send({
		Target = args.sender,
		Action = 'Settlement-Success',
		Tags = {
			Status = 'Success',
			OrderId = orderId,
			Winner = auctionBids.HighestBidder,
			WinningBid = auctionBids.HighestBid,
			Message = 'Auction settled successfully!',
			['X-Group-ID'] = args.orderGroupId,
		},
	})
end

-- Helper function to handle ARIO token orders: we are selling ANT token, so we need to add to orderbook
function english_auction.handleArioOrder(args)
	-- Add the new order to the orderbook (buy now functionality)
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
		orderType = 'english',
	}

	-- Record listed order internally
	activity.recordListedOrder({
		Id = args.orderId,
		DominantToken = args.dominantToken,
		SwapToken = args.swapToken,
		Sender = args.sender,
		Receiver = nil,
		Quantity = tostring(args.quantity),
		Price = args.price and tostring(args.price),
		CreatedAt = args.createdAt,
		OrderType = 'english',
		ExpirationTime = args.expirationTime,
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
			Message = 'ARIO order added to orderbook for English auction!',
			['X-Group-ID'] = args.orderGroupId,
			OrderType = 'english',
			ExpirationTime = args.expirationTime,
		},
	})
end

return english_auction
