print('\n=== Loading ucm module for testing ===')
require('test_globals')
local ucm = require('ucm')
print('✓ ucm module loaded')

describe('ucm helpers', function()
	print('\n--- Starting ucm helper tests ---')

	-- Setup and teardown helpers
	local function resetGlobals()
		_G.Orderbook = {}
		_G.OrderIndex = {}
		_G.ARIO_TOKEN_PROCESS_ID = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA'
	end

	before_each(function()
		resetGlobals()
	end)

	describe('findOrderById', function()
		it('should return nil for non-existent order', function()
			local order, pair = ucm.getOrderById('non-existent-id')
			assert.is_nil(order)
			assert.is_nil(pair)
		end)

		it('should return order and pair for valid order', function()
			-- Setup orderbook
			local dominantToken = 'ANT_TOKEN_ID_12345678901234567890123456789012'
			local swapToken = 'ARIO_TOKEN_ID_1234567890123456789012345678901'
			local orderId = 'order-123'

			_G.Orderbook[dominantToken] = {
				[swapToken] = {
					pair = { dominantToken, swapToken },
					orders = {
						[orderId] = {
							id = orderId,
							quantity = '1',
							originalQuantity = '1',
							creator = 'creator-addr',
							token = dominantToken,
							dateCreated = 1000,
							orderType = 'fixed',
							status = 'active',
						},
					},
				},
			}

			_G.OrderIndex[orderId] = {
				dominantToken = dominantToken,
				swapToken = swapToken,
			}

			local order, pair = ucm.getOrderById(orderId)
			assert.is_not_nil(order)
			assert.is_not_nil(pair)
			if order then
				assert.are.equal(orderId, order.id)
				assert.are.equal('1', order.quantity)
			end
		end)

		it('should clean up stale index when pair does not exist', function()
			local orderId = 'stale-order'
			_G.OrderIndex[orderId] = {
				dominantToken = 'missing-token',
				swapToken = 'missing-swap',
			}

			local order, pair = ucm.getOrderById(orderId)
			assert.is_nil(order)
			assert.is_nil(pair)
			assert.is_nil(_G.OrderIndex[orderId])
		end)

		it('should clean up stale index when order does not exist in pair', function()
			local dominantToken = 'ANT_TOKEN_ID_12345678901234567890123456789012'
			local swapToken = 'ARIO_TOKEN_ID_1234567890123456789012345678901'
			local orderId = 'missing-order'

			_G.Orderbook[dominantToken] = {
				[swapToken] = {
					pair = { dominantToken, swapToken },
					orders = {},
				},
			}

			_G.OrderIndex[orderId] = {
				dominantToken = dominantToken,
				swapToken = swapToken,
			}

			local order, pair = ucm.getOrderById(orderId)
			assert.is_nil(order)
			assert.is_nil(pair)
			assert.is_nil(_G.OrderIndex[orderId])
		end)
	end)

	describe('validateAntDominantOrder', function()
		local validPair = { 'ANT_TOKEN_ID_12345678901234567890123456789012', _G.ARIO_TOKEN_PROCESS_ID }
		local sentMessages = {}

		before_each(function()
			sentMessages = {}
			_G.ao.send = function(msg)
				table.insert(sentMessages, msg)
			end
		end)

		it('should reject quantity not equal to 1', function()
			local args = {
				quantity = '2',
				sender = 'test-sender',
				orderGroupId = 'group-1',
				msg = { Tags = { Quantity = '2' }, From = 'token-process-id' },
			}

			local success, err = pcall(function()
				ucm.validateAntDominantOrder(args, validPair)
			end)
			assert.is_false(success)
			assert.is_string(err)
			assert.are.equal(2, #sentMessages) -- Transfer (refund) + Validation-Error
			assert.are.equal('Transfer', sentMessages[1].Action)
			assert.are.equal('Validation-Error', sentMessages[2].Action)
		end)

		it('should reject missing price', function()
			local args = {
				quantity = '1',
				sender = 'test-sender',
				orderGroupId = 'group-1',
				msg = { Tags = { Quantity = '1' }, From = 'token-process-id' },
			}

			local success, err = pcall(function()
				ucm.validateAntDominantOrder(args, validPair)
			end)
			assert.is_false(success)
			assert.is_string(err)
			assert.are.equal(2, #sentMessages)
			assert.are.equal('Transfer', sentMessages[1].Action)
			assert.are.equal('Validation-Error', sentMessages[2].Action)
		end)

		it('should reject invalid price', function()
			local args = {
				quantity = '1',
				price = '0',
				sender = 'test-sender',
				orderGroupId = 'group-1',
				createdAt = 1000,
				msg = { Tags = { Quantity = '1' }, From = 'token-process-id' },
			}

			local success, err = pcall(function()
				ucm.validateAntDominantOrder(args, validPair)
			end)
			assert.is_false(success)
			assert.is_string(err)
		end)

		it('should accept valid ANT order', function()
			local args = {
				quantity = '1',
				price = '1000',
				expirationTime = 2000,
				createdAt = 1000,
				sender = 'test-sender',
				orderGroupId = 'group-1',
				msg = { Tags = { Quantity = '1' }, From = 'token-process-id' },
			}

			local result = ucm.validateAntDominantOrder(args, validPair)
			assert.is_true(result)
			assert.are.equal(0, #sentMessages)
		end)
	end)

	describe('validateArioDominantOrder', function()
		local validPair = { _G.ARIO_TOKEN_PROCESS_ID, 'ANT_TOKEN_ID_12345678901234567890123456789012' }
		local sentMessages = {}

		before_each(function()
			sentMessages = {}
			_G.ao.send = function(msg)
				table.insert(sentMessages, msg)
			end
		end)

		it('should reject missing requestedOrderId', function()
			local args = {
				sender = 'test-sender',
				orderGroupId = 'group-1',
				msg = { Tags = { Quantity = '1000' }, From = 'token-process-id' },
			}

			local success, err = pcall(function()
				ucm.validateArioDominantOrder(args, validPair)
			end)
			assert.is_false(success)
			assert.is_string(err)
			assert.are.equal(2, #sentMessages)
			assert.are.equal('Transfer', sentMessages[1].Action)
			assert.are.equal('Validation-Error', sentMessages[2].Action)
		end)

		it('should accept valid ARIO order', function()
			local args = {
				requestedOrderId = 'order-123',
				sender = 'test-sender',
				orderGroupId = 'group-1',
				msg = { Tags = { Quantity = '1000' }, From = 'token-process-id' },
			}

			local result = ucm.validateArioDominantOrder(args, validPair)
			assert.is_true(result)
			assert.are.equal(0, #sentMessages)
		end)
	end)

	describe('validateOrderParams', function()
		local sentMessages = {}

		before_each(function()
			sentMessages = {}
			_G.ao.send = function(msg)
				table.insert(sentMessages, msg)
			end
		end)

		it('should reject invalid pair data', function()
			local args = {
				dominantToken = 'invalid',
				swapToken = 'invalid',
				quantity = '1',
				orderType = 'fixed',
				sender = 'test-sender',
				msg = { Tags = { Quantity = '1' }, From = 'token-process-id' },
			}

		local success = pcall(function()
			return ucm.validateOrderParams(args)
		end)
		assert.is_false(success)
		end)

		it('should reject trade without ARIO', function()
			local args = {
				dominantToken = 'ANT1_TOKEN_ID_1234567890123456789012345678901',
				swapToken = 'ANT2_TOKEN_ID_1234567890123456789012345678901',
				quantity = '1',
				orderType = 'fixed',
				sender = 'test-sender',
				msg = { Tags = { Quantity = '1' }, From = 'token-process-id' },
			}

		local success = pcall(function()
			return ucm.validateOrderParams(args)
		end)
		assert.is_false(success)
		end)

		it('should reject invalid quantity', function()
			local args = {
				dominantToken = 'ANT_TOKEN_ID_12345678901234567890123456789012',
				swapToken = _G.ARIO_TOKEN_PROCESS_ID,
				quantity = '0',
				orderType = 'fixed',
				sender = 'test-sender',
				msg = { Tags = { Quantity = '0' }, From = 'token-process-id' },
			}

		local success = pcall(function()
			return ucm.validateOrderParams(args)
		end)
		assert.is_false(success)
		end)

		it('should reject invalid order type', function()
			local args = {
				dominantToken = 'ANT_TOKEN_ID_12345678901234567890123456789012',
				swapToken = _G.ARIO_TOKEN_PROCESS_ID,
				quantity = '1',
				orderType = 'invalid',
				sender = 'test-sender',
				msg = { Tags = { Quantity = '1' }, From = 'token-process-id' },
			}

		local success = pcall(function()
			return ucm.validateOrderParams(args)
		end)
		assert.is_false(success)
		end)

		it('should accept valid fixed order', function()
			local args = {
				dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
				swapToken = ARIO_TOKEN_PROCESS_ID,
				quantity = '1',
				price = '1000',
				expirationTime = 2000,
				createdAt = 1000,
				orderType = 'fixed',
				sender = 'test-sender',
				orderGroupId = 'group-1',
				msg = { Tags = { Quantity = '1' }, From = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
			}

			local result = ucm.validateOrderParams(args)
			assert.is_not_nil(result)
			assert.are.equal(2, #result)
		end)
	end)

	describe('ensurePairExists', function()
		it('should create new pair if it does not exist', function()
			local dominantToken = 'ANT_TOKEN_ID_12345678901234567890123456789012'
			local swapToken = 'ARIO_TOKEN_ID_1234567890123456789012345678901'
			local validPair = { dominantToken, swapToken }

			local pair = ucm.ensurePairExists(validPair)
			assert.is_not_nil(pair)
			assert.is_not_nil(_G.Orderbook[dominantToken])
			assert.is_not_nil(_G.Orderbook[dominantToken][swapToken])
			assert.are.same(validPair, pair.pair)
			assert.are.same({}, pair.orders)
		end)

		it('should return existing pair if it already exists', function()
			local dominantToken = 'ANT_TOKEN_ID_12345678901234567890123456789012'
			local swapToken = 'ARIO_TOKEN_ID_1234567890123456789012345678901'
			local validPair = { dominantToken, swapToken }

			-- Create pair first
			_G.Orderbook[dominantToken] = {
				[swapToken] = {
					pair = validPair,
					orders = {
						['order-1'] = {
							id = 'order-1',
							creator = 'test-creator',
							quantity = '1',
							originalQuantity = '1',
							token = dominantToken,
							dateCreated = 1000,
							orderType = 'fixed',
							status = 'active',
						},
					},
				},
			}

			local pair = ucm.ensurePairExists(validPair)
			assert.is_not_nil(pair)
			assert.is_not_nil(pair.orders['order-1'])
		end)
	end)
end)
