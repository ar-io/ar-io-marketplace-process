print('\n=== Loading english_auction module for testing ===')
local testGlobals = require('test_globals')
local ucm = require('ucm')
local json = require('json')
print('✓ english_auction module loaded')

describe('English Auction', function()
	print('\n--- Starting English Auction tests ---')

	-- Token IDs for testing
	local ANT_TOKEN = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'
	local ARIO_TOKEN = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA'

	local transfers = {}
	local sentMessages = {}

	before_each(function()
		transfers = {}
		sentMessages = {}
		testGlobals.resetState()

		-- Mock ao.send to track transfers
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
				swapToken = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA',
				sender = 'ant-seller',
				quantity = 1,
				price = '500000000000',
				createdAt = '1735689600000',
				blockheight = '123456789',
				orderType = 'english',
				orderGroupId = 'test-group',
				expirationTime = '1736035200000',
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
			assert.are.equal('500000000000', order.price)
		end)

		it('should allow order without expiration time', function()
			ucm.createOrder({
				orderId = 'ant-sell-order',
				dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
				swapToken = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA',
				sender = 'ant-seller',
				quantity = 1,
				price = '500000000000',
				createdAt = '1735689600000',
				blockheight = '123456789',
				orderType = 'english',
				orderGroupId = 'test-group',
			})

			assert.is_not_nil(Orderbook[ANT_TOKEN])
			assert.is_not_nil(Orderbook[ANT_TOKEN][ARIO_TOKEN])
			local order = Orderbook[ANT_TOKEN][ARIO_TOKEN].orders['ant-sell-order']
			assert.is_not_nil(order)
			assert.is_nil(order.expirationTime)
		end)

		it('should reject order with negative expiration time', function()
			ucm.createOrder({
				orderId = 'ant-sell-order',
				dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
				swapToken = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA',
				sender = 'ant-seller',
				quantity = 1,
				price = '500000000000',
				createdAt = '1735689600000',
				blockheight = '123456789',
				orderType = 'english',
				expirationTime = '-1000',
			})

			-- After pair validation, refund is sent first, then error
			assert.are.equal('Transfer', sentMessages[1].Action)
			assert.are.equal('Validation-Error', sentMessages[2].Action)
		end)

		it('should reject order with expired time', function()
			ucm.createOrder({
				orderId = 'ant-sell-order',
				dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
				swapToken = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA',
				sender = 'ant-seller',
				quantity = 1,
				price = '500000000000',
				createdAt = '1735689600000',
				blockheight = '123456789',
				orderType = 'english',
				expirationTime = '1735689500000', -- Before createdAt
			})

			-- After pair validation, refund is sent first, then error
			assert.are.equal('Transfer', sentMessages[1].Action)
			assert.are.equal('Validation-Error', sentMessages[2].Action)
		end)

		it('should reject order without price', function()
			ucm.createOrder({
				orderId = 'ant-sell-order',
				dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
				swapToken = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA',
				sender = 'ant-seller',
				quantity = 1,
				createdAt = '1735689600000',
				blockheight = '123456789',
				orderType = 'english',
			})

			-- After pair validation, refund is sent first, then error
			assert.are.equal('Transfer', sentMessages[1].Action)
			assert.are.equal('Validation-Error', sentMessages[2].Action)
		end)

		it('should reject order with negative price', function()
			ucm.createOrder({
				orderId = 'ant-sell-order',
				dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
				swapToken = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA',
				sender = 'ant-seller',
				quantity = 1,
				price = '-500',
				createdAt = '1735689600000',
				blockheight = '123456789',
				orderType = 'english',
			})

			-- After pair validation, refund is sent first, then error
			assert.are.equal('Transfer', sentMessages[1].Action)
			assert.are.equal('Validation-Error', sentMessages[2].Action)
		end)

		it('should reject order with quantity not equal to 1', function()
			ucm.createOrder({
				orderId = 'ant-sell-order',
				dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
				swapToken = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA',
				sender = 'ant-seller',
				quantity = 2, -- Should be 1 for ANT
				price = '500000000000',
				createdAt = '1735689600000',
				blockheight = '123456789',
				orderType = 'english',
			})

			-- After pair validation, refund is sent first, then error
			assert.are.equal('Transfer', sentMessages[1].Action)
			assert.are.equal('Validation-Error', sentMessages[2].Action)
		end)
	end)

	describe('Bidding validation', function()
		it('should reject bid with negative amount', function()
			-- Setup auction (Orders is a dictionary!)
			Orderbook = {
				[ANT_TOKEN] = {
					[ARIO_TOKEN] = {
						pair = { ANT_TOKEN, ARIO_TOKEN },
						orders = {
							['auction-1'] = {
								id = 'auction-1',
								creator = 'seller-1',
								token = ANT_TOKEN,
								quantity = '1',
								price = '1000000000000',
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

			ucm.createOrder({
				orderId = 'bid-1',
				dominantToken = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA',
				swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
				sender = 'bidder-1',
				quantity = '-100', -- Negative
				createdAt = '1735689601000',
				blockheight = '123456790',
				requestedOrderId = 'auction-1',
			})

			-- Negative quantity fails validation without refund
			assert.are.equal('Validation-Error', sentMessages[1].Action)
		end)

		it('should reject bid without orderId', function()
			ucm.createOrder({
				orderId = 'bid-1',
				dominantToken = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA',
				swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
				sender = 'bidder-1',
				quantity = '1100000000000',
				createdAt = '1735689601000',
				blockheight = '123456790',
				-- requestedOrderId missing
			})

			-- After pair validation, refund is sent first, then error
			assert.are.equal('Transfer', sentMessages[1].Action)
			assert.are.equal('Validation-Error', sentMessages[2].Action)
		end)
	end)

	describe('Bidding logic', function()
		it('should accept first bid on active auction', function()
			-- Setup auction
			Orderbook = {
				[ANT_TOKEN] = {
					[ARIO_TOKEN] = {
						pair = { ANT_TOKEN, ARIO_TOKEN },
						orders = {
							['auction-1'] = {
								id = 'auction-1',
								creator = 'seller-1',
								token = ANT_TOKEN,
								quantity = '1',
								originalQuantity = '1',
								price = '1000000000000',
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

			ucm.createOrder({
				orderId = 'bid-1',
				dominantToken = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA',
				swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
				sender = 'bidder-1',
				quantity = '1100000000000',
				createdAt = '1735689601000',
				blockheight = '123456790',
				requestedOrderId = 'auction-1',
			})

			-- Bid should be stored on the order
			local auction = Orderbook[ANT_TOKEN][ARIO_TOKEN].orders['auction-1']
			assert.is_not_nil(auction.bids)
			assert.is_not_nil(auction.bids['bidder-1'])
			assert.are.equal('bidder-1', auction.highestBidder)
			assert.are.equal('1100000000000', auction.highestBid)
		end)

		it('should accept second bid and return first bid', function()
			-- Setup auction with existing bid
			Orderbook = {
				[ANT_TOKEN] = {
					[ARIO_TOKEN] = {
						pair = { ANT_TOKEN, ARIO_TOKEN },
						orders = {
							['auction-1'] = {
								id = 'auction-1',
								creator = 'seller-1',
								token = ANT_TOKEN,
								quantity = '1',
								originalQuantity = '1',
								price = '1000000000000',
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

			-- Add initial bid directly to order
			Orderbook[ANT_TOKEN][ARIO_TOKEN].orders['auction-1'].bids = {
				['bidder-1'] = {
					bidder = 'bidder-1',
					amount = '1100000000000',
					timestamp = 1735689601000,
				},
			}
			Orderbook[ANT_TOKEN][ARIO_TOKEN].orders['auction-1'].highestBid = '1100000000000'
			Orderbook[ANT_TOKEN][ARIO_TOKEN].orders['auction-1'].highestBidder = 'bidder-1'

			ucm.createOrder({
				orderId = 'bid-2',
				dominantToken = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA',
				swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
				sender = 'bidder-2',
				quantity = '1200000000000',
				createdAt = '1735689602000',
				blockheight = '123456791',
				requestedOrderId = 'auction-1',
			})

			-- Second bid should be highest
			local auction = Orderbook[ANT_TOKEN][ARIO_TOKEN].orders['auction-1']
			assert.are.equal('bidder-2', auction.highestBidder)
			assert.are.equal('1200000000000', auction.highestBid)

			-- First bid should be returned (Transfer to bidder-1)
			local returnTransfer = nil
			for _, transfer in ipairs(transfers) do
				if transfer.recipient == 'bidder-1' then
					returnTransfer = transfer
					break
				end
			end
			assert.is_not_nil(returnTransfer)
			---@diagnostic disable-next-line: need-check-nil, undefined-field
			assert.are.equal('1100000000000', returnTransfer.quantity)
		end)

		it('should reject bid lower than current highest', function()
			-- Setup auction with existing bid
			Orderbook = {
				[ANT_TOKEN] = {
					[ARIO_TOKEN] = {
						pair = { ANT_TOKEN, ARIO_TOKEN },
						orders = {
							['auction-1'] = {
								id = 'auction-1',
								creator = 'seller-1',
								token = ANT_TOKEN,
								quantity = '1',
								originalQuantity = '1',
								price = '1000000000000',
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

			-- Add bid directly to order
			Orderbook[ANT_TOKEN][ARIO_TOKEN].orders['auction-1'].bids = {
				['bidder-1'] = {
					bidder = 'bidder-1',
					amount = '1200000000000',
					timestamp = 1735689601000,
				},
			}
			Orderbook[ANT_TOKEN][ARIO_TOKEN].orders['auction-1'].highestBid = '1200000000000'
			Orderbook[ANT_TOKEN][ARIO_TOKEN].orders['auction-1'].highestBidder = 'bidder-1'

			ucm.createOrder({
				orderId = 'bid-2',
				dominantToken = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA',
				swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
				sender = 'bidder-2',
				quantity = '1100000000000', -- Lower than 1200000000000
				createdAt = '1735689602000',
				blockheight = '123456791',
				requestedOrderId = 'auction-1',
			})

			-- Should get error
			assert.are.equal('Validation-Error', sentMessages[1].Action)
		end)

		it('should reject bid below minimum 1 ARIO increment', function()
			-- Setup auction with existing bid
			Orderbook = {
				[ANT_TOKEN] = {
					[ARIO_TOKEN] = {
						pair = { ANT_TOKEN, ARIO_TOKEN },
						orders = {
							['auction-1'] = {
								id = 'auction-1',
								creator = 'seller-1',
								token = ANT_TOKEN,
								quantity = '1',
								originalQuantity = '1',
								price = '1000000000000',
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

			-- Add bid directly to order
			Orderbook[ANT_TOKEN][ARIO_TOKEN].orders['auction-1'].bids = {
				['bidder-1'] = {
					bidder = 'bidder-1',
					amount = '1100000000000',
					timestamp = 1735689601000,
				},
			}
			Orderbook[ANT_TOKEN][ARIO_TOKEN].orders['auction-1'].highestBid = '1100000000000'
			Orderbook[ANT_TOKEN][ARIO_TOKEN].orders['auction-1'].highestBidder = 'bidder-1'

			ucm.createOrder({
				orderId = 'bid-2',
				dominantToken = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA',
				swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
				sender = 'bidder-2',
				quantity = '1100500000000', -- Only 0.5 ARIO more (1 ARIO = 1000000000 mARIO)
				createdAt = '1735689602000',
				blockheight = '123456791',
				requestedOrderId = 'auction-1',
			})

			-- Should get error for insufficient increment
			assert.are.equal('Validation-Error', sentMessages[1].Action)
		end)

		it('should accept bid that meets minimum 1 ARIO increment', function()
			-- Setup auction with existing bid
			Orderbook = {
				[ANT_TOKEN] = {
					[ARIO_TOKEN] = {
						pair = { ANT_TOKEN, ARIO_TOKEN },
						orders = {
							['auction-1'] = {
								id = 'auction-1',
								creator = 'seller-1',
								token = ANT_TOKEN,
								quantity = '1',
								originalQuantity = '1',
								price = '1000000000000',
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

			-- Add bid directly to order
			Orderbook[ANT_TOKEN][ARIO_TOKEN].orders['auction-1'].bids = {
				['bidder-1'] = {
					bidder = 'bidder-1',
					amount = '1100000000000',
					timestamp = 1735689601000,
				},
			}
			Orderbook[ANT_TOKEN][ARIO_TOKEN].orders['auction-1'].highestBid = '1100000000000'
			Orderbook[ANT_TOKEN][ARIO_TOKEN].orders['auction-1'].highestBidder = 'bidder-1'

			ucm.createOrder({
				orderId = 'bid-2',
				dominantToken = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA',
				swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
				sender = 'bidder-2',
				quantity = '1101000000000', -- Exactly 1 ARIO more
				createdAt = '1735689602000',
				blockheight = '123456791',
				requestedOrderId = 'auction-1',
			})

			-- Bid should be accepted
			local auction = Orderbook[ANT_TOKEN][ARIO_TOKEN].orders['auction-1']
			assert.are.equal('bidder-2', auction.highestBidder)
			assert.are.equal('1101000000000', auction.highestBid)
		end)
	end)

	describe('Helper functions', function()
		local english_auction = require('english_auction')

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
				local isValid, err = english_auction.validateBidAmount('1001', '1000', nil)
				assert.is_false(isValid)
				assert.are.equal('The next bid must be at least 1 ARIO higher than the current highest bid', err)
			end)

			it('should accept bid meeting minimum increment', function()
				local isValid, err = english_auction.validateBidAmount('1002', '1000', nil)
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

		describe('returnPreviousBid', function()
			local sentMessages = {}

			before_each(function()
				sentMessages = {}
				_G.ao.send = function(msg)
					table.insert(sentMessages, msg)
				end
			end)

			it('should send refund and notification when all parameters provided', function()
				local msg = { Tags = {} }
				english_auction.returnPreviousBid('auction-1', 'prev-bidder', '1000', 'TOKEN_ID', msg)

				assert.are.equal(2, #sentMessages)

				-- Check transfer
				assert.are.equal('TOKEN_ID', sentMessages[1].Target)
				assert.are.equal('Transfer', sentMessages[1].Action)
				assert.are.equal('prev-bidder', sentMessages[1].Tags.Recipient)
				assert.are.equal('1000', sentMessages[1].Tags.Quantity)

				-- Check notification
				assert.are.equal('prev-bidder', sentMessages[2].Target)
				assert.are.equal('Bid-Returned', sentMessages[2].Action)
				assert.are.equal('auction-1', sentMessages[2].Tags.OrderId)
			end)

			it('should not send anything when bidder is nil', function()
				local msg = { Tags = {} }
				english_auction.returnPreviousBid('auction-1', nil, '1000', 'TOKEN_ID', msg)
				assert.are.equal(0, #sentMessages)
			end)

			it('should not send anything when amount is nil', function()
				local msg = { Tags = {} }
				english_auction.returnPreviousBid('auction-1', 'prev-bidder', nil, 'TOKEN_ID', msg)
				assert.are.equal(0, #sentMessages)
			end)

			it('should not send anything when token is nil', function()
				local msg = { Tags = {} }
				english_auction.returnPreviousBid('auction-1', 'prev-bidder', '1000', nil, msg)
				assert.are.equal(0, #sentMessages)
			end)
		end)
	end)
end)
