package.path = package.path .. ';../src/?.lua'

local utils = require('utils')
local json = require('json')

-- Mock ao.send for testing
local sentMessages = {}
ao = {
	send = function(msg)
		table.insert(sentMessages, msg)
		print('Sent: ' .. msg.Action .. ' to ' .. msg.Target)
	end
}

-- Minimal Handlers mock for module loading only
Handlers = {
	add = function() end,
	utils = { hasMatchingTag = function() return function() return true end end }
}

-- Load the activity module to get access to the actual business logic functions
local activity = require('activity')

-- Helper function to reset test state
local function resetTestState()
	sentMessages = {}
	-- Reset all global state from activity module
	ExecutedOrders = {}
	ListedOrders = {}
	CancelledOrders = {}
	SalesByAddress = {}
	PurchasesByAddress = {}
	AuctionBids = {}
end

-- Helper function to create a mock message
local function createMockMessage(tags, data)
	return {
		From = 'test-sender',
		Tags = tags or {},
		Data = data or '',
		Timestamp = tags and tags.Timestamp or '1722535710966'
	}
end

-- Helper function to decode sent message data
local function decodeSentMessageData(index)
	if not sentMessages[index] or not sentMessages[index].Data then
		return nil
	end
	
	local success, decoded = pcall(function() return json.decode(sentMessages[index].Data) end)
	if success then
		return decoded
	end
	return nil
end

-- Helper function to create test orders
local function createTestOrder(id, dominantToken, swapToken, sender, receiver, quantity, price, timestamp)
	return {
		OrderId = id,
		DominantToken = dominantToken,
		SwapToken = swapToken,
		Sender = sender,
		Receiver = receiver,
		Quantity = quantity,
		Price = price,
		CreatedAt = timestamp,
		Timestamp = timestamp
	}
end

-- Test 1: Test getCompletedOrders function directly
utils.test('getCompletedOrders should return empty result when no orders exist',
	function()
		resetTestState()
		
		local msg = createMockMessage({
			Action = 'Get-Completed-Orders'
		})
		
		-- Call the function directly
		activity.getCompletedOrders(msg)
		
		local result = decodeSentMessageData(1)
		return result
	end,
	{
		items = {},
		limit = 100,
		totalItems = 0,
		sortBy = 'CreatedAt',
		sortOrder = 'desc',
		nextCursor = nil,
		hasMore = false
	}
)

-- Test 2: Test getCompletedOrders with executed orders
utils.test('getCompletedOrders should return executed orders with proper decoration',
	function()
		resetTestState()
		
		ExecutedOrders = {
			createTestOrder(
				'order-1',
				'token-1',
				'token-2',
				'sender-1',
				'receiver-1',
				'100',
				'500000000000',
				'1722535710966'
			)
		}
		
		local msg = createMockMessage({
			Action = 'Get-Completed-Orders'
		})
		
		-- Call the function directly
		activity.getCompletedOrders(msg)
		
		local result = decodeSentMessageData(1)
		return result
	end,
	{
		items = {
			{
				OrderId = 'order-1',
				DominantToken = 'token-1',
				SwapToken = 'token-2',
				Sender = 'sender-1',
				Receiver = 'receiver-1',
				Quantity = '100',
				Price = '500000000000',
				CreatedAt = 1722535710966,
				Timestamp = '1722535710966',
				Status = 'settled',
				Buyer = 'receiver-1'
			}
		},
		limit = 100,
		totalItems = 1,
		sortBy = 'CreatedAt',
		sortOrder = 'desc',
		nextCursor = nil,
		hasMore = false
	}
)

-- Test 3: Test getListedOrders function directly
utils.test('getListedOrders should return active orders',
	function()
		resetTestState()
		
		ListedOrders = {
			{
				OrderId = 'order-1',
				DominantToken = 'token-1',
				SwapToken = 'token-2',
				Sender = 'sender-1',
				Receiver = nil,
				Quantity = '100',
				Price = '500000000000',
				CreatedAt = '1722535710966',
				ExpirationTime = '1722535712000', -- Not expired
				OrderType = 'fixed'
			}
		}
		
		local msg = createMockMessage({
			Action = 'Get-Listed-Orders',
			Timestamp = '1722535711000' -- Current time before expiration
		})
		
		-- Call the function directly
		activity.getListedOrders(msg)
		
		local result = decodeSentMessageData(1)
		return result
	end,
	{
		items = {
			{
				OrderId = 'order-1',
				DominantToken = 'token-1',
				SwapToken = 'token-2',
				Sender = 'sender-1',
				Receiver = nil,
				Quantity = '100',
				Price = '500000000000',
				CreatedAt = 1722535710966,
				ExpirationTime = 1722535712000,
				OrderType = 'fixed',
				Status = 'active'
			}
		},
		limit = 100,
		totalItems = 1,
		sortBy = 'CreatedAt',
		sortOrder = 'desc',
		nextCursor = nil,
		hasMore = false
	}
)

