print('\n=== Loading intents module for testing ===')
local testGlobals = require('test_globals')
local intents = require('intents')
local constants = require('constants')
local bint = require('.bint')(256)
print('✓ intents module loaded')

describe('Intent Management', function()
	print('\n--- Starting Intent Management tests ---')
	before_each(function()
		-- Reset global state
		testGlobals.resetState()
	end)

	describe('createParent', function()
		it('should create a parent intent with correct structure', function()
			-- Setup balance for listing fee
			ARIOBalances['user-address-abc'] = {balance = '10000000000', orders = {}} -- 10 ARIO
			
			local msg = {
				Id = 'test-intent-123',
				From = 'user-address-abc',
				Timestamp = 1234567890,
			}

			local forwardedTags = {
				['X-Intent-Order-Type'] = 'fixed',
				['X-Intent-Swap-Token'] = 'token-xyz',
			}

			local intent = intents.createParentIntent(msg, 'Create-Order', forwardedTags)

			-- Intent ID is auto-generated, not using message ID
			assert.is_not_nil(intent.intentId)
			assert.are.equal('parent', intent.type)
			assert.are.equal('user-address-abc', intent.initiator)
			assert.are.equal('Create-Order', intent.action)
			assert.are.equal('pending', intent.status)
			assert.are.equal(1234567890, intent.createdAt)
			assert.is_nil(intent.parentIntentId)
			assert.is_table(intent.childIntentIds)
			assert.are.same(forwardedTags, intent.forwardedTags)
		end)

		it('should add parent intent to Intents table', function()
			ARIOBalances['user-xyz'] = {balance = '10000000000', orders = {}}
			
			local msg = {
				Id = 'test-intent-456',
				From = 'user-xyz',
				Timestamp = 1234567890,
			}

			local intent = intents.createParentIntent(msg, 'Cancel-Order', {})

			-- Check that the intent exists in Intents table using the auto-generated ID
			assert.is_not_nil(Intents[intent.intentId])
			assert.are.equal('parent', Intents[intent.intentId].type)
		end)
	end)

	describe('createChild', function()
		it('should create a child intent with correct structure', function()
			ARIOBalances['user-abc'] = {balance = '10000000000', orders = {}}
			
			-- First create parent
			local parentMsg = {
				Id = 'parent-123',
				From = 'user-abc',
				Timestamp = 1234567890,
			}
			local parentIntent = intents.createParentIntent(parentMsg, 'Create-Order', {})

			-- Create child
			local childMsg = {
				Id = 'msg-789',
				Timestamp = 1234567900,
			}

			local forwardedTags = {
				Recipient = 'seller-address',
				Quantity = '1000',
				Token = 'token-process-id',
			}

			local childIntent = intents.createChildIntent(parentIntent.intentId, childMsg, 'token-process-id', forwardedTags)

			assert.are.equal('child', childIntent.type)
			assert.are.equal(parentIntent.intentId, childIntent.parentIntentId)
			assert.are.equal('Transfer', childIntent.action)
			assert.are.equal('Debit-Notice', childIntent.expectedMessage)
			assert.are.equal('token-process-id', childIntent.expectedFrom)
			assert.are.equal('pending', childIntent.status)
			assert.are.same(forwardedTags, childIntent.forwardedTags)
		end)

		it("should add child to parent's ChildIntentIds map", function()
			ARIOBalances['user-xyz'] = {balance = '10000000000', orders = {}}
			
			-- Create parent
			local parentMsg = {
				Id = 'parent-456',
				From = 'user-xyz',
				Timestamp = 1234567890,
			}
			local parentIntent = intents.createParentIntent(parentMsg, 'Create-Order', {})

			-- Create child
			local childMsg = {
				Id = 'msg-111',
				Timestamp = 1234567900,
			}

			local childIntent = intents.createChildIntent(parentIntent.intentId, childMsg, 'token-123', {})

			local parent = Intents[parentIntent.intentId]
			assert.is_true(parent.childIntentIds[childIntent.intentId])
		end)
	end)

	describe('resolve', function()
		it('should update parent status from pending to active', function()
			ARIOBalances['user-abc'] = {balance = '10000000000', orders = {}}
			
			local msg = {
				Id = 'parent-789',
				From = 'user-abc',
				Timestamp = 1234567890,
			}
			local intent = intents.createParentIntent(msg, 'Create-Order', {})

			local result = intents.resolveIntent(intent.intentId, 1234567900)

			assert.is_true(result)
			assert.are.equal('active', Intents[intent.intentId].status)
			assert.are.equal(1234567900, Intents[intent.intentId].resolvedAt)
		end)

	it('should update child status to resolved', function()
		ARIOBalances['user-abc'] = {balance = '10000000000', orders = {}}
		
		-- Create parent
		local parentMsg = {
			Id = 'parent-999',
			From = 'user-abc',
			Timestamp = 1234567890,
		}
		local parentIntent = intents.createParentIntent(parentMsg, 'Create-Order', {})

		-- Create TWO children so resolving one doesn't complete the parent
		local childMsg1 = {
			Id = 'msg-222',
			Timestamp = 1234567900,
		}
		local childIntent1 = intents.createChildIntent(parentIntent.intentId, childMsg1, 'token-123', {})
		
		local childMsg2 = {
			Id = 'msg-333',
			Timestamp = 1234567900,
		}
		local childIntent2 = intents.createChildIntent(parentIntent.intentId, childMsg2, 'token-456', {})

		local result = intents.resolveIntent(childIntent1.intentId, 1234567950)

		assert.is_true(result)
		assert.are.equal('resolved', Intents[childIntent1.intentId].status)
		assert.are.equal(1234567950, Intents[childIntent1.intentId].resolvedAt)
		-- Second child should still be pending
		assert.are.equal('pending', Intents[childIntent2.intentId].status)
	end)

		it('should return false for non-existent intent', function()
			local result = intents.resolveIntent('non-existent-id', 1234567890)
			assert.is_false(result)
		end)
	end)

	describe('fail', function()
		it('should mark intent as failed with reason and then prune it', function()
			ARIOBalances['user-abc'] = {balance = '10000000000', orders = {}}
			
			local msg = {
				Id = 'parent-fail',
				From = 'user-abc',
				Timestamp = 1234567890,
			}
			local intent = intents.createParentIntent(msg, 'Create-Order', {})

			local result = intents.failIntent(intent.intentId, 'Insufficient balance')

			assert.is_true(result)
			-- Intent should be pruned after reaching terminal failed state
			assert.is_nil(Intents[intent.intentId])
		end)

		it('should return false for non-existent intent', function()
			local result = intents.failIntent('non-existent', 'Some reason')
			assert.is_false(result)
		end)
	end)

	describe('updateStatus', function()
		it('should update intent status', function()
			ARIOBalances['user-abc'] = {balance = '10000000000', orders = {}}
			
			local msg = {
				Id = 'parent-status',
				From = 'user-abc',
				Timestamp = 1234567890,
			}
			local intent = intents.createParentIntent(msg, 'Create-Order', {})

			local result = intents.updateIntentStatus(intent.intentId, 'settling')

			assert.is_true(result)
			assert.are.equal('settling', Intents[intent.intentId].status)
		end)

		it('should set CompletedAt when status is completed and then prune it', function()
			ARIOBalances['user-abc'] = {balance = '10000000000', orders = {}}
			
			local msg = {
				Id = 'parent-complete',
				From = 'user-abc',
				Timestamp = 1234567890,
			}
			local intent = intents.createParentIntent(msg, 'Create-Order', {})

		-- Mark as active first (required before completed transition)
		intents.resolveIntent(intent.intentId, 1234567900)

		intents.updateIntentStatus(intent.intentId, 'completed')

			-- Intent should be pruned after reaching terminal completed state
			assert.is_nil(Intents[intent.intentId])
		end)
	end)

	describe('getById', function()
		it('should return intent by ID', function()
			ARIOBalances['user-abc'] = {balance = '10000000000', orders = {}}
			
			local msg = {
				Id = 'test-get',
				From = 'user-abc',
				Timestamp = 1234567890,
			}
			local createdIntent = intents.createParentIntent(msg, 'Create-Order', {})

			local intent = intents.getIntentById(createdIntent.intentId)

			assert.is_not_nil(intent)
			---@diagnostic disable-next-line: need-check-nil
			assert.are.equal(createdIntent.intentId, intent.intentId)
		end)

		it('should return nil for non-existent intent', function()
			local intent = intents.getIntentById('non-existent')
			assert.is_nil(intent)
		end)
	end)

	describe('getPending', function()
		it('should return all pending parent intents', function()
			ARIOBalances['user-1'] = {balance = '10000000000', orders = {}}
			ARIOBalances['user-2'] = {balance = '10000000000', orders = {}}
			
			-- Create pending parent
			local msg1 = {
				Id = 'pending-1',
				From = 'user-1',
				Timestamp = 1234567890,
			}
			local pendingIntent = intents.createParentIntent(msg1, 'Create-Order', {})

			-- Create active parent
			local msg2 = {
				Id = 'active-1',
				From = 'user-2',
				Timestamp = 1234567890,
			}
			local activeIntent = intents.createParentIntent(msg2, 'Create-Order', {})
			intents.resolveIntent(activeIntent.intentId, 1234567900)

			local pending = intents.getPendingIntents()

			assert.are.equal(1, #pending)
			assert.are.equal(pendingIntent.intentId, pending[1].intentId)
		end)
	end)

	describe('getByStatus', function()
		it('should return intents filtered by status', function()
			ARIOBalances['user-1'] = {balance = '10000000000', orders = {}}
			ARIOBalances['user-2'] = {balance = '10000000000', orders = {}}
			
			-- Create various intents
			local msg1 = {
				Id = 'intent-1',
				From = 'user-1',
				Timestamp = 1234567890,
			}
			intents.createParentIntent(msg1, 'Create-Order', {})

			local msg2 = {
				Id = 'intent-2',
				From = 'user-2',
				Timestamp = 1234567890,
			}
			local failedIntent = intents.createParentIntent(msg2, 'Cancel-Order', {})
			intents.failIntent(failedIntent.intentId, 'Some error')

			local failed = intents.getIntentsByStatus('failed')

			-- Failed intents are immediately pruned, so we expect 0
			-- This is by design for memory management
			assert.are.equal(0, #failed)
		end)
	end)

	describe('validateExists', function()
		it('should return true for existing intent', function()
			ARIOBalances['user-1'] = {balance = '10000000000', orders = {}}
			
			local msg = {
				Id = 'exists-1',
				From = 'user-1',
				Timestamp = 1234567890,
			}
			local intent = intents.createParentIntent(msg, 'Create-Order', {})

			assert.is_true(intents.validateIntentExists(intent.intentId))
		end)

		it('should return false for non-existent intent', function()
			assert.is_false(intents.validateIntentExists('does-not-exist'))
		end)
	end)

	describe('getAllIntents', function()
		it('should return all intents as array', function()
			ARIOBalances['user-1'] = {balance = '10000000000', orders = {}}
			ARIOBalances['user-2'] = {balance = '10000000000', orders = {}}
			
			local msg1 = {
				Id = 'intent-1',
				From = 'user-1',
				Timestamp = 1234567890,
			}
			intents.createParentIntent(msg1, 'Create-Order', {})

			local msg2 = {
				Id = 'intent-2',
				From = 'user-2',
				Timestamp = 1234567890,
			}
			intents.createParentIntent(msg2, 'Cancel-Order', {})

			local all = intents.getAllIntents()

			assert.are.equal(2, #all)
		end)
	end)

	describe('areAllChildrenResolved', function()
	it('should return true when all children are resolved', function()
		ARIOBalances['user-abc'] = {balance = '10000000000', orders = {}}
		
		-- Create parent
		local parentMsg = {
			Id = 'parent-check',
			From = 'user-abc',
			Timestamp = 1234567890,
		}
		local parentIntent = intents.createParentIntent(parentMsg, 'Create-Order', {})

		-- Create children
		local childMsg1 = {
			Id = 'child-1',
			Timestamp = 1234567900,
		}
		local child1 = intents.createChildIntent(parentIntent.intentId, childMsg1, 'token-1', {})

		local childMsg2 = {
			Id = 'child-2',
			Timestamp = 1234567900,
		}
		local child2 = intents.createChildIntent(parentIntent.intentId, childMsg2, 'token-2', {})

		-- Manually set both children to resolved status (without triggering completion)
		Intents[child1.intentId].status = constants.INTENT_STATUSES.RESOLVED
		Intents[child2.intentId].status = constants.INTENT_STATUSES.RESOLVED

		-- Now check if all children are resolved
		assert.is_true(intents.areAllChildrenIntentsResolved(parentIntent.intentId))
	end)

		it('should return false when not all children are resolved', function()
			ARIOBalances['user-abc'] = {balance = '10000000000', orders = {}}
			
			-- Create parent
			local parentMsg = {
				Id = 'parent-check-2',
				From = 'user-abc',
				Timestamp = 1234567890,
			}
			local parentIntent = intents.createParentIntent(parentMsg, 'Create-Order', {})

			-- Create children
			local childMsg1 = {
				Id = 'child-3',
				Timestamp = 1234567900,
			}
			local child1 = intents.createChildIntent(parentIntent.intentId, childMsg1, 'token-1', {})

			local childMsg2 = {
				Id = 'child-4',
				Timestamp = 1234567900,
			}
			intents.createChildIntent(parentIntent.intentId, childMsg2, 'token-2', {})

			-- Only resolve one child
			intents.resolveIntent(child1.intentId, 1234567950)

			assert.is_false(intents.areAllChildrenIntentsResolved(parentIntent.intentId))
		end)
	end)

	describe('Intent TTL', function()
		it('should set TTL to 24 hours from creation', function()
			local msg = {
				Id = 'ttl-test-1',
				From = 'user-abc',
				Timestamp = 1000000,
			}
			local intent = intents.createParentIntent(msg, 'Cancel-Order', {})

			assert.is_not_nil(intent.ttl)
			-- 24 hours = 86400000 milliseconds
			assert.are.equal(1000000 + 86400000, intent.ttl)
		end)

		it('should schedule pruning when creating intent', function()
			local msg = {
				Id = 'ttl-test-2',
				From = 'user-abc',
				Timestamp = 2000000,
			}
			local intent = intents.createParentIntent(msg, 'Cancel-Order', {})

			assert.is_not_nil(Pruning.nextScheduledIntentsPruning)
			assert.are.equal(intent.ttl, Pruning.nextScheduledIntentsPruning)
		end)
	end)

	describe('Listing Fees', function()
		it('should charge listing fee for Create-Order intent without expiration', function()
			-- Setup user balance
			ARIOBalances['user-abc'] = {balance = '10000000000', orders = {}} -- 10 ARIO

			local msg = {
				Id = 'fee-test-1',
				From = 'user-abc',
				Timestamp = 1000000,
			}

			local intent = intents.createParentIntent(msg, 'Create-Order', {})

		-- 1 ARIO should be charged (LISTING_FEE_ARIO)
		assert.are.equal(tostring(bint('9000000000')), ARIOBalances['user-abc'].balance)
			-- Treasury should receive fee
			assert.are.equal('1000000000', ARIOBalances[TREASURY_ADDRESS].balance)
		end)

		it('should calculate fee based on listing duration', function()
			-- Setup user balance
			ARIOBalances['user-abc'] = {balance = '20000000000', orders = {}} -- 20 ARIO

			local msg = {
				Id = 'fee-test-2',
				From = 'user-abc',
				Timestamp = 1000000,
			}

			-- 48 hours expiration (2 days)
			local expirationTime = 1000000 + (48 * 3600000)
			local forwardedTags = {
				['Expiration-Time'] = tostring(expirationTime),
			}

			local intent = intents.createParentIntent(msg, 'Create-Order', forwardedTags)

		-- Fee should be 2 ARIO (48 hours / 24 hours = 2)
		assert.are.equal(tostring(bint('18000000000')), ARIOBalances['user-abc'].balance)
			assert.are.equal('2000000000', ARIOBalances[TREASURY_ADDRESS].balance)
		end)

		it('should fail if insufficient balance for listing fee', function()
			-- Setup insufficient balance
			ARIOBalances['user-poor'] = {balance = '500000000', orders = {}} -- 0.5 ARIO (need 1)

			local msg = {
				Id = 'fee-test-3',
				From = 'user-poor',
				Timestamp = 1000000,
			}

			local success, err = pcall(function()
				intents.createParentIntent(msg, 'Create-Order', {})
			end)

		assert.is_false(success)
		assert.is_not_nil(err and err:match('Insufficient ARIO balance'))
		end)

		it('should not charge fee for non-Create-Order intents', function()
			-- Setup user balance
			ARIOBalances['user-abc'] = {balance = '10000000000', orders = {}} -- 10 ARIO

			local msg = {
				Id = 'fee-test-4',
				From = 'user-abc',
				Timestamp = 1000000,
			}

			intents.createParentIntent(msg, 'Cancel-Order', {})

			-- Balance should remain unchanged
			assert.are.equal('10000000000', ARIOBalances['user-abc'].balance)
		end)

		it('should reject expiration time beyond 30 days', function()
			ARIOBalances['user-abc'] = {balance = '100000000000', orders = {}} -- 100 ARIO

			local msg = {
				Id = 'fee-test-5',
				From = 'user-abc',
				Timestamp = 1000000,
			}

			-- 31 days expiration (exceeds 30 day limit)
			local expirationTime = 1000000 + (31 * 24 * 3600000)
			local forwardedTags = {
				['Expiration-Time'] = tostring(expirationTime),
			}

			local success, err = pcall(function()
				intents.createParentIntent(msg, 'Create-Order', forwardedTags)
			end)

		assert.is_false(success)
		assert.is_not_nil(err and err:match('cannot exceed 30 days'))
		end)

		it('should reject expiration time in the past', function()
			ARIOBalances['user-abc'] = {balance = '10000000000', orders = {}}

			local msg = {
				Id = 'fee-test-6',
				From = 'user-abc',
				Timestamp = 1000000,
			}

			-- Expiration time in the past
			local forwardedTags = {
				['Expiration-Time'] = '500000', -- Before current timestamp
			}

			local success, err = pcall(function()
				intents.createParentIntent(msg, 'Create-Order', forwardedTags)
			end)

		assert.is_false(success)
		assert.is_not_nil(err and err:match('must be in the future'))
		end)
	end)

	describe('calculateListingFee', function()
		it('should return base fee when no expiration time provided', function()
			local fee, err = intents.calculateListingFee(nil, 1000000)

			assert.is_nil(err)
			assert.are.equal('1000000000', fee) -- 1 ARIO
		end)

		it('should calculate fee for 24 hours (1 day = 1 fee)', function()
			local expirationTime = 1000000 + (24 * 3600000) -- 24 hours later
			local fee, err = intents.calculateListingFee(expirationTime, 1000000)

			assert.is_nil(err)
			assert.are.equal('1000000000', fee) -- 1 ARIO
		end)

		it('should calculate fee for 48 hours (2 days = 2 fees)', function()
			local expirationTime = 1000000 + (48 * 3600000) -- 48 hours later
			local fee, err = intents.calculateListingFee(expirationTime, 1000000)

			assert.is_nil(err)
			assert.are.equal('2000000000', fee) -- 2 ARIO
		end)

		it('should round up partial days (25 hours = 2 fees)', function()
			local expirationTime = 1000000 + (25 * 3600000) -- 25 hours later
			local fee, err = intents.calculateListingFee(expirationTime, 1000000)

			assert.is_nil(err)
			assert.are.equal('2000000000', fee) -- 2 ARIO (rounded up)
		end)

		it('should calculate fee for 30 days (max allowed)', function()
			local expirationTime = 1000000 + (30 * 24 * 3600000) -- 30 days later
			local fee, err = intents.calculateListingFee(expirationTime, 1000000)

			assert.is_nil(err)
			assert.are.equal('30000000000', fee) -- 30 ARIO
		end)

		it('should reject expiration beyond 30 days', function()
			local expirationTime = 1000000 + (31 * 24 * 3600000) -- 31 days later
			local fee, err = intents.calculateListingFee(expirationTime, 1000000)

		assert.is_nil(fee)
		assert.is_not_nil(err and err:match('cannot exceed 30 days'))
		end)

		it('should reject expiration time in the past', function()
			local fee, err = intents.calculateListingFee(500000, 1000000) -- Past timestamp

		assert.is_nil(fee)
		assert.is_not_nil(err and err:match('must be in the future'))
		end)

		it('should reject invalid expiration time format', function()
			local fee, err = intents.calculateListingFee('invalid', 1000000)

		assert.is_nil(fee)
		assert.is_not_nil(err and err:match('must be a valid number'))
		end)

		it('should handle very short durations (1 hour = 1 fee)', function()
			local expirationTime = 1000000 + (1 * 3600000) -- 1 hour later
			local fee, err = intents.calculateListingFee(expirationTime, 1000000)

			assert.is_nil(err)
			assert.are.equal('1000000000', fee) -- 1 ARIO (minimum)
		end)
	end)

	describe('scheduleNextIntentsPruning', function()
		it('should schedule pruning at given timestamp', function()
			intents.scheduleNextIntentsPruning(5000000)

			assert.are.equal(5000000, Pruning.nextScheduledIntentsPruning)
		end)

		it('should update to earlier timestamp', function()
			Pruning.nextScheduledIntentsPruning = 6000000
			intents.scheduleNextIntentsPruning(5000000)

			assert.are.equal(5000000, Pruning.nextScheduledIntentsPruning)
		end)

		it('should not update to later timestamp', function()
			Pruning.nextScheduledIntentsPruning = 4000000
			intents.scheduleNextIntentsPruning(5000000)

			assert.are.equal(4000000, Pruning.nextScheduledIntentsPruning)
		end)
	end)

	describe('pruneIntents', function()
		it('should not prune before scheduled time', function()
			local msg = {
				Id = 'prune-test-1',
				From = 'user-abc',
				Timestamp = 1000000,
			}
			local intent = intents.createParentIntent(msg, 'Cancel-Order', {})

			-- Try to prune before TTL
			intents.pruneIntents(1000000 + 1000) -- Just 1 second later

			-- Intent should still exist
			assert.is_not_nil(Intents[intent.intentId])
			assert.are.equal('pending', Intents[intent.intentId].status)
		end)

		it('should prune expired intents', function()
			local msg = {
				Id = 'prune-test-2',
				From = 'user-abc',
				Timestamp = 1000000,
			}
			local intent = intents.createParentIntent(msg, 'Cancel-Order', {})

			-- Prune after TTL (24 hours + 1ms)
			intents.pruneIntents(1000000 + 86400000 + 1)

			-- Intent should be pruned
			assert.is_nil(Intents[intent.intentId])
		end)

		it('should reschedule next pruning after pruning', function()
			-- Create two intents with different TTLs
			local msg1 = {
				Id = 'prune-test-3a',
				From = 'user-abc',
				Timestamp = 1000000,
			}
			local intent1 = intents.createParentIntent(msg1, 'Cancel-Order', {})

			local msg2 = {
				Id = 'prune-test-3b',
				From = 'user-xyz',
				Timestamp = 2000000, -- Created 1000000ms later
			}
			local intent2 = intents.createParentIntent(msg2, 'Cancel-Order', {})

			-- Prune first intent
			intents.pruneIntents(intent1.ttl + 1)

			-- Next pruning should be scheduled for second intent
			assert.are.equal(intent2.ttl, Pruning.nextScheduledIntentsPruning)
			-- Second intent should still exist
			assert.is_not_nil(Intents[intent2.intentId])
		end)

		it('should only prune parent intents', function()
			ARIOBalances['user-abc'] = {balance = '10000000000', orders = {}}
			
			-- Create parent and child
			local parentMsg = {
				Id = 'prune-test-4-parent',
				From = 'user-abc',
				Timestamp = 1000000,
			}
			local parentIntent = intents.createParentIntent(parentMsg, 'Create-Order', {})

			local childMsg = {
				Id = 'prune-test-4-child',
				Timestamp = 1000000,
			}
			local childIntent = intents.createChildIntent(parentIntent.intentId, childMsg, 'token-123', {})

			-- Child intents don't have TTL, so they're not pruned by this function
		-- They're pruned when their parent is pruned
		intents.pruneIntents(parentIntent.ttl + 1)

		-- Both parent and child should be pruned (failIntent cascades)
		assert.is_nil(Intents[parentIntent.intentId])
		assert.is_nil(Intents[childIntent.intentId])
	end)
end)

describe('ANT Intent Resolution', function()
	local json = require('json')
	local constants = require('constants')
	local sentMessages = {}
	
	before_each(function()
		sentMessages = {}
		testGlobals.resetState()
		---@diagnostic disable-next-line: duplicate-set-field
		_G.ao.send = function(msg)
			table.insert(sentMessages, msg)
		end
	end)
	
	describe('pushANTIntentResolutionHandler', function()
		it('should send State action to ANT process', function()
			ARIOBalances['user-ant-owner'] = {balance = '10000000000', orders = {}}
			
			-- Create parent intent
			local parentMsg = {
				From = 'user-ant-owner',
				Timestamp = 1000000,
			}
			local parentIntent = intents.createParentIntent(parentMsg, 'Create-Order', {})
			
			-- Create child intent expecting from ANT
			local childMsg = {
				Timestamp = 1000100,
			}
			local antProcessId = 'ant-process-'..(string.rep('x', 33))
			local childIntent = intents.createChildIntent(
				parentIntent.intentId,
				childMsg,
				antProcessId,
				{}
			)
			
			-- Call handler
			local msg = {
				From = 'user-ant-owner',
				Tags = {
					['X-Intent-Id'] = childIntent.intentId,
				},
			}
			
			intents.pushANTIntentResolutionHandler(msg)
			
			-- Check that State message was sent to ANT
			assert.are.equal(1, #sentMessages)
			assert.are.equal(antProcessId, sentMessages[1].Target)
			assert.are.equal('State', sentMessages[1].Action)
			assert.are.equal(childIntent.intentId, sentMessages[1].Tags['X-Intent-Id'])
		end)
		
		it('should require X-Intent-Id', function()
			local msg = {
				Id = 'msg-123',
				From = 'user-123',
				Timestamp = 1000000,
				Tags = {},
			}
			
			local success, err = pcall(function()
				intents.pushANTIntentResolutionHandler(msg)
			end)
			
		assert.is_false(success)
		assert.is_not_nil(err and err:match('X%-Intent%-Id required'))
		end)
		
		it('should require intent to exist', function()
			local msg = {
				Id = 'msg-456',
				From = 'user-123',
				Timestamp = 1000000,
				Tags = {
					['X-Intent-Id'] = '999999',
				},
			}
			
			local success, err = pcall(function()
				intents.pushANTIntentResolutionHandler(msg)
			end)
			
		assert.is_false(success)
		assert.is_not_nil(err and err:match('Intent not found'))
		end)
		
		it('should require sender to match intent initiator', function()
			ARIOBalances['user-owner'] = {balance = '10000000000', orders = {}}
			
			-- Create parent intent for user-owner
			local parentMsg = {
				Id = 'parent-msg-789',
				From = 'user-owner',
				Timestamp = 1000000,
			}
			local parentIntent = intents.createParentIntent(parentMsg, 'Create-Order', {})
			
			-- Try to call from different user
			local msg = {
				Id = 'msg-789',
				From = 'different-user',
				Timestamp = 1000100,
				Tags = {
					['X-Intent-Id'] = parentIntent.intentId,
				},
			}
			
			local success, err = pcall(function()
				intents.pushANTIntentResolutionHandler(msg)
			end)
			
		assert.is_false(success)
		assert.is_not_nil(err and err:match('Sender does not match intent initiator'))
		end)
	end)
	
	describe('stateNoticeHandler', function()
		local utils = require('utils')
		
		it('should resolve intent when ANT owner matches marketplace', function()
			ARIOBalances['user-ant-owner'] = {balance = '10000000000', orders = {}}
			
			-- Create parent intent
			local parentMsg = {
				From = 'user-ant-owner',
				Timestamp = 1000000,
			}
			local parentIntent = intents.createParentIntent(parentMsg, 'Create-Order', {})
			
			-- Create TWO child intents so resolving one doesn't complete the parent
			local childMsg1 = {
				Timestamp = 1000100,
			}
			local antProcessId = 'ant-process-'..(string.rep('x', 33))
			local childIntent1 = intents.createChildIntent(
				parentIntent.intentId,
				childMsg1,
				antProcessId,
				{}
			)
			
			local childMsg2 = {
				Timestamp = 1000100,
			}
			local childIntent2 = intents.createChildIntent(
				parentIntent.intentId,
				childMsg2,
				'other-token-id',
				{}
			)
			
			-- Simulate State-Notice from ANT with marketplace as owner
			local stateNotice = {
				From = antProcessId,
				Timestamp = 1000200,
				Data = json.encode({
					Owner = ao.id, -- Marketplace owns the ANT
				}),
				Tags = {
					['X-Intent-Id'] = childIntent1.intentId,
				},
			}
			
			intents.stateNoticeHandler(stateNotice)
			
		-- Child intent should be resolved
		local resolvedChild = intents.getIntentById(childIntent1.intentId)
		assert.is_not_nil(resolvedChild)
		assert.are.equal('resolved', resolvedChild and resolvedChild.status)
		
	-- Parent should be settling (first child resolved, second child still pending)
	local parentAfterResolve = intents.getIntentById(parentIntent.intentId)
	assert.is_not_nil(parentAfterResolve)
	assert.are.equal('settling', parentAfterResolve and parentAfterResolve.status)
			
		-- Acknowledgment should be sent
		assert.are.equal(1, #sentMessages)
		assert.are.equal('user-ant-owner', sentMessages[1].Target)
		assert.are.equal('State-Notice-Processed', sentMessages[1].Action)
		assert.are.equal(childIntent1.intentId, sentMessages[1]['Intent-Id'])
		assert.are.equal('resolved', sentMessages[1]['Intent-Status'])
		end)
		
		it('should fail intent when ANT owner is not marketplace', function()
			ARIOBalances['user-ant-owner'] = {balance = '10000000000', orders = {}}
			
			-- Create parent intent
			local parentMsg = {
				From = 'user-ant-owner',
				Timestamp = 1000000,
			}
			local parentIntent = intents.createParentIntent(parentMsg, 'Create-Order', {})
			
			-- Create child intent
			local childMsg = {
				Timestamp = 1000100,
			}
			local antProcessId = 'ant-process-'..(string.rep('y', 33))
			local childIntent = intents.createChildIntent(
				parentIntent.intentId,
				childMsg,
				antProcessId,
				{}
			)
			
			-- Simulate State-Notice with different owner
			local stateNotice = {
				From = antProcessId,
				Timestamp = 1000200,
				Data = json.encode({
					Owner = 'different-owner-address',
				}),
				Tags = {
					['X-Intent-Id'] = childIntent.intentId,
				},
			}
			
			local success, err = pcall(function()
				intents.stateNoticeHandler(stateNotice)
			end)
			
		assert.is_false(success)
		assert.is_not_nil(err and err:match('Marketplace does not own this ANT'))
		end)
		
		it('should require X-Intent-Id', function()
			local msg = {
				Id = 'state-msg-1',
				From = 'ant-process-123',
				Timestamp = 1000000,
				Data = json.encode({Owner = ao.id}),
				Tags = {},
			}
			
			local success, err = pcall(function()
				intents.stateNoticeHandler(msg)
			end)
			
		assert.is_false(success)
		assert.is_not_nil(err and err:match('X%-Intent%-Id required'))
		end)
		
		it('should require valid intent ID format', function()
			local msg = {
				From = 'ant-process-123',
				Data = json.encode({Owner = ao.id}),
				Tags = {
					['X-Intent-Id'] = 'invalid-format',
				},
			}
			
			local success, err = pcall(function()
				intents.stateNoticeHandler(msg)
			end)
			
		assert.is_false(success)
		assert.is_not_nil(err and err:match('Invalid X%-Intent%-Id format'))
		end)
		
		it('should require intent to exist', function()
			local msg = {
				From = 'ant-process-123',
				Data = json.encode({Owner = ao.id}),
				Tags = {
					['X-Intent-Id'] = '999999',
				},
			}
			
			local success, err = pcall(function()
				intents.stateNoticeHandler(msg)
			end)
			
		assert.is_false(success)
		assert.is_not_nil(err and err:match('Intent not found'))
		end)
		
		it('should require State-Notice from expected ANT', function()
			ARIOBalances['user-owner'] = {balance = '10000000000', orders = {}}
			
			-- Create intents
			local parentMsg = {Id = 'parent-msg-1', From = 'user-owner', Timestamp = 1000000}
			local parentIntent = intents.createParentIntent(parentMsg, 'Create-Order', {})
			
			local antProcessId = 'ant-expected-'..(string.rep('a', 32))
			local childIntent = intents.createChildIntent(
				parentIntent.intentId,
				{Id = 'child-msg-1', From = 'user-owner', Owner = '', Timestamp = 1000100, Tags = {}, Data = ''},
				antProcessId,
				{}
			)
			
			-- State-Notice from different ANT
			local msg = {
				From = 'different-ant-'..(string.rep('b', 32)),
				Data = json.encode({Owner = ao.id}),
				Timestamp = 1000200,
				Tags = {
					['X-Intent-Id'] = childIntent.intentId,
				},
			}
			
			local success, err = pcall(function()
				intents.stateNoticeHandler(msg)
			end)
			
		assert.is_false(success)
		assert.is_not_nil(err and err:match('Sender does not match intent expected from'))
		end)
		
		it('should require valid State-Notice data', function()
			ARIOBalances['user-owner'] = {balance = '10000000000', orders = {}}
			
			local parentMsg = {Id = 'parent-msg-2', From = 'user-owner', Timestamp = 1000000}
			local parentIntent = intents.createParentIntent(parentMsg, 'Create-Order', {})
			
			local antProcessId = 'ant-process-'..(string.rep('c', 33))
			local childIntent = intents.createChildIntent(
				parentIntent.intentId,
				{Id = 'child-msg-2', From = 'user-owner', Owner = '', Timestamp = 1000100, Tags = {}, Data = ''},
				antProcessId,
				{}
			)
			
			-- Invalid JSON data
			local msg = {
				From = antProcessId,
				Data = 'invalid json',
				Timestamp = 1000200,
				Tags = {
					['X-Intent-Id'] = childIntent.intentId,
				},
			}
			
			local success, err = pcall(function()
				intents.stateNoticeHandler(msg)
			end)
			
		assert.is_false(success)
		assert.is_not_nil(err and err:match('Invalid State%-Notice data'))
		end)
		
		it('should handle multiple child intents completing parent', function()
			ARIOBalances['user-owner'] = {balance = '10000000000', orders = {}}
			
			-- Create parent intent
			local parentMsg = {Id = 'parent-msg-3', From = 'user-owner', Timestamp = 1000000}
			local parentIntent = intents.createParentIntent(parentMsg, 'Create-Order', {})
			
			-- Create two child intents for different ANTs
			local ant1 = 'ant-process-1'..(string.rep('x', 32))
			local ant2 = 'ant-process-2'..(string.rep('y', 32))
			
			local child1 = intents.createChildIntent(
				parentIntent.intentId,
				{Id = 'child-msg-3a', From = 'user-owner', Owner = '', Timestamp = 1000100, Tags = {}, Data = ''},
				ant1,
				{}
			)
			local child2 = intents.createChildIntent(
				parentIntent.intentId,
				{Id = 'child-msg-3b', From = 'user-owner', Owner = '', Timestamp = 1000100, Tags = {}, Data = ''},
				ant2,
				{}
			)
			
			-- Resolve first child
			local msg1 = {
				From = ant1,
				Data = json.encode({Owner = ao.id}),
				Timestamp = 1000200,
				Tags = {['X-Intent-Id'] = child1.intentId},
			}
			intents.stateNoticeHandler(msg1)
			
		-- Parent should still be active (not all children resolved)
		local parentAfterFirst = intents.getIntentById(parentIntent.intentId)
		assert.is_not_nil(parentAfterFirst)
		assert.are.equal('settling', parentAfterFirst and parentAfterFirst.status)
			
			-- Resolve second child
			local msg2 = {
				From = ant2,
				Data = json.encode({Owner = ao.id}),
				Timestamp = 1000300,
				Tags = {['X-Intent-Id'] = child2.intentId},
			}
		intents.stateNoticeHandler(msg2)
		
	-- Now parent should be completed and pruned (no longer in Intents table)
	local parentAfterSecond = intents.getIntentById(parentIntent.intentId)
	assert.is_nil(parentAfterSecond)
		end)
	end)
end)
end)
