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

			assert.are.equal('test-intent-123', intent.intentId)
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

			intents.createParentIntent(msg, 'Cancel-Order', {})

			assert.is_not_nil(Intents['test-intent-456'])
			assert.are.equal('parent', Intents['test-intent-456'].type)
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
			intents.createParentIntent(parentMsg, 'Create-Order', {})

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

			local childIntent = intents.createChildIntent('parent-123', childMsg, 'token-process-id', forwardedTags)

			assert.are.equal('child', childIntent.type)
			assert.are.equal('parent-123', childIntent.parentIntentId)
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
			intents.createParentIntent(parentMsg, 'Create-Order', {})

			-- Create child
			local childMsg = {
				Id = 'msg-111',
				Timestamp = 1234567900,
			}

			local childIntent = intents.createChildIntent('parent-456', childMsg, 'token-123', {})

			local parent = Intents['parent-456']
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
			intents.createParentIntent(msg, 'Create-Order', {})

			local result = intents.resolveIntent('parent-789', 1234567900)

			assert.is_true(result)
			assert.are.equal('active', Intents['parent-789'].status)
			assert.are.equal(1234567900, Intents['parent-789'].resolvedAt)
		end)

		it('should update child status to resolved', function()
			-- Create parent
			local parentMsg = {
				Id = 'parent-999',
				From = 'user-abc',
				Timestamp = 1234567890,
			}
			intents.createParentIntent(parentMsg, 'Create-Order', {})

			-- Create child
			local childMsg = {
				Id = 'msg-222',
				Timestamp = 1234567900,
			}
			local childIntent = intents.createChildIntent('parent-999', childMsg, 'token-123', {})

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
		it('should mark intent as failed with reason', function()
			local msg = {
				Id = 'parent-fail',
				From = 'user-abc',
				Timestamp = 1234567890,
			}
			intents.createParentIntent(msg, 'Create-Order', {})

			local result = intents.failIntent('parent-fail', 'Insufficient balance')

			assert.is_true(result)
			assert.are.equal('failed', Intents['parent-fail'].status)
			assert.are.equal('Insufficient balance', Intents['parent-fail'].failureReason)
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
			intents.createParentIntent(msg, 'Create-Order', {})

			local result = intents.updateIntentStatus('parent-status', 'settling')

			assert.is_true(result)
			assert.are.equal('settling', Intents['parent-status'].status)
		end)

		it('should set CompletedAt when status is completed', function()
			local msg = {
				Id = 'parent-complete',
				From = 'user-abc',
				Timestamp = 1234567890,
			}
			intents.createParentIntent(msg, 'Create-Order', {})

			intents.updateIntentStatus('parent-complete', 'completed')

			assert.are.equal('completed', Intents['parent-complete'].status)
			assert.is_not_nil(Intents['parent-complete'].completedAt)
		end)
	end)

	describe('getById', function()
		it('should return intent by ID', function()
			local msg = {
				Id = 'test-get',
				From = 'user-abc',
				Timestamp = 1234567890,
			}
			intents.createParentIntent(msg, 'Create-Order', {})

			local intent = intents.getIntentById('test-get')

			assert.is_not_nil(intent)
			assert.are.equal('test-get', intent.intentId)
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
			intents.createParentIntent(msg1, 'Create-Order', {})

			-- Create active parent
			local msg2 = {
				Id = 'active-1',
				From = 'user-2',
				Timestamp = 1234567890,
			}
			intents.createParentIntent(msg2, 'Create-Order', {})
			intents.resolveIntent('active-1', 1234567900)

			local pending = intents.getPendingIntents()

			assert.are.equal(1, #pending)
			assert.are.equal('pending-1', pending[1].intentId)
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
			intents.createParentIntent(msg2, 'Cancel-Order', {})
			intents.failIntent('intent-2', 'Some error')

			local failed = intents.getIntentsByStatus('failed')

			assert.are.equal(1, #failed)
			assert.are.equal('intent-2', failed[1].intentId)
		end)
	end)

	describe('validateExists', function()
		it('should return true for existing intent', function()
			local msg = {
				Id = 'exists-1',
				From = 'user-1',
				Timestamp = 1234567890,
			}
			intents.createParentIntent(msg, 'Create-Order', {})

			assert.is_true(intents.validateIntentExists('exists-1'))
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
			intents.createParentIntent(parentMsg, 'Create-Order', {})

			-- Create children
			local childMsg1 = {
				Id = 'child-1',
				Timestamp = 1234567900,
			}
			local child1 = intents.createChildIntent('parent-check', childMsg1, 'token-1', {})

			local childMsg2 = {
				Id = 'child-2',
				Timestamp = 1234567900,
			}
			local child2 = intents.createChildIntent('parent-check', childMsg2, 'token-2', {})

			-- Resolve both children
			intents.resolveIntent(child1.intentId, 1234567950)
			intents.resolveIntent(child2.intentId, 1234567960)

			assert.is_true(intents.areAllChildrenIntentsResolved('parent-check'))
		end)

		it('should return false when not all children are resolved', function()
			-- Create parent
			local parentMsg = {
				Id = 'parent-check-2',
				From = 'user-abc',
				Timestamp = 1234567890,
			}
			intents.createParentIntent(parentMsg, 'Create-Order', {})

			-- Create children
			local childMsg1 = {
				Id = 'child-3',
				Timestamp = 1234567900,
			}
			local child1 = intents.createChildIntent('parent-check-2', childMsg1, 'token-1', {})

			local childMsg2 = {
				Id = 'child-4',
				Timestamp = 1234567900,
			}
			intents.createChildIntent('parent-check-2', childMsg2, 'token-2', {})

			-- Only resolve one child
			intents.resolveIntent(child1.intentId, 1234567950)

			assert.is_false(intents.areAllChildrenIntentsResolved('parent-check-2'))
		end)
	end)
end)
