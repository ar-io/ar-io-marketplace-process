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
					Id = 'order-1',
					Quantity = '1000',
					Price = '100',
				},
			}
			local args = { blockheight = '1000' }
			local currentToken = 'TOKEN_ID_1234567890123456789012345678901234'

			local sumVolume = fixed_price.updateVwapData(pair, matches, args, currentToken)

			-- Expected: volume = 1000, price = 100, vwap = (1000 * 100) / 1000 = 100
			assert.are.equal(bint(1000), sumVolume)
			assert.is_not_nil(pair.PriceData)
			assert.are.equal('100', pair.PriceData.Vwap)
			assert.are.equal('1000', pair.PriceData.Block)
			assert.are.equal(currentToken, pair.PriceData.DominantToken)
			assert.are.same(matches, pair.PriceData.MatchLogs)
		end)

		it('should calculate VWAP correctly for multiple matches', function()
			local pair = { orders = {} }
			local matches = {
				{
					Id = 'order-1',
					Quantity = '1000',
					Price = '100',
				},
				{
					Id = 'order-2',
					Quantity = '2000',
					Price = '150',
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
			assert.is_not_nil(pair.PriceData)
			assert.are.equal('133', pair.PriceData.Vwap)
			assert.are.equal('2000', pair.PriceData.Block)
		end)

		it('should handle large volume and price values', function()
			local pair = { orders = {} }
			local matches = {
				{
					Id = 'order-1',
					Quantity = '1000000000000',
					Price = '50000000',
				},
			}
			local args = { blockheight = '5000' }
			local currentToken = 'TOKEN_ID_1234567890123456789012345678901234'

			local sumVolume = fixed_price.updateVwapData(pair, matches, args, currentToken)

			assert.are.equal(bint('1000000000000'), sumVolume)
			assert.is_not_nil(pair.PriceData)
			-- vwap = (1000000000000 * 50000000) / 1000000000000 = 50000000
			assert.are.equal('50000000', pair.PriceData.Vwap)
		end)

		it('should floor VWAP to integer', function()
			local pair = { orders = {} }
			local matches = {
				{
					Id = 'order-1',
					Quantity = '3',
					Price = '10',
				},
			}
			local args = { blockheight = '3000' }
			local currentToken = 'TOKEN_ID_1234567890123456789012345678901234'

			local sumVolume = fixed_price.updateVwapData(pair, matches, args, currentToken)

			-- vwap = (3 * 10) / 3 = 10
			assert.are.equal(bint(3), sumVolume)
			assert.are.equal('10', pair.PriceData.Vwap)
		end)
	end)
end)
