print('\n=== Loading english_auction module for testing ===')
local testGlobals = require('test_globals')
local ucm = require('ucm')
local english_auction = require('english_auction')
local json = require('json')
print('✓ english_auction module loaded')

describe('English Auction', function()
	print('\n--- Starting English Auction tests ---')

	-- Token IDs for testing
	local ANT_TOKEN = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'
	local ARIO_TOKEN = 'qNvAoz0TgcH7DMg8BCVn8jF32QH5L6T29VjHxhHqqGE'

	local transfers = {}
	local sentMessages = {}

	before_each(function()
		transfers = {}
		sentMessages = {}
		testGlobals.resetState()

		-- Disable treasury fees for these tests
		_G.TREASURY_ADDRESS = nil

		-- Mock ao.send to track transfers
		---@diagnostic disable-next-line: duplicate-set-field
		_G.ao.send = function(msg)
			-- Mock activity query response for status checks
			if msg.Action == 'Get-Order' then
				return {
					receive = function()
						return { Data = json.encode({ Status = 'active' }) }
					end,
				}
			end

			table.insert(sentMessages, msg)
			if msg.Action == 'Transfer' then
				local transfer = {
					action = msg.Action,
					quantity = msg.Tags.Quantity,
					recipient = msg.Tags.Recipient,
					target = msg.Target,
				}
				table.insert(transfers, transfer)
			end
		end
	end)

	describe('ANT sell order creation', function()
		it('should add ANT sell order to orderbook', function()
			ucm.createOrder({
				orderId = 'ant-sell-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
			swapToken = 'qNvAoz0TgcH7DMg8BCVn8jF32QH5L6T29VjHxhHqqGE',
			sender = 'ant-seller',
			quantity = '1',
			price = '500000000', -- 500 ARIO
			createdAt = 1735689600000,
			blockheight = 123456789,
			orderType = 'english',
		expirationTime = 1736035200000,
			msg = { Id = 'test-msg-1', Owner = 'ant-seller', Timestamp = 1735689600000, Data = '', Tags = { Quantity = '1' }, From = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
		})

			-- No transfers should occur (just adding to orderbook)
			assert.are.equal(0, #transfers)

			-- Validate orderbook structure (nested dictionary, Orders keyed by orderId!)
			assert.is_not_nil(Orderbook[ANT_TOKEN])
			assert.is_not_nil(Orderbook[ANT_TOKEN][ARIO_TOKEN])
			local order = Orderbook[ANT_TOKEN][ARIO_TOKEN].orders['ant-sell-order']
			assert.is_not_nil(order)
			assert.are.equal('ant-sell-order', order.id)
			assert.are.equal('english', order.orderType)
			assert.are.equal('500000000', order.price) -- 500 ARIO
		end)

		it('should allow order without expiration time', function()
			ucm.createOrder({
				orderId = 'ant-sell-order',
				dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
				swapToken = 'qNvAoz0TgcH7DMg8BCVn8jF32QH5L6T29VjHxhHqqGE',
		sender = 'ant-seller',
		quantity = '1',
		price = '500000000', -- 500 ARIO
		createdAt = 1735689600000,
		blockheight = 123456789,
		orderType = 'english',
		msg = { Id = 'test-msg-2', Owner = 'ant-seller', Timestamp = 1735689600000, Data = '', Tags = { Quantity = '1' }, From = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
		})

			assert.is_not_nil(Orderbook[ANT_TOKEN])
			assert.is_not_nil(Orderbook[ANT_TOKEN][ARIO_TOKEN])
			local order = Orderbook[ANT_TOKEN][ARIO_TOKEN].orders['ant-sell-order']
			assert.is_not_nil(order)
			assert.is_nil(order.expirationTime)
		end)

		it('should reject order with negative expiration time', function()
			local success = pcall(function()
				ucm.createOrder({
					orderId = 'ant-sell-order',
					dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
					swapToken = 'qNvAoz0TgcH7DMg8BCVn8jF32QH5L6T29VjHxhHqqGE',
				sender = 'ant-seller',
				quantity = '1',
				price = '500000000', -- 500 ARIO
				createdAt = 1735689600000,
				blockheight = 123456789,
				orderType = 'english',
			expirationTime = -1000,
			msg = { Id = 'test-msg-3', Owner = 'ant-seller', Timestamp = 1735689600000, Data = '', Tags = { Quantity = '1' }, From = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
			})
			end)

		-- After pair validation, refund is sent first, then error
		-- Note: refundAndNotifyError no longer throws, so pcall returns true (but messages are still sent)
		assert.is_true(success)
		assert.are.equal('Transfer', sentMessages[1].Action)
		assert.are.equal('Validation-Error', sentMessages[2].Action)
		end)

		it('should reject order with expired time', function()
			local success = pcall(function()
				ucm.createOrder({
					orderId = 'ant-sell-order',
					dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
					swapToken = 'qNvAoz0TgcH7DMg8BCVn8jF32QH5L6T29VjHxhHqqGE',
				sender = 'ant-seller',
				quantity = '1',
				price = '500000000', -- 500 ARIO
			createdAt = 1735689600000,
			msg = { Id = 'test-msg-4', Owner = 'ant-seller', Timestamp = 1735689600000, Data = '', Tags = { Quantity = '1' }, From = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
			blockheight = 123456789,
				orderType = 'english',
				expirationTime = 1735689500000, -- Before createdAt
				})
			end)

		-- After pair validation, refund is sent first, then error
		-- Note: refundAndNotifyError no longer throws, so pcall returns true (but messages are still sent)
		assert.is_true(success)
		assert.are.equal('Transfer', sentMessages[1].Action)
		assert.are.equal('Validation-Error', sentMessages[2].Action)
		end)

		it('should reject order without price', function()
			local success = pcall(function()
				ucm.createOrder({
					orderId = 'ant-sell-order',
					dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
			swapToken = 'qNvAoz0TgcH7DMg8BCVn8jF32QH5L6T29VjHxhHqqGE',
			sender = 'ant-seller',
			quantity = '1',
			createdAt = 1735689600000,
			blockheight = 123456789,
			orderType = 'english',
			msg = { Id = 'test-msg-5', Owner = 'ant-seller', Timestamp = 1735689600000, Data = '', Tags = { Quantity = '1' }, From = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
			})
		end)

		-- After pair validation, refund is sent first, then error
		-- Note: refundAndNotifyError no longer throws, so pcall returns true (but messages are still sent)
		assert.is_true(success)
		assert.are.equal('Transfer', sentMessages[1].Action)
		assert.are.equal('Validation-Error', sentMessages[2].Action)
		end)

		it('should reject order with negative price', function()
			local success = pcall(function()
				ucm.createOrder({
					orderId = 'ant-sell-order',
					dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
					swapToken = 'qNvAoz0TgcH7DMg8BCVn8jF32QH5L6T29VjHxhHqqGE',
			sender = 'ant-seller',
			quantity = '1',
			price = '-500',
			createdAt = 1735689600000,
			blockheight = 123456789,
			orderType = 'english',
			msg = { Id = 'test-msg-6', Owner = 'ant-seller', Timestamp = 1735689600000, Data = '', Tags = { Quantity = '1' }, From = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
			})
		end)

		-- After pair validation, refund is sent first, then error
		-- Note: refundAndNotifyError no longer throws, so pcall returns true (but messages are still sent)
		assert.is_true(success)
		assert.are.equal('Transfer', sentMessages[1].Action)
		assert.are.equal('Validation-Error', sentMessages[2].Action)
		end)

		it('should reject order with quantity not equal to 1', function()
			local success = pcall(function()
				ucm.createOrder({
					orderId = 'ant-sell-order',
					dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
					swapToken = 'qNvAoz0TgcH7DMg8BCVn8jF32QH5L6T29VjHxhHqqGE',
				sender = 'ant-seller',
				quantity = '2', -- Should be 1 for ANT
				price = '500000000', -- 500 ARIO
				createdAt = 1735689600000,
				blockheight = 123456789,
			orderType = 'english',
			msg = { Id = 'test-msg-7', Owner = 'ant-seller-2', Timestamp = 1735689601000, Data = '', Tags = { Quantity = '2' }, From = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
			})
			end)

		-- After pair validation, refund is sent first, then error
		-- Note: refundAndNotifyError no longer throws, so pcall returns true (but messages are still sent)
		assert.is_true(success)
		assert.are.equal('Transfer', sentMessages[1].Action)
		assert.are.equal('Validation-Error', sentMessages[2].Action)
		end)
	end)

	describe('Bidding validation', function()
		it('should reject bid with negative amount', function()
		-- Setup auction (Orders is a dictionary!)
		_G.Orderbook = {
			[ANT_TOKEN] = {
				[ARIO_TOKEN] = {
					pair = { ANT_TOKEN, ARIO_TOKEN },
					orders = {
						['auction-1'] = {
							id = 'auction-1',
							creator = 'seller-1',
							token = ANT_TOKEN,
							dominantToken = ANT_TOKEN,
							swapToken = ARIO_TOKEN,
							quantity = '1',
							originalQuantity = '1',
							price = '1000000000', -- 1000 ARIO
							orderType = 'english',
							dateCreated = 1735689600000,
							expirationTime = 1736035200000,
							status = 'active',
						},
					},
				},
			},
		}

			-- Add to OrderIndex for O(1) lookup
			_G.OrderIndex['auction-1'] = {
				dominantToken = ANT_TOKEN,
				swapToken = ARIO_TOKEN,
			}

		local success = pcall(function()
			ucm.createOrder({
				orderId = 'bid-1',
				dominantToken = 'qNvAoz0TgcH7DMg8BCVn8jF32QH5L6T29VjHxhHqqGE',
				swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
			sender = 'bidder-1',
			quantity = '-100', -- Negative
			createdAt = 1735689601000,
			blockheight = 123456790,
		orderType = 'english',
		requestedOrderId = 'auction-1',
		msg = { Id = 'test-msg-8', Owner = 'bidder-1', Timestamp = 1735689601000, Data = '', Tags = { Quantity = '-100' }, From = 'qNvAoz0TgcH7DMg8BCVn8jF32QH5L6T29VjHxhHqqGE' },
		})
		end)

		-- Negative quantity fails validation without refund
		-- Note: refundAndNotifyError no longer throws, so pcall returns true (but messages are still sent)
		assert.is_true(success)
		assert.are.equal('Validation-Error', sentMessages[1].Action)
		end)
	end)

	describe('Bidding logic', function()
	it('should accept first bid on active auction', function()
		-- Setup auction
		_G.Orderbook = {
			[ANT_TOKEN] = {
				[ARIO_TOKEN] = {
					pair = { ANT_TOKEN, ARIO_TOKEN },
					orders = {
						['auction-1'] = {
							id = 'auction-1',
							creator = 'seller-1',
							token = ANT_TOKEN,
							dominantToken = ANT_TOKEN,
							swapToken = ARIO_TOKEN,
							quantity = '1',
							originalQuantity = '1',
							price = '1000000000', -- 1000 ARIO
							orderType = 'english',
							dateCreated = 1735689600000,
							expirationTime = 1736035200000,
							status = 'active',
						},
					},
				},
			},
		}

		-- Add to OrderIndex for O(1) lookup
		_G.OrderIndex['auction-1'] = {
			dominantToken = ANT_TOKEN,
			swapToken = ARIO_TOKEN,
		}

		-- Setup bidder's ARIO balance
		_G.ARIOBalances['bidder-1'] = {
			balance = '2000000000', -- 2000 ARIO available
			orders = {},
		}

		-- Use bidOnEnglishAuctionHandler (correct handler for English auction bids)
		local bidMsg = {
			Id = 'test-msg-9',
			From = 'bidder-1',
			Owner = 'bidder-1',
			Timestamp = 1735689601000,
			Tags = {
				['Order-Id'] = 'auction-1',
				['Bid-Amount'] = '1100000000', -- 1100 ARIO
			},
		}

		english_auction.bidOnEnglishAuctionHandler(bidMsg)

		-- Bid should update auction highest bid in internal balances
		local auction = Orderbook[ANT_TOKEN][ARIO_TOKEN].orders['auction-1']
		local highestBid = english_auction.getHighestBid(auction.id)
		assert.is_not_nil(highestBid)
		---@diagnostic disable-next-line: need-check-nil
		assert.are.equal('bidder-1', highestBid.bidder)
		---@diagnostic disable-next-line: need-check-nil
		assert.are.equal('1100000000', highestBid.amount) -- 1100 ARIO
	-- Should be added to order.bids
	assert.is_not_nil(auction.bids)
	assert.is_true(auction.bids['bidder-1'])
	end)

	it('should accept bid that meets minimum 1 ARIO increment', function()
		-- Setup auction with existing bid
		_G.Orderbook = {
			[ANT_TOKEN] = {
				[ARIO_TOKEN] = {
					pair = { ANT_TOKEN, ARIO_TOKEN },
					orders = {
						['auction-1'] = {
							id = 'auction-1',
							creator = 'seller-1',
							token = ANT_TOKEN,
							dominantToken = ANT_TOKEN,
							swapToken = ARIO_TOKEN,
							quantity = '1',
							originalQuantity = '1',
							price = '1000000000', -- 1000 ARIO
							orderType = 'english',
							dateCreated = 1735689600000,
							expirationTime = 1736035200000,
							status = 'active',
						},
					},
				},
			},
		}

		-- Add to OrderIndex for O(1) lookup
		OrderIndex['auction-1'] = {
			dominantToken = ANT_TOKEN,
			swapToken = ARIO_TOKEN,
		}

		-- Setup first bidder's locked bid in ARIOBalances
		_G.ARIOBalances['bidder-1'] = {
			balance = '0',
			orders = {
				['auction-1'] = '1100000000', -- First bid: 1100 ARIO
			},
		}

		-- Setup second bidder's ARIO balance
		_G.ARIOBalances['bidder-2'] = {
			balance = '2000000000', -- 2000 ARIO available
			orders = {},
		}

		-- Place new bid using bidOnEnglishAuctionHandler
		local bidMsg = {
			Id = 'test-msg-10',
			From = 'bidder-2',
			Owner = 'bidder-2',
			Timestamp = 1735689602000,
			Tags = {
				['Order-Id'] = 'auction-1',
				['Bid-Amount'] = '1101000000', -- Exactly 1 ARIO more (1101 ARIO)
			},
		}

		english_auction.bidOnEnglishAuctionHandler(bidMsg)

		-- Bid should be accepted and become the new highest bid
		local auction = Orderbook[ANT_TOKEN][ARIO_TOKEN].orders['auction-1']
		local highestBid = english_auction.getHighestBid(auction.id)
		assert.is_not_nil(highestBid)
		---@diagnostic disable-next-line: need-check-nil
		assert.are.equal('bidder-2', highestBid.bidder)
		---@diagnostic disable-next-line: need-check-nil
		assert.are.equal('1101000000', highestBid.amount) -- 1101 ARIO
	end)
	end)

	describe('Helper functions', function()
		-- Note: getAuctionBids and getExistingAuctionBids have been removed
		-- Bids are now stored directly on order objects

		describe('isAuctionActive', function()
			it('should return true when expiration is nil', function()
				assert.is_true(english_auction.isAuctionActive(nil, 1000))
			end)

			it('should return true when current time is before expiration', function()
				assert.is_true(english_auction.isAuctionActive(2000, 1000))
				assert.is_true(english_auction.isAuctionActive('2000', '1000'))
			end)

			it('should return false when current time equals expiration', function()
				assert.is_false(english_auction.isAuctionActive(1000, 1000))
				assert.is_false(english_auction.isAuctionActive('1000', '1000'))
			end)

			it('should return false when current time is after expiration', function()
				assert.is_false(english_auction.isAuctionActive(1000, 2000))
				assert.is_false(english_auction.isAuctionActive('1000', '2000'))
			end)
		end)

		describe('validateBidAmount', function()
			it('should reject non-positive bid amounts', function()
				local isValid, err = english_auction.validateBidAmount('0', nil, nil)
				assert.is_false(isValid)
				assert.are.equal('Bid amount must be a positive integer', err)
			end)

			it('should reject bid equal to current highest bid', function()
				local isValid, err = english_auction.validateBidAmount('1000', '1000', nil)
				assert.is_false(isValid)
				assert.are.equal('Bids equal to or lower than the current bid are not allowed', err)
			end)

			it('should reject bid lower than current highest bid', function()
				local isValid, err = english_auction.validateBidAmount('999', '1000', nil)
				assert.is_false(isValid)
				assert.are.equal('Bids equal to or lower than the current bid are not allowed', err)
			end)

		it('should reject bid not meeting minimum increment', function()
			-- Current bid: 1000000 (1 ARIO), new bid: 1500000 (1.5 ARIO, only 0.5 ARIO increment)
			local isValid, err = english_auction.validateBidAmount('1500000', '1000000', nil)
			assert.is_false(isValid)
			assert.are.equal('The next bid must be at least 1 ARIO higher than the current highest bid', err)
		end)

		it('should accept bid meeting minimum increment', function()
			-- Current bid: 1000000 (1 ARIO), new bid: 2000000 (2 ARIO, exactly 1 ARIO increment)
			local isValid, err = english_auction.validateBidAmount('2000000', '1000000', nil)
			assert.is_true(isValid)
			assert.is_nil(err)
		end)

			it('should reject first bid below minimum starting price', function()
				local isValid, err = english_auction.validateBidAmount('999', nil, '1000')
				assert.is_false(isValid)
				assert.are.equal('Bid must be at least the minimum starting price', err)
			end)

			it('should accept first bid meeting minimum starting price', function()
				local isValid, err = english_auction.validateBidAmount('1000', nil, '1000')
				assert.is_true(isValid)
				assert.is_nil(err)
			end)

			it('should accept first bid when no minimum and no current bid', function()
				local isValid, err = english_auction.validateBidAmount('100', nil, nil)
				assert.is_true(isValid)
				assert.is_nil(err)
			end)
	end)

	describe('returnLosingBids', function()
		local returnBidMessages

		before_each(function()
		-- Track messages sent via utils.Send / ao.send
		returnBidMessages = {}
		---@diagnostic disable-next-line: duplicate-set-field
		_G.ao.send = function(msg)
				table.insert(returnBidMessages, msg)
			end

			-- Reset state
			testGlobals.resetState()
		end)

	it('should return all losing bids to internal balances', function()
		local orderId = 'auction-123'
		local winner = 'winner-addr'
		local loser1 = 'loser1-addr'
		local loser2 = 'loser2-addr'
		local msg = { Tags = {} }

		-- Setup order with bids field
		local order = {
			id = orderId,
			bids = {
				[winner] = true,
				[loser1] = true,
				[loser2] = true,
			}
		}

		-- Setup locked balances for each bidder
		ARIOBalances[winner] = {balance = '0', orders = {[orderId] = '3000'}}
		ARIOBalances[loser1] = {balance = '5000', orders = {[orderId] = '1000'}}
		ARIOBalances[loser2] = {balance = '6000', orders = {[orderId] = '2000'}}

		-- Return losing bids
		english_auction.returnLosingBids(order, winner, msg)

		-- Winner's locked bid should still be there
		assert.are.equal('3000', ARIOBalances[winner].orders[orderId])

		-- Losers' bids should be returned to their available balances
		assert.are.equal('6000', ARIOBalances[loser1].balance) -- 5000 + 1000
		assert.are.equal('8000', ARIOBalances[loser2].balance) -- 6000 + 2000
		-- Losers' locked balances should be cleared
		assert.is_nil(ARIOBalances[loser1].orders[orderId])
		assert.is_nil(ARIOBalances[loser2].orders[orderId])

		-- Should have sent 2 notifications (one per loser)
		assert.are.equal(2, #returnBidMessages)
	end)

	it('should handle auction with no bids', function()
		local msg = { Tags = {} }
		local order = {id = 'nonexistent-auction'} -- No bids field
		english_auction.returnLosingBids(order, 'winner', msg)
		-- Should not error, just return
		assert.are.equal(0, #returnBidMessages)
	end)
	end)
	end)

	describe('bidOnEnglishAuctionHandler', function()
		it('should place new bid using internal balance', function()
			-- Setup: Create an English auction
			ucm.createOrder({
				orderId = 'auction-balance-1',
				dominantToken = ANT_TOKEN,
			swapToken = ARIO_TOKEN,
			sender = 'seller-123',
			quantity = '1',
			price = '1000000', -- 1 ARIO minimum
			createdAt = 1000000,
			blockheight = 123456,
			orderType = 'english',
			expirationTime = 2000000,
			msg = { Id = 'test-msg-ant', Owner = 'ant-seller', Timestamp = 1735689600000, Data = '', Tags = {}, From = ANT_TOKEN },
			})

			-- Setup bidder balance
			ARIOBalances['bidder-1'] = {balance = '10000000000', orders = {}} -- 10,000 ARIO

			local msg = {
				From = 'bidder-1',
				Timestamp = 1500000,
				Tags = {
					['Order-Id'] = 'auction-balance-1',
					['Bid-Amount'] = '2000000', -- 2 ARIO
				},
			}

			local result = english_auction.bidOnEnglishAuctionHandler(msg)
			local resultData = json.decode(result)

			assert.are.equal('Success', resultData.Status)
			assert.are.equal('2000000', resultData['Bid-Amount']) -- 2 ARIO
			assert.is_true(resultData['Is-Highest-Bid'])

		-- Balance should be reduced
		assert.are.equal('9998000000', ARIOBalances['bidder-1'].balance) -- 10,000 - 2 = 9,998 ARIO

	-- Order should have bid
	---@type Order
	local order = Orderbook[ANT_TOKEN][ARIO_TOKEN].orders['auction-balance-1']
	local highestBid = english_auction.getHighestBid(order.id)
	assert.is_not_nil(highestBid)
	---@diagnostic disable-next-line: need-check-nil
	assert.are.equal('2000000', highestBid.amount) -- 2 ARIO
	---@diagnostic disable-next-line: need-check-nil
	assert.are.equal('bidder-1', highestBid.bidder)
		end)

	it('should increase existing bid with delta', function()
		-- Setup: Create auction and place initial bid
		ucm.createOrder({
			orderId = 'auction-delta-1',
			dominantToken = ANT_TOKEN,
			swapToken = ARIO_TOKEN,
			sender = 'seller-123',
			quantity = '1',
			price = '1000000', -- 1 ARIO minimum
			createdAt = 1000000,
			blockheight = 123456,
			orderType = 'english',
			expirationTime = 3000000,
			msg = { Id = 'test-msg-ant', Owner = 'ant-seller', Timestamp = 1735689600000, Data = '', Tags = {}, From = ANT_TOKEN },
		})

			ARIOBalances['bidder-2'] = {balance = '20000000000', orders = {}} -- 20,000 ARIO

			-- Place initial bid
			local msg1 = {
				From = 'bidder-2',
				Timestamp = 1500000,
				Tags = {
					['Order-Id'] = 'auction-delta-1',
					['Bid-Amount'] = '2000000', -- 2 ARIO
				},
			}
		english_auction.bidOnEnglishAuctionHandler(msg1)

		assert.are.equal('19998000000', ARIOBalances['bidder-2'].balance) -- 20,000 - 2 = 19,998 ARIO

		-- Increase bid to 5 ARIO (delta of 3 ARIO)
			local msg2 = {
				From = 'bidder-2',
				Timestamp = 1600000,
				Tags = {
					['Order-Id'] = 'auction-delta-1',
					['Bid-Amount'] = '5000000', -- 5 ARIO
				},
			}
			local result = english_auction.bidOnEnglishAuctionHandler(msg2)
			local resultData = json.decode(result)

			assert.are.equal('Success', resultData.Status)
			assert.are.equal('5000000', resultData['Bid-Amount']) -- 5 ARIO
			assert.are.equal('3000000', resultData['Delta-Amount']) -- 3 ARIO delta

		-- Balance should be reduced by delta only
		assert.are.equal('19995000000', ARIOBalances['bidder-2'].balance) -- 19,998 - 3 = 19,995 ARIO

	-- Order should have updated bid
	---@type Order
	local order = Orderbook[ANT_TOKEN][ARIO_TOKEN].orders['auction-delta-1']
	local highestBid = english_auction.getHighestBid(order.id)
	assert.is_not_nil(highestBid)
	---@diagnostic disable-next-line: need-check-nil
	assert.are.equal('5000000', highestBid.amount) -- 5 ARIO
		end)

	it('should keep all bids until auction ends (no immediate returns)', function()
		-- Setup auction
		ucm.createOrder({
			orderId = 'auction-refund-1',
			dominantToken = ANT_TOKEN,
			swapToken = ARIO_TOKEN,
			sender = 'seller-123',
			quantity = '1',
			price = '1000000', -- 1 ARIO minimum
			createdAt = 1000000,
			blockheight = 123456,
			orderType = 'english',
			expirationTime = 3000000,
			msg = { Id = 'test-msg-ant', Owner = 'ant-seller', Timestamp = 1735689600000, Data = '', Tags = {}, From = ANT_TOKEN },
		})

			ARIOBalances['bidder-a'] = {balance = '10000000000', orders = {}}
			ARIOBalances['bidder-b'] = {balance = '10000000000', orders = {}}

			-- Bidder A places bid
			local msg1 = {
				From = 'bidder-a',
				Timestamp = 1500000,
				Tags = {
					['Order-Id'] = 'auction-refund-1',
					['Bid-Amount'] = '2000000', -- 2 ARIO
				},
		}
		english_auction.bidOnEnglishAuctionHandler(msg1)
		assert.are.equal('9998000000', ARIOBalances['bidder-a'].balance) -- 10,000 - 2 = 9,998 ARIO

		-- Bidder B outbids with higher amount (must be at least 1 ARIO more)
			local msg2 = {
				From = 'bidder-b',
				Timestamp = 1600000,
				Tags = {
					['Order-Id'] = 'auction-refund-1',
					['Bid-Amount'] = '4000000', -- 4 ARIO (Exceeds minimum increment)
				},
			}
			english_auction.bidOnEnglishAuctionHandler(msg2)

		-- Bidder A's available balance should be reduced (bid kept locked until auction ends)
		assert.are.equal('9998000000', ARIOBalances['bidder-a'].balance) -- 10,000 - 2 = 9,998 ARIO
		-- Bidder B should have reduced available balance
		assert.are.equal('9996000000', ARIOBalances['bidder-b'].balance) -- 10,000 - 4 = 9,996 ARIO

		-- Both bids should be in locked balances
		assert.are.equal('2000000', ARIOBalances['bidder-a'].orders['auction-refund-1']) -- 2 ARIO
		assert.are.equal('4000000', ARIOBalances['bidder-b'].orders['auction-refund-1']) -- 4 ARIO

	-- Order should have bidder B as highest
	---@type Order
	local order = Orderbook[ANT_TOKEN][ARIO_TOKEN].orders['auction-refund-1']
	local highestBid = english_auction.getHighestBid(order.id)
	assert.is_not_nil(highestBid)
	---@diagnostic disable-next-line: need-check-nil
	assert.are.equal('4000000', highestBid.amount) -- 4 ARIO
	---@diagnostic disable-next-line: need-check-nil
	assert.are.equal('bidder-b', highestBid.bidder)
		end)

	it('should fail with insufficient balance', function()
		ucm.createOrder({
			orderId = 'auction-poor-1',
			dominantToken = ANT_TOKEN,
			swapToken = ARIO_TOKEN,
			sender = 'seller-123',
			quantity = '1',
			price = '1000000', -- 1 ARIO minimum
			createdAt = 1000000,
			blockheight = 123456,
			orderType = 'english',
			expirationTime = 3000000,
			msg = { Id = 'test-msg-ant', Owner = 'ant-seller', Timestamp = 1735689600000, Data = '', Tags = {}, From = ANT_TOKEN },
		})

			ARIOBalances['poor-bidder'] = {balance = '500000', orders = {}} -- Only 0.5 ARIO

			local msg = {
				From = 'poor-bidder',
				Timestamp = 1500000,
				Tags = {
					['Order-Id'] = 'auction-poor-1',
					['Bid-Amount'] = '2000000', -- 2 ARIO -- Need 2 ARIO
				},
			}

			local success, err = pcall(function()
				english_auction.bidOnEnglishAuctionHandler(msg)
			end)

		assert.is_false(success)
		assert(err)
		assert.is_not_nil(err:match('Insufficient ARIO balance'))
		end)

		it('should fail if order does not exist', function()
			ARIOBalances['bidder-x'] = {balance = '10000000000', orders = {}}

			local msg = {
				From = 'bidder-x',
				Timestamp = 1500000,
				Tags = {
					['Order-Id'] = 'nonexistent-order',
					['Bid-Amount'] = '2000000', -- 2 ARIO
				},
			}

			local success, err = pcall(function()
				english_auction.bidOnEnglishAuctionHandler(msg)
			end)

		assert.is_false(success)
		assert(err)
		assert.is_not_nil(err:match('Order not found'))
		end)

	it('should fail if auction has expired', function()
		ucm.createOrder({
			orderId = 'auction-expired',
			dominantToken = ANT_TOKEN,
			swapToken = ARIO_TOKEN,
			sender = 'seller-123',
			quantity = '1',
			price = '1000000', -- 1 ARIO minimum
			createdAt = 1000000,
			blockheight = 123456,
			orderType = 'english',
			expirationTime = 2000000, -- Expires at 2000000
			msg = { Id = 'test-msg-ant', Owner = 'ant-seller', Timestamp = 1735689600000, Data = '', Tags = {}, From = ANT_TOKEN },
		})

			ARIOBalances['late-bidder'] = {balance = '10000000000', orders = {}}

			local msg = {
				From = 'late-bidder',
				Timestamp = 2500000, -- After expiration
				Tags = {
					['Order-Id'] = 'auction-expired',
					['Bid-Amount'] = '2000000', -- 2 ARIO
				},
			}

			local success, err = pcall(function()
				english_auction.bidOnEnglishAuctionHandler(msg)
			end)

		assert.is_false(success)
		assert(err)
		assert.is_not_nil(err:match('expired'))
		end)

	it('should fail if bid does not meet minimum increment', function()
		ucm.createOrder({
			orderId = 'auction-increment',
			dominantToken = ANT_TOKEN,
			swapToken = ARIO_TOKEN,
			sender = 'seller-123',
			quantity = '1',
			price = '1000000', -- 1 ARIO minimum starting price
			createdAt = 1000000,
			blockheight = 123456,
			orderType = 'english',
			expirationTime = 3000000,
			msg = { Id = 'test-msg-ant', Owner = 'ant-seller', Timestamp = 1735689600000, Data = '', Tags = {}, From = ANT_TOKEN },
		})

			ARIOBalances['bidder-1'] = {balance = '10000000', orders = {}} -- 10 ARIO
			ARIOBalances['bidder-2'] = {balance = '10000000', orders = {}} -- 10 ARIO

			-- First bid
			local msg1 = {
				From = 'bidder-1',
				Timestamp = 1500000,
				Tags = {
					['Order-Id'] = 'auction-increment',
					['Bid-Amount'] = '2000000', -- 2 ARIO
				},
			}
			english_auction.bidOnEnglishAuctionHandler(msg1)

			-- Try to bid only 0.5 ARIO more (need at least 1 ARIO increment)
			local msg2 = {
				From = 'bidder-2',
				Timestamp = 1600000,
				Tags = {
					['Order-Id'] = 'auction-increment',
					['Bid-Amount'] = '2500000', -- Only 0.5 ARIO more
				},
			}

			local success, err = pcall(function()
				english_auction.bidOnEnglishAuctionHandler(msg2)
			end)

		assert.is_false(success)
		assert(err)
		assert.is_not_nil(err:match('at least 1 ARIO higher'))
		end)
	end)

	describe('English Auction Cancellation', function()
	it('should allow cancellation of English auction without bids', function()
		-- Setup: Create an English auction with no bids
		ucm.createOrder({
			orderId = 'auction-no-bids',
			dominantToken = ANT_TOKEN,
			swapToken = ARIO_TOKEN,
			sender = 'seller-123',
			quantity = '1',
			price = '1000000', -- 1 ARIO minimum
			createdAt = 1000000,
			blockheight = 123456,
			orderType = 'english',
			expirationTime = 3000000,
			msg = { Id = 'test-msg-ant', Owner = 'ant-seller', Timestamp = 1735689600000, Data = '', Tags = {}, From = ANT_TOKEN },
		})

		-- Verify auction exists
		---@type Order
		local order = Orderbook[ANT_TOKEN][ARIO_TOKEN].orders['auction-no-bids']
		assert.is_not_nil(order)
		assert.are.equal('active', order.status)
		local highestBid = english_auction.getHighestBid(order.id)
		assert.is_nil(highestBid)

			-- Cancel the auction
			local cancelMsg = testGlobals.mockMsg({
				From = 'seller-123',
				Timestamp = 1500000,
				Tags = {
					['Order-Id'] = 'auction-no-bids',
				},
			})

			local result = ucm.cancelOrderHandler(cancelMsg)
			local resultData = json.decode(result)

			assert.are.equal('Success', resultData.Status)
			assert.are.equal('Order cancelled', resultData.Message)

			-- Verify order is removed from orderbook
			assert.is_nil(Orderbook[ANT_TOKEN])
			assert.is_nil(OrderIndex['auction-no-bids'])
		end)

	it('should block cancellation of English auction with bids', function()
		-- Setup: Create an English auction
		ucm.createOrder({
			orderId = 'auction-with-bids',
			dominantToken = ANT_TOKEN,
			swapToken = ARIO_TOKEN,
			sender = 'seller-456',
			quantity = '1',
			price = '1000000', -- 1 ARIO minimum
			createdAt = 1000000,
			blockheight = 123456,
			orderType = 'english',
			expirationTime = 3000000,
			msg = { Id = 'test-msg-ant', Owner = 'ant-seller', Timestamp = 1735689600000, Data = '', Tags = {}, From = ANT_TOKEN },
		})

			-- Place a bid on the auction
			ARIOBalances['bidder-xyz'] = {balance = '10000000000', orders = {}}
			local bidMsg = {
				From = 'bidder-xyz',
				Timestamp = 1500000,
				Tags = {
					['Order-Id'] = 'auction-with-bids',
					['Bid-Amount'] = '2000000', -- 2 ARIO
				},
			}
			english_auction.bidOnEnglishAuctionHandler(bidMsg)

	-- Verify auction has a bid
	---@type Order
	local order = Orderbook[ANT_TOKEN][ARIO_TOKEN].orders['auction-with-bids']
	local highestBid = english_auction.getHighestBid(order.id)
	assert.is_not_nil(highestBid)
	---@diagnostic disable-next-line: need-check-nil
	assert.are.equal('bidder-xyz', highestBid.bidder)

			-- Try to cancel the auction (should fail)
			local cancelMsg = testGlobals.mockMsg({
				From = 'seller-456',
				Timestamp = 1600000,
				Tags = {
					['Order-Id'] = 'auction-with-bids',
				},
			})

			local success, err = pcall(function()
				ucm.cancelOrderHandler(cancelMsg)
			end)

		assert.is_false(success)
		assert(err)
		assert.is_not_nil(err:match('cannot cancel an English auction that has bids'))

			-- Verify order still exists
			assert.is_not_nil(Orderbook[ANT_TOKEN][ARIO_TOKEN].orders['auction-with-bids'])
		end)

	it('should only allow creator to cancel English auction', function()
		-- Setup: Create an English auction
		ucm.createOrder({
			orderId = 'auction-creator-test',
			dominantToken = ANT_TOKEN,
			swapToken = ARIO_TOKEN,
			sender = 'creator-789',
			quantity = '1',
			price = '1000000', -- 1 ARIO minimum
			createdAt = 1000000,
			blockheight = 123456,
			orderType = 'english',
			expirationTime = 3000000,
			msg = { Id = 'test-msg-ant', Owner = 'ant-seller', Timestamp = 1735689600000, Data = '', Tags = {}, From = ANT_TOKEN },
		})

			-- Try to cancel from different user (should fail)
			local cancelMsg = testGlobals.mockMsg({
				From = 'not-the-creator',
				Timestamp = 1500000,
				Tags = {
					['Order-Id'] = 'auction-creator-test',
				},
			})

			local success, err = pcall(function()
				ucm.cancelOrderHandler(cancelMsg)
			end)

		assert.is_false(success)
		assert(err)
		assert.is_not_nil(err:match('Unauthorized'))

			-- Verify order still exists
			assert.is_not_nil(Orderbook[ANT_TOKEN][ARIO_TOKEN].orders['auction-creator-test'])
		end)

	it('should return ANT to creator when cancelling auction without bids', function()
		-- Setup: Create an English auction
		ucm.createOrder({
			orderId = 'auction-return-ant',
			dominantToken = ANT_TOKEN,
			swapToken = ARIO_TOKEN,
			sender = 'seller-999',
			quantity = '1',
			price = '1000000', -- 1 ARIO minimum
			createdAt = 1000000,
			blockheight = 123456,
			orderType = 'english',
			expirationTime = 3000000,
			msg = { Id = 'test-msg-ant', Owner = 'ant-seller', Timestamp = 1735689600000, Data = '', Tags = {}, From = ANT_TOKEN },
		})

		local transfersSent = {}
		---@diagnostic disable-next-line: duplicate-set-field
		_G.ao.send = function(msg)
			if msg.Action == 'Transfer' then
				table.insert(transfersSent, msg)
			end
		end

			-- Cancel the auction
			local cancelMsg = testGlobals.mockMsg({
				From = 'seller-999',
				Timestamp = 1500000,
				Tags = {
					['Order-Id'] = 'auction-return-ant',
					['X-Intent-Id'] = '12345',
				},
			})

			ucm.cancelOrderHandler(cancelMsg)

			-- Verify Transfer message was sent back to creator
			assert.are.equal(1, #transfersSent)
			assert.are.equal('Transfer', transfersSent[1].Action)
			assert.are.equal(ANT_TOKEN, transfersSent[1].Target)
			assert.are.equal('seller-999', transfersSent[1].Tags.Recipient)
			assert.are.equal('1', transfersSent[1].Tags.Quantity)
		end)
	end)

	describe('pruneExpiredAuction', function()
		it('should mark auction without bids as expired and remove from orderbook', function()
			_G.OrderIndex = {}
			_G.Orderbook = {
				[ANT_TOKEN] = {
					[ARIO_TOKEN] = {
						pair = { ANT_TOKEN, ARIO_TOKEN },
						orders = {
							['english-123'] = {
								id = 'english-123',
								status = 'active',
								expirationTime = 2000,
								token = ANT_TOKEN,
								creator = 'test-creator',
								quantity = '1',
								originalQuantity = '1',
								dateCreated = 1000,
								dominantToken = ANT_TOKEN,
								swapToken = ARIO_TOKEN,
								orderType = 'english',
								price = '1000',
							},
						},
					},
				},
			}

			_G.OrderIndex['english-123'] = {
				dominantToken = ANT_TOKEN,
				swapToken = ARIO_TOKEN,
			}

			local order = _G.Orderbook[ANT_TOKEN][ARIO_TOKEN].orders['english-123']
			local pair = _G.Orderbook[ANT_TOKEN][ARIO_TOKEN]

			english_auction.pruneExpiredAuction(order, pair, ANT_TOKEN, ARIO_TOKEN, 3000, { Id = 'prune-msg', From = 'test', Owner = 'test', Timestamp = 3000, Tags = {}, Data = '' })

			-- Order should be marked as expired
			assert.are.equal('expired', order.status)
			assert.are.equal(2000, order.endedAt)

			-- Order should be removed from index
			assert.is_nil(_G.OrderIndex['english-123'])
			-- Pair should be pruned (empty) - this means the order was removed
			assert.is_nil(_G.Orderbook[ANT_TOKEN])
		end)
	end)
end)
