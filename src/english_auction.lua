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
		if bint(bidAmount) < bint(currentHighestBid) + minimumIncrement then
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

-- Helper function to return all losing bids at the end of an auction
-- Called during settlement to return bids to internal balances
function english_auction.returnLosingBids(order, winningBidder, msg)
	local balances = require('balances')
	
	if not order.bids then
		return
	end
	
	-- Return all bids except the winner's to internal balances
	for bidder, _ in pairs(order.bids) do
		if bidder ~= winningBidder then
			-- Get locked amount for this bidder
			local amount = balances.getOrderLockedBalance(order.id, bidder)
			
			if bint(amount) > 0 then
				-- Transfer bid back to bidder's available balance
				balances.unlockBalanceFromOrder(order.id, bidder, bidder, amount)
				
				-- Notify bidder
				utils.Send(msg, {
					Target = bidder,
					Action = 'Bid-Returned',
					Tags = {
						Status = 'Success',
						['Order-Id'] = order.id,
						Amount = amount,
						Message = 'Your bid has been returned as the auction ended',
					},
				})
			end
		end
	end
end

-- Helper function to handle ANT token orders: we are buying ANT token, so we need to place bids on English auctions
--- Handle ANT-dominant order (selling ANT for ARIO) for English auction
--- @param args EnglishAuctionBidArgs Bid arguments
function english_auction.handleAntOrder(args)
	-- Check if orderId is provided (required for bid identification)
	if not args.orderId then
		utils.refundAndError(args.msg, args.sender, 'Order ID is required for bidding', 'Order-Error')
		return
	end

	local currentOrders = args.pair.orders
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
		utils.refundAndError(args.msg, args.sender, 'English auction not found', 'Order-Error')
		return
	end

	-- Ensure bidding is allowed only on active orders
	if targetOrder.status ~= ORDER_STATUSES.ACTIVE then
		utils.refundAndError(args.msg, args.sender, 'Bidding allowed only on active orders', 'Order-Error')
		return
	end

	-- Check if auction has expired
	if not english_auction.isAuctionActive(targetOrder.expirationTime, args.createdAt) then
		utils.refundAndError(args.msg, args.sender, 'Auction has expired', 'Order-Error')
		return
	end

	-- Validate bid amount - use args.quantity for ARIO-dominant orders (buying ANT)
	local bidAmount = args.quantity -- The amount of ARIO tokens sent by the user

	-- Determine minimum starting price from the target order for first bid validation
	local minimumStartingPrice = targetOrder.price

	local isValidBid, bidError =
		english_auction.validateBidAmount(bidAmount, targetOrder.highestBid, minimumStartingPrice)

	if not isValidBid then
		utils.refundAndError(args.msg, args.sender, bidError, 'Validation-Error')
		return
	end

	-- Keep all bids until auction ends - losing bids returned during settlement
	
	-- Add bidder to order.bids for tracking
	if not targetOrder.bids then
		targetOrder.bids = {}
	end
	targetOrder.bids[args.sender] = true

	-- Update highest bid
	targetOrder.highestBid = tostring(bidAmount) -- Use the quantity sent by user
	targetOrder.highestBidder = args.sender

	-- Notify sender of successful bid placement
	utils.Send(args.msg, {
		Target = args.sender,
		Action = 'Bid-Success',
		Tags = {
			Status = 'Success',
			['Order-Id'] = targetOrder.id,
			Handler = 'Create-Order',
			['Dominant-Token'] = args.dominantToken,
			['Swap-Token'] = args.swapToken,
			['Bid-Amount'] = tostring(bidAmount), -- Use the quantity sent by user
			Message = 'Bid placed successfully on English auction!',
			['X-Group-ID'] = args.orderGroupId,
			['Order-Type'] = ORDER_TYPES.ENGLISH,
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
		local success = pcall(function()
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

	-- All bids now use internal balance (ARIO Credit-Notices for orders are blocked)
	local balances = require('balances')
	local feeAmount = winningBidAmount - calculatedSendAmount
	
	-- Transfer fee from winner's locked bid to treasury balance
	balances.unlockBalanceFromOrder(orderId, order.highestBidder, TREASURY_ADDRESS, tostring(feeAmount))
	
	-- Transfer remaining bid ARIO to seller's balance
	balances.unlockBalanceFromOrder(orderId, order.highestBidder, order.creator, tostring(calculatedSendAmount))
	
	-- Record the fee
	utils.accrueFee(tostring(feeAmount))
	
	-- Transfer ANT to winner via Credit-Notice with intent tracking (ANT came via Credit-Notice)
	local ucm = require('ucm')
	ucm.transferWithIntent(order.highestBidder, tostring(calculatedFillAmount), order.token, args.msg)

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

	-- Return all losing bids to internal balances
	english_auction.returnLosingBids(order, order.highestBidder, args.msg)

	-- Clean up auction data structure
	-- Clear the bids field after settlement
	order.bids = nil

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
			['Order-Id'] = orderId,
			['Winning-Bid'] = order.highestBid,
			Quantity = tostring(quantity),
			Message = args.sender and 'You won the English auction!' or 'You won the English auction (auto-settled)!',
			['Order-Type'] = ORDER_TYPES.ENGLISH,
		},
	})

	-- Notify settler if this was a manual settlement
	if args.sender then
		utils.Send(args.msg, {
			Target = args.sender,
			Action = 'Settlement-Success',
			Tags = {
				Status = 'Success',
				['Order-Id'] = orderId,
				Winner = order.highestBidder,
				['Winning-Bid'] = order.highestBid,
				Message = 'Auction settled successfully!',
				['X-Group-ID'] = args.orderGroupId or 'None',
			},
		})
	end
end

-- Helper function to handle ARIO token orders: we are selling ANT token, so we need to add to orderbook
--- Handle ANT-dominant order (selling ANT for ARIO) for English auction
--- Creates an auction where ANT is being sold for ARIO bids
--- ANT comes via Credit-Notice, ARIO bids come from internal balance
--- @param args table Order arguments
--- @param validPair string[] The validated pair [ANT, ARIO]
--- @param pair Pair The pair object from orderbook
function english_auction.handleArioOrder(args, validPair, pair)
	-- NOTE: No balance deduction here - ANT comes via Credit-Notice
	-- This creates an auction selling ANT for ARIO
	
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
	bids = {}, -- Track all bidders for this auction
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
			['Order-Id'] = args.orderId,
			Handler = 'Create-Order',
			['Dominant-Token'] = args.dominantToken,
			['Swap-Token'] = args.swapToken,
			Quantity = tostring(args.quantity),
			Price = args.price and tostring(args.price),
			Message = 'ARIO order added to orderbook for English auction!',
			['X-Group-ID'] = args.orderGroupId,
			['Order-Type'] = ORDER_TYPES.ENGLISH,
			['Expiration-Time'] = args.expirationTime,
		},
	})
