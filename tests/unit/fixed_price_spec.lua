print('\n=== Loading fixed_price module for testing ===')
require('test_globals')
local fixed_price = require('fixed_price')
print('✓ fixed_price module loaded')
local bint = require('.bint')(256)
print('✓ bint module loaded')

describe('fixed_price helpers', function()
	print('\n--- Starting fixed_price helper tests ---')

	describe('updateVwapData', function()
		it('should return 0 volume for empty matches', function()
			local pair = { orders = {} }
			local matches = {}
			local args = { blockheight = '1000' }
			local currentToken = 'TOKEN_ID_1234567890123456789012345678901234'

			local sumVolume = fixed_price.updateVwapData(pair, matches, args, currentToken)
			assert.are.equal(0, sumVolume)
			assert.is_nil(pair.PriceData)
		end)

		it('should calculate VWAP correctly for single match', function()
			local pair = { orders = {} }
			local matches = {
				{
					id = 'order-1',
					quantity = '1000',
					price = '100',
				},
			}
			local args = { blockheight = '1000' }
			local currentToken = 'TOKEN_ID_1234567890123456789012345678901234'

			local sumVolume = fixed_price.updateVwapData(pair, matches, args, currentToken)

			-- Expected: volume = 1000, price = 100, vwap = (1000 * 100) / 1000 = 100
			assert.are.equal(bint(1000), sumVolume)
			assert.is_not_nil(pair.priceData)
			assert.are.equal('100', pair.priceData.vwap)
			assert.are.equal('1000', pair.priceData.block)
			assert.are.equal(currentToken, pair.priceData.dominantToken)
			assert.are.same(matches, pair.priceData.matchLogs)
		end)

		it('should calculate VWAP correctly for multiple matches', function()
			local pair = { orders = {} }
			local matches = {
				{
					id = 'order-1',
					quantity = '1000',
					price = '100',
				},
				{
					id = 'order-2',
					quantity = '2000',
					price = '150',
				},
			}
			local args = { blockheight = '2000' }
			local currentToken = 'TOKEN_ID_1234567890123456789012345678901234'

			local sumVolume = fixed_price.updateVwapData(pair, matches, args, currentToken)

			-- Expected:
			-- sumVolumePrice = (1000 * 100) + (2000 * 150) = 100,000 + 300,000 = 400,000
			-- sumVolume = 1000 + 2000 = 3000
			-- vwap = 400,000 / 3000 = 133.333... = floor(133) = 133
			assert.are.equal(bint(3000), sumVolume)
			assert.is_not_nil(pair.priceData)
			assert.are.equal('133', pair.priceData.vwap)
			assert.are.equal('2000', pair.priceData.block)
		end)

		it('should handle large volume and price values', function()
			local pair = { orders = {} }
			local matches = {
				{
					id = 'order-1',
					quantity = '1000000000000',
					price = '50000000',
				},
			}
			local args = { blockheight = '5000' }
			local currentToken = 'TOKEN_ID_1234567890123456789012345678901234'

			local sumVolume = fixed_price.updateVwapData(pair, matches, args, currentToken)

			assert.are.equal(bint('1000000000000'), sumVolume)
			assert.is_not_nil(pair.priceData)
			-- vwap = (1000000000000 * 50000000) / 1000000000000 = 50000000
			assert.are.equal('50000000', pair.priceData.vwap)
		end)

		it('should floor VWAP to integer', function()
			local pair = { orders = {} }
			local matches = {
				{
					id = 'order-1',
					quantity = '3',
					price = '10',
				},
			}
			local args = { blockheight = '3000' }
			local currentToken = 'TOKEN_ID_1234567890123456789012345678901234'

			local sumVolume = fixed_price.updateVwapData(pair, matches, args, currentToken)

			-- vwap = (3 * 10) / 3 = 10
			assert.are.equal(bint(3), sumVolume)
			assert.are.equal('10', pair.priceData.vwap)
		end)
	end)

	describe('pruneExpiredOrder', function()
		it('should mark order as expired', function()
			local order = {
				id = 'order-123',
				status = 'active',
				expirationTime = 2000,
			}

			fixed_price.pruneExpiredOrder(order)

			assert.are.equal('expired', order.status)
			assert.are.equal(2000, order.endedAt)
		end)
	end)

	describe('handleArioOrder', function()
		local testGlobals = require('test_globals')

		before_each(function()
			testGlobals.resetState()
			testGlobals.setArioTokenId('ario-token-123')
		end)

		it('should create ANT sell order in orderbook', function()
			local validPair = {'ant-token-456', 'ario-token-123'}
			local pair = {orders = {}}
			local args = {
				orderId = 'order-123',
				quantity = '1',
				sender = 'user-123',
				dominantToken = 'ant-token-456',
				swapToken = 'ario-token-123',
				createdAt = 1000,
				blockheight = '100',
				price = '5000',
				expirationTime = '2000',
				msg = testGlobals.mockMsg({}),
			}

			fixed_price.handleArioOrder(args, validPair, pair)

			-- Check order was added to orderbook
			assert.is_not_nil(pair.orders['order-123'])
			local order = pair.orders['order-123']
			assert.are.equal('order-123', order.id)
			assert.are.equal('1', order.quantity)
			assert.are.equal('user-123', order.creator)
			assert.are.equal('ant-token-456', order.token)
			assert.are.equal('5000', order.price)
			assert.are.equal('active', order.status)
			assert.are.equal('fixed', order.orderType)
			
			-- Check index was updated
			assert.is_not_nil(OrderIndex['order-123'])
			assert.are.equal('ant-token-456', OrderIndex['order-123'].dominantToken)
			assert.are.equal('ario-token-123', OrderIndex['order-123'].swapToken)

			-- Check success message was sent
			assert.is_true(#testGlobals.sentMessages > 0)
			local successMsg = testGlobals.sentMessages[1]
			assert.are.equal('Order-Success', successMsg.Action)
			assert.are.equal('order-123', successMsg.Tags['Order-Id'])
		end)

		it('should handle order without expiration time', function()
			local validPair = {'ant-token-456', 'ario-token-123'}
			local pair = {orders = {}}
			local args = {
				orderId = 'order-456',
				quantity = '1',
				sender = 'user-456',
				dominantToken = 'ant-token-456',
				swapToken = 'ario-token-123',
				createdAt = 1000,
				blockheight = '100',
				price = '3000',
				expirationTime = nil, -- No expiration
				msg = testGlobals.mockMsg({}),
			}

			fixed_price.handleArioOrder(args, validPair, pair)

			-- Order should still be created
			assert.is_not_nil(pair.orders['order-456'])
			assert.is_nil(pair.orders['order-456'].expirationTime)
		end)
	end)

	describe('handleAntOrder', function()
		local testGlobals = require('test_globals')
		local balances = require('balances')

		before_each(function()
			testGlobals.resetState()
			testGlobals.setArioTokenId('ario-token-123')
		end)

		it('should execute immediate match with matching sell order', function()
			local validPair = {'ant-token-456', 'ario-token-123'}
			local pair = {
				pair = validPair,
				orders = {
					['sell-order-1'] = {
						id = 'sell-order-1',
						quantity = '1',
						originalQuantity = '1',
						creator = 'seller-123',
						token = 'ant-token-456',
						price = '5000',
						status = 'active',
						orderType = 'fixed',
						dominantToken = 'ant-token-456',
						swapToken = 'ario-token-123',
					}
				}
			}

			-- Give buyer ARIO balance (need to cover price + fee)
			ARIOBalances['buyer-123'] = {
				balance = '10000',
				orders = {}
			}

			local args = {
				orderId = 'buy-order-1',
				quantity = '5000',
				sender = 'buyer-123',
				dominantToken = 'ario-token-123',
				swapToken = 'ant-token-456',
				createdAt = 1000,
				blockheight = '100',
				requestedOrderId = 'sell-order-1', -- Request specific order
				msg = testGlobals.mockMsg({}),
			}

			fixed_price.handleAntOrder(args, validPair, pair)

			-- Order should be removed from orderbook
			assert.is_nil(pair.orders['sell-order-1'])
			
			-- Buyer balance should be reduced by the price (10000 - 5000 = 5000)
			assert.are.equal('5000', ARIOBalances['buyer-123'].balance)
			
			-- Seller should have received ARIO minus 0.5% maker fee (5000 * 0.995 = 4975)
			assert.are.equal('4975', balances.getBalance('seller-123'))

			-- Success message should be sent
			local successMsg = nil
			for _, msg in ipairs(testGlobals.sentMessages) do
				if msg.Action == 'Order-Success' then
					successMsg = msg
					break
				end
			end
			assert.is_not_nil(successMsg)
			assert.are.equal('buy-order-1', successMsg.Tags['Order-Id'])
		end)

		it('should return error if no matching orders found', function()
			local validPair = {'ant-token-456', 'ario-token-123'}
			local pair = {
				pair = validPair,
				orders = {} -- No sell orders
			}

			-- Give buyer ARIO balance
			ARIOBalances['buyer-123'] = {
				balance = '10000',
				orders = {}
			}

			local args = {
				orderId = 'buy-order-1',
				quantity = '5000',
				sender = 'buyer-123',
				dominantToken = 'ario-token-123',
				swapToken = 'ant-token-456',
				createdAt = 1000,
				blockheight = '100',
				requestedOrderId = 'non-existent-order', -- Request order that doesn't exist
				msg = testGlobals.mockMsg({}),
			}

			-- Should throw error when no matching order found
			local success, err = pcall(function()
				fixed_price.handleAntOrder(args, validPair, pair)
			end)

			-- Expect error to be thrown
			assert.is_false(success)
			assert.is_string(err)
		end)

		it('should skip orders with insufficient buyer balance', function()
			local validPair = {'ant-token-456', 'ario-token-123'}
			local pair = {
				pair = validPair,
				orders = {
					['sell-order-expensive'] = {
						id = 'sell-order-expensive',
						quantity = '1',
						creator = 'seller-123',
						token = 'ant-token-456',
						price = '10000',
						status = 'active',
						orderType = 'fixed',
						dominantToken = 'ant-token-456',
						swapToken = 'ario-token-123',
					},
					['sell-order-cheap'] = {
						id = 'sell-order-cheap',
						quantity = '1',
						creator = 'seller-456',
						token = 'ant-token-456',
						price = '3000',
						status = 'active',
						orderType = 'fixed',
						dominantToken = 'ant-token-456',
						swapToken = 'ario-token-123',
					}
				}
			}

			-- Give buyer limited ARIO balance (can't afford first order)
			ARIOBalances['buyer-123'] = {
				balance = '5000',
				orders = {}
			}

			local args = {
				orderId = 'buy-order-1',
				quantity = '5000',
				sender = 'buyer-123',
				dominantToken = 'ario-token-123',
				swapToken = 'ant-token-456',
				createdAt = 1000,
				blockheight = '100',
				requestedOrderId = 'sell-order-cheap', -- Request the cheaper order
				msg = testGlobals.mockMsg({}),
			}

			fixed_price.handleAntOrder(args, validPair, pair)

			-- Should match with cheaper order
			assert.is_nil(pair.orders['sell-order-cheap'])
			assert.is_not_nil(pair.orders['sell-order-expensive']) -- Still there
			
			-- Buyer balance should be reduced
			assert.are.equal('2000', ARIOBalances['buyer-123'].balance)
		end)

		it('should skip non-active orders', function()
			local validPair = {'ant-token-456', 'ario-token-123'}
			local pair = {
				pair = validPair,
				orders = {
					['sell-order-expired'] = {
						id = 'sell-order-expired',
						quantity = '1',
						creator = 'seller-123',
						token = 'ant-token-456',
						price = '5000',
						status = 'active', -- Set as active but will be expired by time
						orderType = 'fixed',
						dominantToken = 'ant-token-456',
						swapToken = 'ario-token-123',
						expirationTime = 2000, -- Expiration time
					}
				}
			}

			-- Give buyer ARIO balance
			ARIOBalances['buyer-123'] = {
				balance = '10000',
				orders = {}
			}

			local args = {
				orderId = 'buy-order-1',
				quantity = '5000',
				sender = 'buyer-123',
				dominantToken = 'ario-token-123',
				swapToken = 'ant-token-456',
				createdAt = 3000, -- After order expiration (> 2000)
				blockheight = '100',
				requestedOrderId = 'sell-order-expired', -- Request expired order
				msg = testGlobals.mockMsg({}),
			}

			-- Should throw error when order is expired (skipped in matching)
			local success, err = pcall(function()
				fixed_price.handleAntOrder(args, validPair, pair)
			end)

			-- Expect error to be thrown (no matching orders found)
			assert.is_false(success)
			assert.is_not_nil(err)
		end)
	end)
end)
