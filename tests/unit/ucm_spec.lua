print('\n=== Loading ucm module for testing ===')
local testGlobals = require('test_globals')
local ucm = require('ucm')
local json = require('json')
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

	describe('scheduleNextOrderbookPruning', function()
		before_each(function()
			_G.Pruning = nil
		end)

		it('should initialize Pruning if not exists', function()
			ucm.scheduleNextOrderbookPruning(5000)
			
			assert.is_not_nil(_G.Pruning)
			assert.are.equal(5000, _G.Pruning.nextScheduledOrderbookPruning)
		end)

		it('should update if new timestamp is sooner', function()
			_G.Pruning = { nextScheduledOrderbookPruning = 10000 }
			
			ucm.scheduleNextOrderbookPruning(5000)
			
			assert.are.equal(5000, _G.Pruning.nextScheduledOrderbookPruning)
		end)

		it('should not update if new timestamp is later', function()
			_G.Pruning = { nextScheduledOrderbookPruning = 5000 }
			
			ucm.scheduleNextOrderbookPruning(10000)
			
			assert.are.equal(5000, _G.Pruning.nextScheduledOrderbookPruning)
		end)

		it('should handle nil timestamp gracefully', function()
			ucm.scheduleNextOrderbookPruning(nil)
			-- Should not crash
		end)
	end)

	describe('pruneOrderbook', function()
		local testGlobals = require('test_globals')

		before_each(function()
			testGlobals.resetState()
		end)

		it('should return early if no pruning scheduled', function()
			_G.Pruning = nil
			
			ucm.pruneOrderbook(5000, {})
			
			-- Should not crash
		end)

		it('should return early if not time yet', function()
			_G.Pruning = { nextScheduledOrderbookPruning = 10000 }
			
			ucm.pruneOrderbook(5000, {})
			
			-- nextScheduledOrderbookPruning should not change
			assert.are.equal(10000, _G.Pruning.nextScheduledOrderbookPruning)
		end)

		it('should prune expired fixed price orders', function()
			local fixedPrice = require('fixed_price')
			_G.Pruning = { nextScheduledOrderbookPruning = 2000 }
			
			_G.Orderbook = {
				['ant-token'] = {
					['ario-token'] = {
						orders = {
							['expired-order'] = {
								id = 'expired-order',
								status = 'active',
								expirationTime = 1000,
								orderType = 'fixed',
							},
						},
					},
				},
			}

			ucm.pruneOrderbook(2000, {})

			-- Order should be marked as expired
			assert.are.equal('expired', _G.Orderbook['ant-token']['ario-token'].orders['expired-order'].status)
		end)

		it('should reschedule next pruning for future expirations', function()
			_G.Pruning = { nextScheduledOrderbookPruning = 1000 }
			
			_G.Orderbook = {
				['ant-token'] = {
					['ario-token'] = {
						orders = {
							['future-order'] = {
								id = 'future-order',
								status = 'active',
								expirationTime = 5000,
								orderType = 'fixed',
							},
						},
					},
				},
			}

			ucm.pruneOrderbook(2000, {})

			-- Should reschedule for 5000
			assert.are.equal(5000, _G.Pruning.nextScheduledOrderbookPruning)
		end)
	end)

	describe('getPair', function()
		it('should return pair if exists', function()
			_G.Orderbook = {
				['ant-token'] = {
					['ario-token'] = {
						pair = {'ant-token', 'ario-token'},
						orders = {},
					},
				},
			}

			local pair = ucm.getPair('ant-token', 'ario-token')
			assert.is_not_nil(pair)
			assert.are.same({'ant-token', 'ario-token'}, pair.pair)
		end)

		it('should return nil if pair does not exist', function()
			_G.Orderbook = {}

			local pair = ucm.getPair('non-existent', 'non-existent')
			assert.is_nil(pair)
		end)
	end)

	describe('pruneEmptyPair', function()
		it('should remove empty pair', function()
			_G.Orderbook = {
				['ant-token'] = {
					['ario-token'] = {
						orders = {}, -- Empty
					},
				},
			}

			ucm.pruneEmptyPair('ant-token', 'ario-token')

			-- Pair should be removed (and since it's the only pair, the dominant token level too)
			assert.is_nil(_G.Orderbook['ant-token'])
		end)

		it('should remove dominant token level if empty', function()
			_G.Orderbook = {
				['ant-token'] = {
					['ario-token'] = {
						orders = {},
					},
				},
			}

			ucm.pruneEmptyPair('ant-token', 'ario-token')

			assert.is_nil(_G.Orderbook['ant-token'])
		end)

		it('should not remove pair with orders', function()
			_G.Orderbook = {
				['ant-token'] = {
					['ario-token'] = {
						orders = {
							['order-123'] = { id = 'order-123' },
						},
					},
				},
			}

			ucm.pruneEmptyPair('ant-token', 'ario-token')

			assert.is_not_nil(_G.Orderbook['ant-token']['ario-token'])
		end)

		it('should not remove dominant token if other pairs exist', function()
			_G.Orderbook = {
				['ant-token'] = {
					['ario-token'] = {
						orders = {},
					},
					['other-token'] = {
						orders = {
							['order-456'] = { id = 'order-456' },
						},
					},
				},
			}

			ucm.pruneEmptyPair('ant-token', 'ario-token')

			assert.is_nil(_G.Orderbook['ant-token']['ario-token'])
			assert.is_not_nil(_G.Orderbook['ant-token']['other-token'])
		end)
	end)

	describe('cancelOrderHandler', function()
		local testGlobals = require('test_globals')
		local balances = require('balances')

		before_each(function()
			testGlobals.resetState()
			testGlobals.setArioTokenId('ario-token-123')
		end)

		it('should cancel order and return balance', function()
			-- Create order in orderbook
			_G.Orderbook = {
				['ant-token'] = {
					['ario-token-123'] = {
						orders = {
							['order-123'] = {
								id = 'order-123',
								creator = 'user-123',
								quantity = '1',
								token = 'ant-token',
								status = 'active',
								orderType = 'fixed',
								dominantToken = 'ant-token',
								swapToken = 'ario-token-123',
							},
						},
					},
				},
			}

			_G.OrderIndex['order-123'] = {
				dominantToken = 'ant-token',
				swapToken = 'ario-token-123',
			}

			local msg = testGlobals.mockMsg({
				From = 'user-123',
				Tags = {
					['Order-Id'] = 'order-123',
				},
			})

			local result = ucm.cancelOrderHandler(msg)

			-- Order should be removed
			assert.is_nil(_G.OrderIndex['order-123'])

			-- Pair should be pruned (empty) - dominant token level should be removed
			assert.is_nil(_G.Orderbook['ant-token'])
		end)

		it('should fail if order not found', function()
			local msg = testGlobals.mockMsg({
				From = 'user-123',
				Tags = {
					['Order-Id'] = 'non-existent',
				},
			})

			local success = pcall(function()
				ucm.cancelOrderHandler(msg)
			end)

			assert.is_false(success)
		end)

		it('should fail if unauthorized', function()
			_G.Orderbook = {
				['ant-token'] = {
					['ario-token-123'] = {
						orders = {
							['order-123'] = {
								id = 'order-123',
								creator = 'user-123',
								status = 'active',
								orderType = 'fixed',
							},
						},
					},
				},
			}

			_G.OrderIndex['order-123'] = {
				dominantToken = 'ant-token',
				swapToken = 'ario-token-123',
			}

			local msg = testGlobals.mockMsg({
				From = 'user-456', -- Different user
				Tags = {
					['Order-Id'] = 'order-123',
				},
			})

			local success = pcall(function()
				ucm.cancelOrderHandler(msg)
			end)

			assert.is_false(success)
		end)
	end)

	describe('infoHandler', function()
		local testGlobals = require('test_globals')
		local json = require('json')

		before_each(function()
			testGlobals.resetState()
			testGlobals.setArioTokenId('ario-token-123')
		end)

		it('should return marketplace info', function()
			-- Add some orders
			_G.Orderbook = {
				['ant-token'] = {
					['ario-token-123'] = {
						orders = {
							['order-1'] = { status = 'active' },
							['order-2'] = { status = 'executed' },
							['order-3'] = { status = 'cancelled' },
						},
					},
				},
			}

			local msg = testGlobals.mockMsg({})
			local result = ucm.infoHandler(msg)
			local info = json.decode(result)

			assert.is_not_nil(info)
			assert.are.equal(3, info.activity.totalOrders)
			assert.are.equal(1, info.activity.activeOrders)
			assert.are.equal(1, info.activity.executedOrders)
			assert.are.equal(1, info.activity.cancelledOrders)
			assert.are.equal(1, info.ucm.totalPairs)
		end)

		it('should handle empty orderbook', function()
			_G.Orderbook = {}

			local msg = testGlobals.mockMsg({})
			local result = ucm.infoHandler(msg)
			local info = json.decode(result)

			assert.are.equal(0, info.activity.totalOrders)
			assert.are.equal(0, info.ucm.totalPairs)
		end)
	end)

	describe('matchesStatusFilter', function()
		it('should match ALL filter', function()
			local order = { status = 'active' }
			assert.is_true(ucm.matchesStatusFilter(order, 'all'))
		end)

		it('should match LISTED filter for active', function()
			local order = { status = 'active' }
			assert.is_true(ucm.matchesStatusFilter(order, 'listed'))
		end)

		it('should match LISTED filter for ready-for-settlement', function()
			local order = { status = 'ready-for-settlement' }
			assert.is_true(ucm.matchesStatusFilter(order, 'listed'))
		end)

		it('should match COMPLETED filter for executed', function()
			local order = { status = 'executed' }
			assert.is_true(ucm.matchesStatusFilter(order, 'completed'))
		end)

		it('should match COMPLETED filter for cancelled', function()
			local order = { status = 'cancelled' }
			assert.is_true(ucm.matchesStatusFilter(order, 'completed'))
		end)

		it('should not match wrong status', function()
			local order = { status = 'active' }
			assert.is_false(ucm.matchesStatusFilter(order, 'completed'))
		end)
	end)

	describe('getOrderHandler', function()
		local testGlobals = require('test_globals')
		local json = require('json')

		before_each(function()
			testGlobals.resetState()
		end)

		it('should return order by ID', function()
			_G.Orderbook = {
				['ant-token'] = {
					['ario-token'] = {
						orders = {
							['order-123'] = {
								id = 'order-123',
								quantity = '1',
								status = 'active',
							},
						},
					},
				},
			}

			_G.OrderIndex['order-123'] = {
				dominantToken = 'ant-token',
				swapToken = 'ario-token',
			}

			local msg = testGlobals.mockMsg({
				Tags = {
					['Order-Id'] = 'order-123',
				},
			})

			local result = ucm.getOrderHandler(msg)
			local order = json.decode(result)

			assert.are.equal('order-123', order.id)
			assert.are.equal('1', order.quantity)
		end)

		it('should fail if order not found', function()
			local msg = testGlobals.mockMsg({
				Tags = {
					['Order-Id'] = 'non-existent',
				},
			})

			local success = pcall(function()
				ucm.getOrderHandler(msg)
			end)

			assert.is_false(success)
		end)
	end)

	describe('Whitelist Management', function()
		local TEST_MODULE_ID = 'drhsJZSyX8InDsd5EAfQDTgdKnD_wvjddHKY3KDPdf8'
		local TEST_MODULE_ID_2 = '9afQ1PLf2mrshqCTZEzzJTR2gWaC9zHYWyqH3_1234'

		before_each(function()
			testGlobals.resetState()
		end)

		describe('whitelistModule', function()
			it('should add module to whitelist', function()
				local result = ucm.whitelistModule(TEST_MODULE_ID)
				
				assert.is_true(result)
				assert.is_true(WhitelistedModules[TEST_MODULE_ID])
			end)

			it('should reject invalid module ID', function()
				local success = pcall(function()
					ucm.whitelistModule('invalid-id')
				end)
				
				assert.is_false(success)
			end)

			it('should reject already whitelisted module', function()
				ucm.whitelistModule(TEST_MODULE_ID)
				
				local success = pcall(function()
					ucm.whitelistModule(TEST_MODULE_ID)
				end)
				
				assert.is_false(success)
			end)
		end)

		describe('unwhitelistModule', function()
			it('should remove module from whitelist', function()
				ucm.whitelistModule(TEST_MODULE_ID)
				
				local result = ucm.unwhitelistModule(TEST_MODULE_ID)
				
				assert.is_true(result)
				assert.is_nil(WhitelistedModules[TEST_MODULE_ID])
			end)

			it('should reject non-whitelisted module', function()
				local success = pcall(function()
					ucm.unwhitelistModule(TEST_MODULE_ID)
				end)
				
				assert.is_false(success)
			end)
		end)

		describe('whitelistModuleHandler', function()
			it('should whitelist via message handler', function()
				local msg = testGlobals.mockMsg({
					Tags = {
						['Module-Id'] = TEST_MODULE_ID,
					},
				})
				
				local result = ucm.whitelistModuleHandler(msg)
				local whitelist = json.decode(result)
				
				assert.is_true(WhitelistedModules[TEST_MODULE_ID])
				assert.is_true(whitelist[TEST_MODULE_ID])
			end)

			it('should require Module-Id tag', function()
				local msg = testGlobals.mockMsg({
					Tags = {},
				})
				
				local success = pcall(function()
					ucm.whitelistModuleHandler(msg)
				end)
				
				assert.is_false(success)
			end)
		end)

		describe('unwhitelistModuleHandler', function()
			it('should unwhitelist via message handler', function()
				ucm.whitelistModule(TEST_MODULE_ID)
				
				local msg = testGlobals.mockMsg({
					Tags = {
						['Module-Id'] = TEST_MODULE_ID,
					},
				})
				
				local result = ucm.unwhitelistModuleHandler(msg)
				local whitelist = json.decode(result)
				
				assert.is_nil(WhitelistedModules[TEST_MODULE_ID])
				assert.is_nil(whitelist[TEST_MODULE_ID])
			end)

			it('should require Module-Id tag', function()
				local msg = testGlobals.mockMsg({
					Tags = {},
				})
				
				local success = pcall(function()
					ucm.unwhitelistModuleHandler(msg)
				end)
				
				assert.is_false(success)
			end)
		end)
	end)
end)
