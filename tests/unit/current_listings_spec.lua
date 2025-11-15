print('\n=== Loading CurrentListings module for testing ===')
local testGlobals = require('test_globals')
local ucm = require('ucm')
print('✓ CurrentListings module loaded')

describe('CurrentListings', function()
	print('\n--- Starting CurrentListings tests ---')

	-- Token IDs for testing
	local ANT_TOKEN = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'
	local ARIO_TOKEN = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA'

	local sentMessages = {}

	before_each(function()
		sentMessages = {}
		testGlobals.resetState()
		_G.ACTIVITY_PROCESS = '7_psKu3QHwzc2PFCJk2lEwyitLJbz6Vj7hOcltOulj4'

		-- Override ao.send to track messages
		_G.ao.send = function(msg)
			table.insert(sentMessages, msg)
		end
	end)

	describe('Order creation', function()
		it('should create listing successfully', function()
			ucm.createOrder({
				orderId = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
				dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
				swapToken = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA',
				sender = 'SaXnsUgxJLkJRghWQOUs9-wB0npVviewTkUbh2Yk64M',
				quantity = 1,
				price = '500000000000',
				orderType = 'fixed',
				createdAt = '1722535710966',
				blockheight = '123456789',
				expirationTime = '1722535720966',
			})

			assert.is_not_nil(Orderbook[ANT_TOKEN])
			assert.is_not_nil(Orderbook[ANT_TOKEN][ARIO_TOKEN])
			-- Check dictionary has the order
			assert.is_not_nil(Orderbook[ANT_TOKEN][ARIO_TOKEN].orders['N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE'])
			assert.are.equal(
				'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
				Orderbook[ANT_TOKEN][ARIO_TOKEN].orders['N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE'].id
			)
		end)

		it('should reject listing with invalid quantity', function()
			ucm.createOrder({
				orderId = 'some-order-id',
				dominantToken = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA',
				swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
				sender = 'SaXnsUgxJLkJRghWQOUs9-wB0npVviewTkUbh2Yk64M',
				quantity = 0,
				price = '99000000',
				createdAt = '1722535710966',
				blockheight = '123456789',
				orderType = 'fixed',
				requestedOrderId = 'some-order-id',
			})

			-- No refund for invalid quantity (handleError checks quantity validity)
			assert.are.equal('Validation-Error', sentMessages[1].Action)
			-- Orderbook should remain empty (count dictionary keys)
			local pairCount = 0
			for _ in pairs(Orderbook) do
				pairCount = pairCount + 1
			end
			assert.are.equal(0, pairCount)
		end)

		it('should reject multi order with invalid quantity', function()
			Orderbook = {
				[ARIO_TOKEN] = {
					[ANT_TOKEN] = {
						pair = { ARIO_TOKEN, ANT_TOKEN },
						orders = {
							['order-1'] = {
								creator = 'LNtQf8SGZbHPeoksAqnVKfZvuGNgX4eH-xQYsFt_w-k',
								dateCreated = '1722535710966',
								id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
								originalQuantity = '10000000',
								price = '500000000000',
								quantity = '10000000',
								token = ARIO_TOKEN,
							},
							['order-2'] = {
								creator = 'LNtQf8SGZbHPeoksAqnVKfZvuGNgX4eH-xQYsFt_w-k',
								dateCreated = '1722535710966',
								id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
								originalQuantity = '10000000',
								price = '500000000000',
								quantity = '10000000',
								token = ARIO_TOKEN,
							},
						},
					},
				},
			}

			ucm.createOrder({
				orderId = tostring(1),
				dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
				swapToken = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA',
				sender = 'User' .. tostring(1),
				quantity = tostring(5500000000000),
				timestamp = os.time() + 1,
				blockheight = '123456789',
				transferDenomination = '1000000',
			})

			-- Orders should remain unchanged (count dictionary entries from the original pair)
			local orderCount = 0
			if Orderbook[ARIO_TOKEN] and Orderbook[ARIO_TOKEN][ANT_TOKEN] then
				for _ in pairs(Orderbook[ARIO_TOKEN][ANT_TOKEN].orders) do
					orderCount = orderCount + 1
				end
			end
			assert.are.equal(2, orderCount)
		end)
	end)

	-- CurrentListings has been removed - orders now have a 'status' field in Orderbook
	-- The Orderbook serves as the single source of truth for all orders regardless of status
end)
