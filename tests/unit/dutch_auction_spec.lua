print('\n=== Loading dutch_auction module for testing ===')
local ucm = require('ucm')
local testGlobals = require('test_globals')
print('✓ dutch_auction module loaded')

describe('Dutch Auction', function()
	print('\n--- Starting Dutch Auction tests ---')

	-- Token IDs for testing
	local ANT_TOKEN = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'
	local ARIO_TOKEN = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA'

	local transfers = {}
	local sentMessages = {}

	-- Setup and teardown
	before_each(function()
		transfers = {}
		sentMessages = {}

		-- Reset global state using the utility function
		testGlobals.resetState()

		-- Disable treasury fees for these tests
		_G.TREASURY_ADDRESS = nil

		-- Override ao.send to track messages and transfers
		_G.ao.send = function(msg)
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

	describe('ANT sell order (Dutch auction)', function()
		it('should add ANT sell order to orderbook', function()
			ucm.createOrder({
				orderId = 'ant-sell-order',
				dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT
				swapToken = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA', -- ARIO
				sender = 'ant-seller',
				quantity = 1,
				price = '500000000000',
				createdAt = '1735689600000',
				blockheight = '123456789',
				orderType = 'dutch',
				orderGroupId = 'test-group',
				expirationTime = '1736035200000',
				minimumPrice = '100000000000',
				decreaseInterval = '86400000',
				msg = { Tags = { Quantity = '1' }, From = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
			})

			-- Validate no transfers occurred (just adding to orderbook)
			assert.are.equal(0, #transfers)

			-- Validate orderbook structure (nested dictionary)
			assert.is_not_nil(Orderbook)
			assert.is_not_nil(Orderbook[ANT_TOKEN], 'Orderbook should have ANT token entry')
			assert.is_not_nil(Orderbook[ANT_TOKEN][ARIO_TOKEN], 'Orderbook should have pair entry')
			assert.are.same({ ANT_TOKEN, ARIO_TOKEN }, Orderbook[ANT_TOKEN][ARIO_TOKEN].pair)
			assert.is_not_nil(Orderbook[ANT_TOKEN][ARIO_TOKEN].orders, 'Orderbook pair should have orders table')
			assert.is_table(Orderbook[ANT_TOKEN][ARIO_TOKEN].orders)

			-- Dutch auction now uses dictionary-style orders (lookup table)!
			local count = 0
			for _ in pairs(Orderbook[ANT_TOKEN][ARIO_TOKEN].orders) do
				count = count + 1
			end
			assert.are.equal(1, count)
			local order = Orderbook[ANT_TOKEN][ARIO_TOKEN].orders['ant-sell-order']
			assert.is_not_nil(order, 'Order should exist')
			assert.are.equal('ant-sell-order', order.id)
			assert.are.equal('ant-seller', order.creator)
			assert.are.equal('1', order.quantity)
			assert.are.equal('500000000000', order.price)
			assert.are.equal('100000000000', order.minimumPrice)
			assert.are.equal('86400000', order.decreaseInterval)
			assert.are.equal('dutch', order.orderType)
			assert.is_not_nil(order.decreaseStep)
		end)
	end)

	describe('ARIO buy order matching Dutch auction', function()
		it('should match ARIO buy order with ANT sell order at current Dutch price', function()
			-- Setup: Create ANT sell order first (nested dictionary structure)
			_G.Orderbook[ANT_TOKEN] = {
				[ARIO_TOKEN] = {
					pair = { ANT_TOKEN, ARIO_TOKEN },
					orders = {
						['ant-sell-order'] = {
							id = 'ant-sell-order',
							creator = 'ant-seller',
							token = ANT_TOKEN,
							quantity = '1',
							originalQuantity = '1',
							price = '500000000000',
							dateCreated = 1735689600000,
							expirationTime = 1736035200000,
							minimumPrice = '100000000000',
							decreaseInterval = '86400000',
							decreaseStep = '100000000000',
							orderType = 'dutch',
							status = 'active',
						},
					},
				},
			}

			-- Add to OrderIndex for O(1) lookup
			_G.OrderIndex['ant-sell-order'] = {
				dominantToken = ANT_TOKEN,
				swapToken = ARIO_TOKEN,
			}

			-- Buy order: Send 500000000000 ARIO to buy 1 ANT at current Dutch price
			print('DEBUG: Orderbook before buy order')
			if Orderbook[ANT_TOKEN] and Orderbook[ANT_TOKEN][ARIO_TOKEN] then
				local pair = Orderbook[ANT_TOKEN][ARIO_TOKEN]
				print('  Pair exists:', pair.pair[1], pair.pair[2])
				local orderCount = 0
				for _ in pairs(pair.orders) do
					orderCount = orderCount + 1
				end
				print('  Orders count:', orderCount)
				if orderCount > 0 then
					local order = pair.orders['ant-sell-order']
					if order then
						print('  Order ID:', order.id)
						print('  Order Type:', order.orderType)
						print('  Are they equal?:', order.id == 'ant-sell-order')
					end
				end
			end
			ucm.createOrder({
				orderId = 'ario-buy-order',
				dominantToken = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA', -- ARIO
				swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT
				sender = 'ario-buyer',
				quantity = 500000000000, -- Paying 500B ARIO (as number)
				createdAt = '1735689600000', -- Same timestamp, so price hasn't decreased yet
				blockheight = '123456790',
				orderType = 'dutch',
				requestedOrderId = 'ant-sell-order',
				msg = { Tags = { Quantity = '500000000000' }, From = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA' },
			})

			print('DEBUG: Orderbook after buy order')
			local totalPairs = 0
			for dominantToken, swapTokens in pairs(Orderbook) do
				for swapToken, pair in pairs(swapTokens) do
					totalPairs = totalPairs + 1
					local pairOrderCount = 0
					for _ in pairs(pair.orders) do
						pairOrderCount = pairOrderCount + 1
					end
					print('  Pair:', dominantToken, '->', swapToken, '- Orders:', pairOrderCount)
				end
			end
			print('  Total pairs:', totalPairs)

			-- Validate transfers occurred
			print('DEBUG Dutch matching: Transfer count:', #transfers)
			for i, t in ipairs(transfers) do
				print('  Transfer', i, ':', t.action, 'of', t.quantity, 'to', t.recipient, 'at', t.target)
			end
			print('DEBUG: Sent messages count in matching test:', #sentMessages)
			for i, msg in ipairs(sentMessages) do
				print('  Message', i, ':', msg.Action, 'to', msg.Target)
				if msg.Tags and msg.Tags.Message then
					print('    Message text:', msg.Tags.Message)
				end
			end
			assert.are.equal(2, #transfers, 'Should have 2 transfers (ARIO to seller, ANT to buyer)')

			-- Check ARIO transfer to seller
			assert.are.equal('Transfer', transfers[1].action)
			assert.are.equal('agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA', transfers[1].target)
			assert.are.equal('ant-seller', transfers[1].recipient)
			-- Should be 500000000000 * 0.995 = 497500000000 (after 0.5% fee)

			-- Check ANT transfer to buyer
			assert.are.equal('Transfer', transfers[2].action)
			assert.are.equal('xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', transfers[2].target)
			assert.are.equal('ario-buyer', transfers[2].recipient)
			assert.are.equal('1', transfers[2].quantity)

			-- Order should be removed from orderbook (dictionary-style)
			local remainingCount = 0
			if Orderbook[ANT_TOKEN] and Orderbook[ANT_TOKEN][ARIO_TOKEN] then
				for _ in pairs(Orderbook[ANT_TOKEN][ARIO_TOKEN].orders) do
					remainingCount = remainingCount + 1
				end
			end
			assert.are.equal(0, remainingCount, 'Matched order should be removed from orderbook')
		end)

		it('should apply price reduction over time in Dutch auction', function()
			-- Setup: Create ANT sell order (nested dictionary structure)
			_G.Orderbook = {
				[ANT_TOKEN] = {
					[ARIO_TOKEN] = {
						pair = { ANT_TOKEN, ARIO_TOKEN },
						orders = {
							['ant-sell-order'] = {
								id = 'ant-sell-order',
								creator = 'ant-seller',
								token = ANT_TOKEN,
								quantity = '1',
								originalQuantity = '1',
								price = '500000000000',
								dateCreated = 1735689600000,
								expirationTime = 1736035200000,
								minimumPrice = '100000000000',
								decreaseInterval = '86400000', -- 1 day
								decreaseStep = '100000000000', -- Decreases by 100B per day
								orderType = 'dutch',
								status = 'active',
							},
						},
					},
				},
			}
			-- Add to OrderIndex for O(1) lookup
			_G.OrderIndex['ant-sell-order'] = {
				dominantToken = ANT_TOKEN,
				swapToken = ARIO_TOKEN,
			}

			-- Buy order 1 day later: Price should have decreased by 100B (one interval)
			-- New price: 500B - 100B = 400B
			ucm.createOrder({
				orderId = 'ario-buy-order-2',
				dominantToken = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA',
				swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
				sender = 'ario-buyer-2',
				quantity = 400000000000, -- Paying reduced price (as number)
				createdAt = '1735776000000', -- 1 day later (86400000ms)
				blockheight = '123456791',
				orderType = 'dutch',
				requestedOrderId = 'ant-sell-order',
				msg = { Tags = { Quantity = '400000000000' }, From = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA' },
			})

			-- Validate transfers occurred
			assert.are.equal(2, #transfers)

			-- Buyer should receive 1 ANT
			assert.are.equal('1', transfers[2].quantity)
		end)
	end)

	describe('Dutch auction validation', function()
		it('should reject order without minimum price', function()
			local success = pcall(function()
				ucm.createOrder({
					orderId = 'invalid-order',
					dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
					swapToken = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA',
					sender = 'test-sender',
					quantity = 1,
					price = '500000000000',
					createdAt = '1735689600000',
					blockheight = '123456789',
					orderType = 'dutch',
					expirationTime = '1736035200000',
					-- minimumPrice missing
					decreaseInterval = '86400000',
					msg = { Tags = { Quantity = '1' }, From = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
				})
			end)

			-- Dutch auction validation sends Transfer (refund) first, then Validation-Error
			assert.is_false(success)
			assert.is_true(#sentMessages >= 2, 'Should have at least two messages (refund + error)')
			assert.are.equal('Transfer', sentMessages[1].Action)
			assert.are.equal('Validation-Error', sentMessages[2].Action)
		end)

		it('should reject order without decrease interval', function()
			local success = pcall(function()
				ucm.createOrder({
					orderId = 'invalid-order-2',
					dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
					swapToken = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA',
					sender = 'test-sender',
					quantity = 1,
					price = '500000000000',
					createdAt = '1735689600000',
					blockheight = '123456789',
					orderType = 'dutch',
					expirationTime = '1736035200000',
					minimumPrice = '100000000000',
					-- decreaseInterval missing
					msg = { Tags = { Quantity = '1' }, From = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
				})
			end)

			-- Dutch auction validation sends Transfer (refund) first, then Validation-Error
			assert.is_false(success)
			assert.is_true(#sentMessages >= 2, 'Should have at least two messages (refund + error)')
			assert.are.equal('Transfer', sentMessages[1].Action)
			assert.are.equal('Validation-Error', sentMessages[2].Action)
		end)
	end)
end)
