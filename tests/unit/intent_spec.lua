print('\n=== Loading intents module for testing ===')
local testGlobals = require('test_globals')
local intents = require('intents')
local constants = require('constants')
local bint = require('.bint')(256)
print('✓ intents module loaded')

-- Test constants
local TEST_ANT_PROCESS_ID = 'test-ant-process-123' .. (string.rep('0', 43 - #'test-ant-process-123'))

describe('Intent Management', function()
	print('\n--- Starting Intent Management tests ---')
	before_each(function()
		-- Reset global state
		testGlobals.resetState()
	end)

	describe('createIntent', function()
		it('should create an intent with correct structure', function()
			-- Setup balance for listing fee
			ARIOBalances['user-address-abc'] = { balance = '10000000000', orders = {} } -- 10,000 ARIO

			local msg = {
				Id = 'test-intent-123',
				From = 'user-address-abc',
				Timestamp = 1234567890,
			}

			local orderParams = {
				orderType = 'fixed',
				swapToken = ARIO_TOKEN_PROCESS_ID,
				quantity = '1',
				price = '5000000000',
			}

			local intent = intents.createIntent(msg, orderParams, TEST_ANT_PROCESS_ID)

			-- Verify intent structure
			assert.is_not_nil(intent.intentId)
			assert.are.equal('user-address-abc', intent.initiator)
			assert.are.equal('Create-Order', intent.action)
			assert.are.equal('pending', intent.status)
			assert.are.equal(1234567890, intent.createdAt)
			assert.are.equal(1234567890 + constants.TIME.ONE_DAY_MS, intent.ttl)
			assert.is_nil(intent.resolvedAt)
			assert.is_nil(intent.completedAt)
			assert.is_nil(intent.failureReason)
			assert.are.same(orderParams, intent.orderParams)
		end)

		it('should add intent to Intents table', function()
			ARIOBalances['user-xyz'] = { balance = '10000000000', orders = {} }

			local msg = {
				Id = 'test-intent-456',
				From = 'user-xyz',
				Timestamp = 1234567890,
			}

			local orderParams = {
				quantity = '1',
			}

			local intent = intents.createIntent(msg, orderParams, TEST_ANT_PROCESS_ID)

			-- Check that the intent exists in Intents table
			assert.is_not_nil(Intents[intent.intentId])
			assert.are.equal('user-xyz', Intents[intent.intentId].initiator)
			assert.are.equal('Create-Order', Intents[intent.intentId].action)
		end)

		it('should charge base listing fee (1 ARIO) when no expiration time', function()
			ARIOBalances['user-abc'] = { balance = '10000000', orders = {} } -- 10 ARIO

			local msg = {
				From = 'user-abc',
				Timestamp = 1000000,
			}

			local orderParams = {
				quantity = '1',
			}

			intents.createIntent(msg, orderParams, TEST_ANT_PROCESS_ID)

			-- Fee should be 1 ARIO (base fee)
			assert.are.equal(tostring(bint('9000000')), ARIOBalances['user-abc'].balance)
			assert.are.equal('1000000', ARIOBalances[TREASURY_ADDRESS].balance)
		end)

		it('should charge listing fee based on expiration time', function()
			ARIOBalances['user-abc'] = { balance = '100000000', orders = {} } -- 100 ARIO

			local msg = {
				From = 'user-abc',
				Timestamp = 1000000,
			}

			-- Set expiration to 48 hours from now
			local expirationTime = 1000000 + (48 * 3600000)
			local orderParams = {
				expirationTime = tostring(expirationTime),
				quantity = '1',
			}

			intents.createIntent(msg, orderParams, TEST_ANT_PROCESS_ID)

			-- Fee should be 48 ARIO (48 hours at 1 ARIO per hour)
			assert.are.equal(tostring(bint('100000000') - bint('48000000')), ARIOBalances['user-abc'].balance)
			assert.are.equal('48000000', ARIOBalances[TREASURY_ADDRESS].balance)
		end)

		it('should fail if insufficient balance for listing fee', function()
			ARIOBalances['user-abc'] = { balance = '500000', orders = {} } -- 0.5 ARIO (not enough)

			local msg = {
				From = 'user-abc',
				Timestamp = 1000000,
			}

			local orderParams = {
				quantity = '1',
			}

			assert.has_error(function()
				intents.createIntent(msg, orderParams, TEST_ANT_PROCESS_ID)
			end)
		end)

		it('should increment intent counter for each new intent', function()
			ARIOBalances['user-abc'] = { balance = '50000000', orders = {} }

			local msg = {
				From = 'user-abc',
				Timestamp = 1000000,
			}

			local orderParams = {
				quantity = '1',
			}

			local intent1 =
				intents.createIntent(msg, orderParams, 'test-ant-1-' .. (string.rep('0', 43 - #'test-ant-1-')))
			local intent2 =
				intents.createIntent(msg, orderParams, 'test-ant-2-' .. (string.rep('0', 43 - #'test-ant-2-')))
			local intent3 =
				intents.createIntent(msg, orderParams, 'test-ant-3-' .. (string.rep('0', 43 - #'test-ant-3-')))

			assert.is_not_nil(intent1.intentId)
			assert.is_not_nil(intent2.intentId)
			assert.is_not_nil(intent3.intentId)
			assert.are_not.equal(intent1.intentId, intent2.intentId)
			assert.are_not.equal(intent2.intentId, intent3.intentId)
		end)

		it('should store different order parameters correctly', function()
			ARIOBalances['user-abc'] = { balance = '10000000000', orders = {} }

			local msg = {
				From = 'user-abc',
				Timestamp = 1000000,
			}

			local orderParams = {
				orderType = 'dutch',
				swapToken = ARIO_TOKEN_PROCESS_ID,
				quantity = '1',
				price = '50000000000',
				minimumPrice = '10000000000',
				decreaseInterval = '3600000',
			}

			local intent = intents.createIntent(msg, orderParams, TEST_ANT_PROCESS_ID)

			assert.are.equal('dutch', intent.orderParams.orderType)
			assert.are.equal('50000000000', intent.orderParams.price)
			assert.are.equal('10000000000', intent.orderParams.minimumPrice)
			assert.are.equal('3600000', intent.orderParams.decreaseInterval)
		end)
	end)

	describe('resolveIntent', function()
		it('should transition intent from pending to active', function()
			ARIOBalances['user-abc'] = { balance = '10000000000', orders = {} }

			local msg = {
				From = 'user-abc',
				Timestamp = 1000000,
			}

			local intent = intents.createIntent(msg, { quantity = '1', expirationTime = 4600000 }, TEST_ANT_PROCESS_ID)
			assert.are.equal('pending', intent.status)

			intents.resolveIntent(intent.intentId, 1000500)

			assert.are.equal('active', Intents[intent.intentId].status)
			assert.are.equal(1000500, Intents[intent.intentId].resolvedAt)
		end)

		it('should return false for non-existent intent', function()
			local success = intents.resolveIntent('non-existent-id', 1000000)
			assert.is_false(success)
		end)
	end)

	describe('updateIntentStatus', function()
		it('should update intent to completed and prune it', function()
			ARIOBalances['user-abc'] = { balance = '10000000000', orders = {} }

			local msg = {
				From = 'user-abc',
				Timestamp = 1000000,
			}

			local intent = intents.createIntent(msg, { quantity = '1', expirationTime = 4600000 }, TEST_ANT_PROCESS_ID)

			intents.updateIntentStatus(intent.intentId, 'completed', msg)

			-- Intent should be pruned after completion
			assert.is_nil(Intents[intent.intentId])
		end)

		it('should return false for non-existent intent', function()
			local msg = { From = 'user-abc', Timestamp = 1000000 }
			local success = intents.updateIntentStatus('non-existent-id', 'completed', msg)
			assert.is_false(success)
		end)
	end)

	describe('failIntent', function()
		it('should mark intent as failed with reason and prune it', function()
			ARIOBalances['user-abc'] = { balance = '10000000000', orders = {} }

			local msg = {
				From = 'user-abc',
				Timestamp = 1000000,
			}

			local intent = intents.createIntent(msg, { quantity = '1', expirationTime = 4600000 }, TEST_ANT_PROCESS_ID)

			intents.failIntent(intent.intentId, 'Test failure reason')

			-- Intent should be pruned after failure
			assert.is_nil(Intents[intent.intentId])
		end)

		it('should return false for non-existent intent', function()
			local success = intents.failIntent('non-existent-id', 'Some error')
			assert.is_false(success)
		end)
	end)

	describe('getIntentById', function()
		it('should retrieve intent by ID', function()
			ARIOBalances['user-abc'] = { balance = '10000000000', orders = {} }

			local msg = {
				From = 'user-abc',
				Timestamp = 1000000,
			}

			local intent = intents.createIntent(msg, { quantity = '1', expirationTime = 4600000 }, TEST_ANT_PROCESS_ID)

			local retrieved = intents.getIntentById(intent.intentId)
			assert.is_not_nil(retrieved)
			if retrieved then
				assert.are.equal(intent.intentId, retrieved.intentId)
				assert.are.equal('user-abc', retrieved.initiator)
			end
		end)

		it('should return nil for non-existent intent', function()
			local retrieved = intents.getIntentById('non-existent-id')
			assert.is_nil(retrieved)
		end)
	end)

	describe('getAllIntents', function()
		it('should return all intents as an array', function()
			ARIOBalances['user-abc'] = { balance = '50000000000', orders = {} }

			local msg = {
				From = 'user-abc',
				Timestamp = 1000000,
			}

			intents.createIntent(
				msg,
				{ quantity = '1', expirationTime = 4600000 },
				'test-ant-a-' .. (string.rep('0', 43 - #'test-ant-a-'))
			)
			intents.createIntent(
				msg,
				{ quantity = '2', expirationTime = 4600000 },
				'test-ant-b-' .. (string.rep('0', 43 - #'test-ant-b-'))
			)
			intents.createIntent(
				msg,
				{ quantity = '3', expirationTime = 4600000 },
				'test-ant-c-' .. (string.rep('0', 43 - #'test-ant-c-'))
			)

			local allIntents = intents.getAllIntents()
			assert.are.equal(3, #allIntents)
		end)

		it('should return empty array when no intents exist', function()
			local allIntents = intents.getAllIntents()
			assert.are.equal(0, #allIntents)
		end)
	end)

	describe('calculateListingFee', function()
		it('should return base fee for no expiration time', function()
			local fee, err = intents.calculateListingFee(nil, 1000000)
			assert.is_nil(err)
			assert.are.equal('1000000', fee) -- 1 ARIO
		end)

		it('should calculate fee based on hours (1 ARIO per hour)', function()
			local currentTime = 1000000
			local expirationTime = currentTime + (10 * 3600000) -- 10 hours

			local fee, err = intents.calculateListingFee(tostring(expirationTime), currentTime)
			assert.is_nil(err)
			assert.are.equal('10000000', fee) -- 10 ARIO
		end)

		it('should use minimum of 1 hour for short durations', function()
			local currentTime = 1000000
			local expirationTime = currentTime + 1800000 -- 30 minutes

			local fee, err = intents.calculateListingFee(tostring(expirationTime), currentTime)
			assert.is_nil(err)
			assert.are.equal('1000000', fee) -- 1 ARIO (minimum)
		end)

		it('should fail for expiration time in the past', function()
			local currentTime = 1000000
			local expirationTime = currentTime - 3600000 -- 1 hour ago

			local fee, err = intents.calculateListingFee(tostring(expirationTime), currentTime)
			assert.is_not_nil(err)
			assert.is_nil(fee)
		end)

		it('should fail for expiration time exceeding 30 days', function()
			local currentTime = 1000000
			local expirationTime = currentTime + (31 * 24 * 3600000) -- 31 days

			local fee, err = intents.calculateListingFee(tostring(expirationTime), currentTime)
			assert.is_not_nil(err)
			assert.is_nil(fee)
		end)

		it('should fail for invalid expiration time format', function()
			local fee, err = intents.calculateListingFee('not-a-number', 1000000)
			assert.is_not_nil(err)
			assert.is_nil(fee)
		end)
	end)
end)
