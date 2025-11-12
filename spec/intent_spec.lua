package.path = package.path .. ';../src/?.lua'

-- Mock global Intents table BEFORE requiring the module
_G.Intents = {}

local intents = require('intents')

describe('Intent Management', function()
	before_each(function()
		-- Clear all intent entries
		for k in pairs(_G.Intents) do
			_G.Intents[k] = nil
		end
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

			local intent = intents.createParent(msg, 'Create-Order', forwardedTags)

			assert.are.equal('test-intent-123', intent.IntentId)
			assert.are.equal('parent', intent.Type)
			assert.are.equal('user-address-abc', intent.Initiator)
			assert.are.equal('Create-Order', intent.Action)
			assert.are.equal('pending', intent.Status)
			assert.are.equal(1234567890, intent.CreatedAt)
			assert.is_nil(intent.ParentIntentId)
			assert.is_table(intent.ChildIntentIds)
			assert.are.same(forwardedTags, intent.ForwardedTags)
		end)

		it('should add parent intent to Intents table', function()
			local msg = {
				Id = 'test-intent-456',
				From = 'user-xyz',
				Timestamp = 1234567890,
			}

			intents.createParent(msg, 'Cancel-Order', {})

			assert.is_not_nil(Intents['test-intent-456'])
			assert.are.equal('parent', Intents['test-intent-456'].Type)
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
			intents.createParent(parentMsg, 'Create-Order', {})

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

			local childIntent = intents.createChild('parent-123', childMsg, 'token-process-id', forwardedTags)

			assert.are.equal('child', childIntent.Type)
			assert.are.equal('parent-123', childIntent.ParentIntentId)
			assert.are.equal('Transfer', childIntent.Action)
			assert.are.equal('Debit-Notice', childIntent.ExpectedMessage)
			assert.are.equal('token-process-id', childIntent.ExpectedFrom)
			assert.are.equal('pending', childIntent.Status)
			assert.are.same(forwardedTags, childIntent.ForwardedTags)
		end)

		it("should add child to parent's ChildIntentIds map", function()
			-- Create parent
			local parentMsg = {
				Id = 'parent-456',
				From = 'user-xyz',
				Timestamp = 1234567890,
			}
			intents.createParent(parentMsg, 'Create-Order', {})

			-- Create child
			local childMsg = {
				Id = 'msg-111',
				Timestamp = 1234567900,
			}

			local childIntent = intents.createChild('parent-456', childMsg, 'token-123', {})

			local parent = Intents['parent-456']
			assert.is_true(parent.ChildIntentIds[childIntent.IntentId])
		end)
	end)

	describe('resolve', function()
		it('should update parent status from pending to active', function()
			local msg = {
				Id = 'parent-789',
				From = 'user-abc',
				Timestamp = 1234567890,
			}
			intents.createParent(msg, 'Create-Order', {})

			local result = intents.resolve('parent-789', 1234567900)

			assert.is_true(result)
			assert.are.equal('active', Intents['parent-789'].Status)
			assert.are.equal(1234567900, Intents['parent-789'].ResolvedAt)
		end)

		it('should update child status to resolved', function()
			-- Create parent
			local parentMsg = {
				Id = 'parent-999',
				From = 'user-abc',
				Timestamp = 1234567890,
			}
			intents.createParent(parentMsg, 'Create-Order', {})

			-- Create child
			local childMsg = {
				Id = 'msg-222',
				Timestamp = 1234567900,
			}
			local childIntent = intents.createChild('parent-999', childMsg, 'token-123', {})

			local result = intents.resolve(childIntent.IntentId, 1234567950)

			assert.is_true(result)
			assert.are.equal('resolved', Intents[childIntent.IntentId].Status)
			assert.are.equal(1234567950, Intents[childIntent.IntentId].ResolvedAt)
		end)

		it('should return false for non-existent intent', function()
			local result = intents.resolve('non-existent-id', 1234567890)
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
			intents.createParent(msg, 'Create-Order', {})

			local result = intents.fail('parent-fail', 'Insufficient balance')

			assert.is_true(result)
			assert.are.equal('failed', Intents['parent-fail'].Status)
			assert.are.equal('Insufficient balance', Intents['parent-fail'].FailureReason)
		end)

		it('should return false for non-existent intent', function()
			local result = intents.fail('non-existent', 'Some reason')
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
			intents.createParent(msg, 'Create-Order', {})

			local result = intents.updateStatus('parent-status', 'settling')

			assert.is_true(result)
			assert.are.equal('settling', Intents['parent-status'].Status)
		end)

		it('should set CompletedAt when status is completed', function()
			local msg = {
				Id = 'parent-complete',
				From = 'user-abc',
				Timestamp = 1234567890,
			}
			intents.createParent(msg, 'Create-Order', {})

			intents.updateStatus('parent-complete', 'completed')

			assert.are.equal('completed', Intents['parent-complete'].Status)
			assert.is_not_nil(Intents['parent-complete'].CompletedAt)
		end)
	end)

	describe('getById', function()
		it('should return intent by ID', function()
			local msg = {
				Id = 'test-get',
				From = 'user-abc',
				Timestamp = 1234567890,
			}
			intents.createParent(msg, 'Create-Order', {})

			local intent = intents.getById('test-get')

			assert.is_not_nil(intent)
			assert.are.equal('test-get', intent.IntentId)
		end)

		it('should return nil for non-existent intent', function()
			local intent = intents.getById('non-existent')
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
			intents.createParent(msg1, 'Create-Order', {})

			-- Create active parent
			local msg2 = {
				Id = 'active-1',
				From = 'user-2',
				Timestamp = 1234567890,
			}
			intents.createParent(msg2, 'Create-Order', {})
			intents.resolve('active-1', 1234567900)

			local pending = intents.getPending()

			assert.are.equal(1, #pending)
			assert.are.equal('pending-1', pending[1].IntentId)
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
			intents.createParent(msg1, 'Create-Order', {})

			local msg2 = {
				Id = 'intent-2',
				From = 'user-2',
				Timestamp = 1234567890,
			}
			intents.createParent(msg2, 'Cancel-Order', {})
			intents.fail('intent-2', 'Some error')

			local failed = intents.getByStatus('failed')

			assert.are.equal(1, #failed)
			assert.are.equal('intent-2', failed[1].IntentId)
		end)
	end)

	describe('validateExists', function()
		it('should return true for existing intent', function()
			local msg = {
				Id = 'exists-1',
				From = 'user-1',
				Timestamp = 1234567890,
			}
			intents.createParent(msg, 'Create-Order', {})

			assert.is_true(intents.validateExists('exists-1'))
		end)

		it('should return false for non-existent intent', function()
			assert.is_false(intents.validateExists('does-not-exist'))
		end)
	end)

	describe('getAllIntents', function()
		it('should return all intents as array', function()
			local msg1 = {
				Id = 'intent-1',
				From = 'user-1',
				Timestamp = 1234567890,
			}
			intents.createParent(msg1, 'Create-Order', {})

			local msg2 = {
				Id = 'intent-2',
				From = 'user-2',
				Timestamp = 1234567890,
			}
			intents.createParent(msg2, 'Cancel-Order', {})

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
			intents.createParent(parentMsg, 'Create-Order', {})

			-- Create children
			local childMsg1 = {
				Id = 'child-1',
				Timestamp = 1234567900,
			}
			local child1 = intents.createChild('parent-check', childMsg1, 'token-1', {})

			local childMsg2 = {
				Id = 'child-2',
				Timestamp = 1234567900,
			}
			local child2 = intents.createChild('parent-check', childMsg2, 'token-2', {})

			-- Resolve both children
			intents.resolve(child1.IntentId, 1234567950)
			intents.resolve(child2.IntentId, 1234567960)

			assert.is_true(intents.areAllChildrenResolved('parent-check'))
		end)

		it('should return false when not all children are resolved', function()
			-- Create parent
			local parentMsg = {
				Id = 'parent-check-2',
				From = 'user-abc',
				Timestamp = 1234567890,
			}
			intents.createParent(parentMsg, 'Create-Order', {})

			-- Create children
			local childMsg1 = {
				Id = 'child-3',
				Timestamp = 1234567900,
			}
			local child1 = intents.createChild('parent-check-2', childMsg1, 'token-1', {})

			local childMsg2 = {
				Id = 'child-4',
				Timestamp = 1234567900,
			}
			intents.createChild('parent-check-2', childMsg2, 'token-2', {})

			-- Only resolve one child
			intents.resolve(child1.IntentId, 1234567950)

			assert.is_false(intents.areAllChildrenResolved('parent-check-2'))
		end)
	end)
end)
