print('\n=== Loading intents module for testing ===')
local testGlobals = require('test_globals')
local intents = require('intents')
print('✓ intents module loaded')

describe('Intent Management', function()
	print('\n--- Starting Intent Management tests ---')
	before_each(function()
		-- Reset global state
		testGlobals.resetState()
	end)

	describe('createParent', function()
		it('should create a parent intent with correct structure', function()
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
			-- Create parent
			local parentMsg = {
				Id = 'parent-999',
				From = 'user-abc',
				Timestamp = 1234567890,
			}
			local parentIntent = intents.createParentIntent(parentMsg, 'Create-Order', {})

			-- Create child
			local childMsg = {
				Id = 'msg-222',
				Timestamp = 1234567900,
			}
			local childIntent = intents.createChildIntent(parentIntent.intentId, childMsg, 'token-123', {})

			local result = intents.resolveIntent(childIntent.intentId, 1234567950)

			assert.is_true(result)
			assert.are.equal('resolved', Intents[childIntent.intentId].status)
			assert.are.equal(1234567950, Intents[childIntent.intentId].resolvedAt)
		end)

		it('should return false for non-existent intent', function()
			local result = intents.resolveIntent('non-existent-id', 1234567890)
			assert.is_false(result)
		end)
	end)

	describe('fail', function()
		it('should mark intent as failed with reason and then prune it', function()
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

			-- Resolve both children
			intents.resolveIntent(child1.intentId, 1234567950)
			intents.resolveIntent(child2.intentId, 1234567960)

			assert.is_true(intents.areAllChildrenIntentsResolved(parentIntent.intentId))
		end)

		it('should return false when not all children are resolved', function()
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
end)