end

--- Handler for bidding on English auctions using internal ARIO balance.
--- This handler supports both placing new bids and increasing existing bids on the same auction.
--- 
--- Delta Calculation (Contract-Side):
--- - Clients send their total desired bid amount, NOT the delta/increment.
--- - The contract calculates the delta internally by comparing with the user's existing bid.
--- - When a user places a new bid, the full bid amount is deducted from their available ARIO balance.
--- - When a user increases an existing bid, only the delta (difference between new and current bid) is deducted.
--- - This allows users to incrementally increase their bid without withdrawing and re-bidding.
--- 
--- Why Contract-Side Delta?
--- - Simplifies client-side interface: clients only need to know their desired total bid, not calculate deltas.
--- - Prevents race conditions: if a client sends multiple "increase bid" messages before they're processed,
---   the contract will correctly handle each one based on the current state, avoiding double-charges or errors.
--- - More robust: clients don't need to track intermediate bid states or handle failed/pending transactions.
--- 
--- Bid Storage:
--- - All bids are stored in EnglishAuctionBalances[orderId][bidder] and kept until auction settlement.
--- - Only the highest bid pointer (order.highestBid, order.highestBidder) is updated when outbid.
--- - Losing bids are returned to internal ARIO balance at settlement, not immediately when outbid.
--- 
--- Intended Use:
--- - Direct message to marketplace with Action: "Bid-On-English-Auction"
--- - Requires: Order-Id (auction to bid on), Bid-Amount (total desired bid, not delta)
--- - User must have sufficient available ARIO balance for the delta amount
--- 
--- @param msg Message The incoming message with Order-Id and Bid-Amount tags
--- @return string JSON response with status, action (Bid-Placed or Bid-Updated), and bid details
function english_auction.bidOnEnglishAuctionHandler(msg)
	local balances = require('balances')
	local json = require('json')
	local ucm = require('ucm')
	
	-- Parse parameters
	local orderId = msg.Tags['Order-Id']
	local bidAmount = msg.Tags['Bid-Amount']
	local bidder = msg.From
	
	assert(orderId, 'Order-Id is required')
	assert(bidAmount, 'Bid-Amount is required')
	assert(utils.checkValidAmount(bidAmount), 'Bid-Amount must be a positive integer')
	
	-- Find the order
	local order, pair = ucm.getOrderById(orderId)
	assert(order, 'Order not found')
	
	-- Validate it's an English auction
	assert(order.orderType == ORDER_TYPES.ENGLISH, 'Order is not an English auction')
	
	-- Validate auction is active
	assert(order.status == ORDER_STATUSES.ACTIVE, 'Auction is not active')
	
	-- Check if auction has expired
	assert(not utils.isExpired(order.expirationTime, msg.Timestamp), 'Auction has expired')
	
	-- Get current bid for this bidder from their locked balances
	local currentBidAmount = balances.getOrderLockedBalance(orderId, bidder)
	local isNewBid = currentBidAmount == '0'
	
	-- Calculate delta needed
	local newBidAmount = bint(bidAmount)
	local delta = newBidAmount - bint(currentBidAmount)
	
	assert(delta > bint(0), 'New bid must be higher than your current bid')
	
	-- Validate new bid amount meets requirements
	local minimumStartingPrice = order.price
	local isValidBid, bidError = english_auction.validateBidAmount(
		tostring(newBidAmount),
		order.highestBid,
		minimumStartingPrice
	)
	assert(isValidBid, bidError or 'Invalid bid amount')
	
	-- Check if bidder has sufficient balance for delta
	assert(
		balances.walletHasSufficientBalance(bidder, tostring(delta)),
		'Insufficient ARIO balance for bid. Required: ' .. tostring(delta)
	)
	
	-- Lock delta from available balance to this order
	balances.lockBalanceForOrder(orderId, bidder, tostring(delta))
	
	-- Add bidder to order.bids for tracking
	if not order.bids then
		order.bids = {}
	end
	order.bids[bidder] = true
	
	-- Keep all bids until auction ends - update highest bid pointer only
	-- Update highest bid if this is now the highest
	if not order.highestBid or newBidAmount > bint(order.highestBid) then
		order.highestBid = tostring(newBidAmount)
		order.highestBidder = bidder
	end
	
	-- Send success notice
	local action = isNewBid and constants.ACTIONS.BID_PLACED or constants.ACTIONS.BID_UPDATED
	return json.encode({
		Status = 'Success',
		Action = action,
		['Order-Id'] = orderId,
		['Bid-Amount'] = tostring(newBidAmount),
		['Delta-Amount'] = tostring(delta),
		['Is-Highest-Bid'] = (order.highestBidder == bidder),
		Message = isNewBid and 'Bid placed successfully' or 'Bid updated successfully',
	})
end

return english_auction