-- Test 4: Test getOrderById function directly
utils.test('getOrderById should return specific order',
	function()
		resetTestState()
		
		ExecutedOrders = {
			createTestOrder(
				'order-1',
				'token-1',
				'token-2',
				'sender-1',
				'receiver-1',
				'100',
				'500000000000',
				'1722535710966'
			)
		}
		
		local msg = createMockMessage({
			Action = 'Get-Order-By-Id',
			OrderId = 'order-1'
		})
		
		-- Call the function directly
		activity.getOrderById(msg)
		
		local result = decodeSentMessageData(1)
		return result
	end,
	{
		OrderId = 'order-1',
		DominantToken = 'token-1',
		SwapToken = 'token-2',
		Sender = 'sender-1',
		Receiver = 'receiver-1',
		Quantity = '100',
		Price = '500000000000',
		CreatedAt = 1722535710966,
		Timestamp = '1722535710966',
		Status = 'settled',
		Buyer = 'receiver-1'
	}
)

-- Test 5: Test getOrderById with non-existent order
utils.test('getOrderById should return error for non-existent order',
	function()
		resetTestState()
		
		local msg = createMockMessage({
			Action = 'Get-Order-By-Id',
			OrderId = 'non-existent'
		})
		
		-- Call the function directly
		activity.getOrderById(msg)
		
		return {
			target = sentMessages[1].Target,
			action = sentMessages[1].Action,
			message = sentMessages[1].Message
		}
	end,
	{
		target = 'test-sender',
		action = 'Order-Not-Found',
		message = 'Order with ID non-existent not found'
	}
)

-- Test 6: Test getSalesByAddress function directly
utils.test('getSalesByAddress should return sales data',
	function()
		resetTestState()
		
		SalesByAddress = {
			['sender-1'] = 5,
			['sender-2'] = 3
		}
		
		local msg = createMockMessage({
			Action = 'Get-Sales-By-Address'
		})
		
		-- Call the function directly
		activity.getSalesByAddress(msg)
		
		local result = decodeSentMessageData(1)
		return result
	end,
	{
		SalesByAddress = {
			['sender-1'] = 5,
			['sender-2'] = 3
		}
	}
)

-- Test 7: Test getVolume function directly
utils.test('getVolume should calculate total volume correctly',
	function()
		resetTestState()
		
		ExecutedOrders = {
			createTestOrder('order-1', 'token-1', 'token-2', 'sender-1', 'receiver-1', '100', '500000000000', '1722535710966'),
			createTestOrder('order-2', 'token-3', 'token-4', 'sender-2', 'receiver-2', '200', '600000000000', '1722535710967')
		}
		
		local msg = createMockMessage({
			Action = 'Get-Volume'
		})
		
		-- Call the function directly
		activity.getVolume(msg)
		
		return {
			target = sentMessages[1].Target,
			action = sentMessages[1].Action,
			volume = sentMessages[1].Volume
		}
	end,
	{
		target = 'test-sender',
		action = 'Volume-Notice',
		volume = '0' -- Volume calculation depends on specific token logic
	}
)

-- Test 8: Test getMostTradedTokens function directly
utils.test('getMostTradedTokens should return sorted token volumes',
	function()
		resetTestState()
		
		ExecutedOrders = {
			createTestOrder('order-1', 'token-1', 'token-2', 'sender-1', 'receiver-1', '100', '500000000000', '1722535710966'),
			createTestOrder('order-2', 'token-1', 'token-3', 'sender-2', 'receiver-2', '200', '600000000000', '1722535710967'),
			createTestOrder('order-3', 'token-4', 'token-5', 'sender-3', 'receiver-3', '50', '700000000000', '1722535710968')
		}
		
		local msg = createMockMessage({
			Action = 'Get-Most-Traded-Tokens',
			Count = '2'
		})
		
		-- Call the function directly
		activity.getMostTradedTokens(msg)
		
		local result = decodeSentMessageData(1)
		return result
	end,
	{
		{
			Token = 'token-1',
			Volume = '300' -- 100 + 200
		},
		{
			Token = 'token-4',
			Volume = '50'
		}
	}
)

