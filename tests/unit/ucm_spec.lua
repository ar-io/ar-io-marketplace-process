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
			---@diagnostic disable-next-line: duplicate-set-field
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
			---@diagnostic disable-next-line: duplicate-set-field
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
			---@diagnostic disable-next-line: duplicate-set-field
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

	describe('createOrderHandler - Internal ARIO Balance', function()
		local sentMessages
		local balances

		before_each(function()
			resetGlobals()
			balances = require('balances')
			
			-- Mock ao.send to track messages
			sentMessages = {}
			---@diagnostic disable-next-line: duplicate-set-field
			_G.ao.send = function(msg)
				table.insert(sentMessages, msg)
				return true
			end
			
			-- Give user and seller some ARIO balance
			_G.ARIOBalances['test-user'] = {balance = '10000000000', orders = {}} -- 10 ARIO
			_G.ARIOBalances['ant-seller'] = {balance = '0', orders = {}} -- ANT seller
		end)

		it('should use internal ARIO balance for buying ANT (no Credit-Notice needed)', function()
			-- Setup: Create an ANT listing first
			local antToken = string.rep('1', 43) -- 43 character ANT process ID
			_G.Orderbook[antToken] = {
				[_G.ARIO_TOKEN_PROCESS_ID] = {
					pair = {antToken, _G.ARIO_TOKEN_PROCESS_ID},
					Pair = {antToken, _G.ARIO_TOKEN_PROCESS_ID},
					orders = {
						['ant-sell-order'] = {
							id = 'ant-sell-order',
							quantity = '1',
							originalQuantity = '1',
							creator = 'ant-seller',
							token = antToken,
							dateCreated = 1000,
							price = '1000000000', -- 1 ARIO
							orderType = 'fixed',
							status = 'active',
							dominantToken = antToken,
							swapToken = _G.ARIO_TOKEN_PROCESS_ID,
						},
					},
				},
			}
			_G.OrderIndex['ant-sell-order'] = {
				dominantToken = antToken,
				swapToken = _G.ARIO_TOKEN_PROCESS_ID,
			}

			local msg = {
				Id = 'buy-order-123',
				From = 'test-user',
				Timestamp = 2000,
				['Block-Height'] = 100,
				Tags = {
					['Swap-Token'] = antToken,
					Quantity = '1000000000', -- 1 ARIO
					['Order-Type'] = 'fixed',
					['Requested-Order-Id'] = 'ant-sell-order',
				},
			}

			-- Act: User buys ANT using internal ARIO balance
			local result = ucm.createOrderHandler(msg)
			local resultData = require('json').decode(result)

			-- Assert: Balance should be deducted
			assert.are.equal('9000000000', _G.ARIOBalances['test-user'].balance) -- 10 - 1 = 9 ARIO

			-- Assert: Seller should receive ARIO to their internal balance (minus fee)
			local sellerBalance = balances.getBalance('ant-seller')
			assert.is_true(tonumber(sellerBalance) > 0, 'Seller should receive ARIO')

			-- Assert: No Credit-Notice needed, order executed immediately
			assert.are.equal('Success', resultData.Status)
		end)

		it('should fail when user has insufficient internal ARIO balance', function()
			-- User has 10 ARIO, tries to spend 20 ARIO
			local antToken = string.rep('2', 43) -- 43 character ANT process ID
			_G.Orderbook[antToken] = {
				[_G.ARIO_TOKEN_PROCESS_ID] = {
					pair = {antToken, _G.ARIO_TOKEN_PROCESS_ID},
					Pair = {antToken, _G.ARIO_TOKEN_PROCESS_ID},
					orders = {
						['expensive-ant'] = {
							id = 'expensive-ant',
							quantity = '1',
							originalQuantity = '1',
							creator = 'ant-seller',
							token = antToken,
							dateCreated = 1000,
							price = '20000000000', -- 20 ARIO
							orderType = 'fixed',
							status = 'active',
							dominantToken = antToken,
							swapToken = _G.ARIO_TOKEN_PROCESS_ID,
						},
					},
				},
			}

			local msg = {
				Id = 'buy-order-fail',
				From = 'test-user',
				Timestamp = 2000,
				['Block-Height'] = 100,
				Tags = {
					['Swap-Token'] = antToken,
					Quantity = '20000000000', -- 20 ARIO (more than user has)
					['Order-Type'] = 'fixed',
					['Requested-Order-Id'] = 'expensive-ant',
				},
			}

			local success, err = pcall(function()
				ucm.createOrderHandler(msg)
			end)

			assert.is_false(success)
			assert.is_not_nil(err)
			assert.is_true(string.find(tostring(err), 'Insufficient balance') ~= nil)
			
			-- User balance should remain unchanged
			assert.are.equal('10000000000', _G.ARIOBalances['test-user'].balance)
		end)

		it('should not create intents for internal ARIO balance orders', function()
			-- Setup simple ANT listing
			local antToken = string.rep('3', 43) -- 43 character ANT process ID
			_G.Orderbook[antToken] = {
				[_G.ARIO_TOKEN_PROCESS_ID] = {
					pair = {antToken, _G.ARIO_TOKEN_PROCESS_ID},
					Pair = {antToken, _G.ARIO_TOKEN_PROCESS_ID},
					orders = {
						['simple-ant'] = {
							id = 'simple-ant',
							quantity = '1',
							originalQuantity = '1',
							creator = 'ant-seller',
							token = antToken,
							dateCreated = 1000,
							price = '500000000', -- 0.5 ARIO
							orderType = 'fixed',
							status = 'active',
							dominantToken = antToken,
							swapToken = _G.ARIO_TOKEN_PROCESS_ID,
						},
					},
				},
			}

			local msg = {
				Id = 'buy-order-no-intent',
				From = 'test-user',
				Timestamp = 2000,
				['Block-Height'] = 100,
				Tags = {
					['Swap-Token'] = antToken,
					Quantity = '500000000', -- 0.5 ARIO
					['Order-Type'] = 'fixed',
					['Requested-Order-Id'] = 'simple-ant',
				},
			}

			-- Initialize empty Intents table
			_G.Intents = {}
			_G.IntentCounter = '0'

			ucm.createOrderHandler(msg)

			-- Assert: No intents should be created for ARIO internal balance orders
			local intentCount = 0
			for _ in pairs(_G.Intents) do
				intentCount = intentCount + 1
			end
			assert.are.equal(0, intentCount, 'No intents should be created for internal ARIO balance orders')
			assert.are.equal('0', _G.IntentCounter, 'Intent counter should remain at 0')
		end)
	end)
end)