-- Test 9: Test helper function normalizeOrderTimestamps
utils.test('normalizeOrderTimestamps should convert timestamps to numbers',
	function()
		resetTestState()
		
		local order = {
			OrderId = 'order-1',
			CreatedAt = '1722535710966',
			ExpirationTime = '1722535712000',
			EndedAt = '1722535713000'
		}
		
		-- Call the helper function directly
		local result = activity._internal.normalizeOrderTimestamps(order)
		
		return result
	end,
	{
		OrderId = 'order-1',
		CreatedAt = 1722535710966,
		ExpirationTime = 1722535712000,
		EndedAt = 1722535713000
	}
)

-- Test 10: Test helper function computeListedStatus
utils.test('computeListedStatus should determine correct status for expired order',
	function()
		resetTestState()
		
		local order = {
			OrderId = 'order-1',
			ExpirationTime = '1722535710000', -- Expired
			OrderType = 'fixed'
		}
		
		local now = 1722535711000 -- Current time after expiration
		
		-- Call the helper function directly
		local status, endedAt = activity._internal.computeListedStatus(order, now)
		
		return {
			status = status,
			endedAt = endedAt
		}
	end,
	{
		status = 'expired',
		endedAt = 1722535710000
	}
)

-- Test 11: Test getOrderById with English auction settlement data
utils.test('getOrderById should return correct buyer address for settled English auction',
	function()
		resetTestState()
		
		-- Create a settled English auction order in ExecutedOrders
		local settledOrder = {
			OrderId = 'english-auction-settled',
			OrderType = 'english',
			DominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT
			SwapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO
			Sender = 'ant-seller',
			Receiver = 'bidder-winner', -- This should be the buyer
			Quantity = '1',
			Price = '2000000000000', -- Final winning bid amount
			CreatedAt = '1735689900000', -- Settlement timestamp
		}
		
		table.insert(ExecutedOrders, settledOrder)
		
		-- Set up auction bids data with settlement information
		AuctionBids = {
			['english-auction-settled'] = {
				Bids = {
					{
						Bidder = 'bidder-1',
						Amount = '1000000000000',
						Timestamp = '1735689700000',
						OrderId = 'english-auction-settled'
					},
					{
						Bidder = 'bidder-winner',
						Amount = '2000000000000',
						Timestamp = '1735689800000',
						OrderId = 'english-auction-settled'
					}
				},
				HighestBid = '2000000000000',
				HighestBidder = 'bidder-winner',
				Settlement = {
					OrderId = 'english-auction-settled',
					Winner = 'bidder-winner',
					WinningBid = '2000000000000',
					Quantity = '1',
					Timestamp = '1735689900000',
					DominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
					SwapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'
				}
			}
		}
		
		local msg = createMockMessage({
			Action = 'Get-Order-By-Id',
			OrderId = 'english-auction-settled'
		})
		
		-- Call the function directly
		activity.getOrderById(msg)
		
		local result = decodeSentMessageData(1)
		return result
	end,
	{
		OrderId = 'english-auction-settled',
		Status = 'settled',
		OrderType = 'english',
		CreatedAt = 1735689900000,
		ExpirationTime = nil,
		DominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
		SwapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8',
		Sender = 'ant-seller',
		Receiver = 'bidder-winner', -- This is the buyer
		Quantity = '1',
		Price = '2000000000000',
		Buyer = 'bidder-winner', -- This should match the highest bidder
		Bids = {
			{
				Bidder = 'bidder-1',
				Amount = '1000000000000',
				Timestamp = '1735689700000',
				OrderId = 'english-auction-settled'
			},
			{
				Bidder = 'bidder-winner',
				Amount = '2000000000000',
				Timestamp = '1735689800000',
				OrderId = 'english-auction-settled'
			}
		},
		HighestBid = '2000000000000',
		HighestBidder = 'bidder-winner',
		StartingPrice = '2000000000000',
		Settlement = {
			OrderId = 'english-auction-settled',
			Winner = 'bidder-winner',
			WinningBid = '2000000000000',
			Quantity = '1',
			Timestamp = '1735689900000',
			DominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
			SwapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'
		}
	}
)

print('Activity Functions Tests completed!')
utils.testSummary()
