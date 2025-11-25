print('\n=== Loading notices module for testing ===')
local testGlobals = require('test_globals')
local notices = require('notices')
local intents = require('intents')
local utils = require('utils')
local balances = require('balances')
print('✓ notices module loaded')

describe('Notices Module', function()
	print('\n--- Starting Notices tests ---')
	
	local function createMockMsg(overrides)
		return testGlobals.mockMsg(overrides or {})
	end

	before_each(function()
		testGlobals.resetState()
		testGlobals.setArioTokenId('ario-token-123')
	end)

	describe('creditNoticeHandler - Deposits', function()
		it('should handle ARIO deposit', function()
			local msg = createMockMsg({
				From = 'ario-token-123',
				Tags = {
					Sender = 'user-123',
					Quantity = '1000',
					['X-Action'] = 'Deposit',
				},
			})

			notices.creditNoticeHandler(msg)

			-- Verify balance increased
			assert.are.equal('1000', balances.getBalance('user-123'))
		end)

		it('should reject non-ARIO deposit', function()
			local msg = createMockMsg({
				From = 'non-ario-token',
				Tags = {
					Sender = 'user-123',
					Quantity = '1000',
					['X-Action'] = 'Deposit',
				},
			})

			local success = pcall(function()
				notices.creditNoticeHandler(msg)
			end)

			assert.is_false(success)
		end)
	end)

	describe('creditNoticeHandler - Validation', function()
		it('should require Sender tag', function()
			local msg = createMockMsg({
				From = 'ant-token-123',
				Tags = {
					Quantity = '1000',
					['X-Intent-Id'] = 'intent-123',
				},
			})

			local success = pcall(function()
				notices.creditNoticeHandler(msg)
			end)

			assert.is_false(success)
		end)

		it('should require Quantity tag', function()
			local msg = createMockMsg({
				From = 'ant-token-123',
				Tags = {
					Sender = 'user-123',
					['X-Intent-Id'] = 'intent-123',
				},
			})

			local success = pcall(function()
				notices.creditNoticeHandler(msg)
			end)

			assert.is_false(success)
		end)

		it('should block ARIO Credit-Notices with X-Order-Action', function()
			local msg = createMockMsg({
				From = 'ario-token-123',
				Tags = {
					Sender = 'user-123',
					Quantity = '1000',
					['X-Order-Action'] = 'Create-Order',
				},
			})

			-- Should handle invalid transfer (accrue fee for ARIO)
			notices.creditNoticeHandler(msg)
			
			-- Fee should be accrued
			assert.are.equal('1000', tostring(utils.getAccruedFees()))
		end)

		it('should require X-Intent-Id for ANT orders', function()
			local msg = createMockMsg({
				From = 'ant-token-123',
				Tags = {
					Sender = 'user-123',
					Quantity = '1',
				},
			})

			-- Should refund without intent ID
			notices.creditNoticeHandler(msg)
			
			-- Should have sent refund
			assert.is_true(#testGlobals.sentMessages > 0)
		end)

		it('should validate X-Intent-Id format', function()
			local msg = createMockMsg({
				From = 'ant-token-123',
				Tags = {
					Sender = 'user-123',
					Quantity = '1',
					['X-Intent-Id'] = 'invalid',
				},
			})

			notices.creditNoticeHandler(msg)
			
			-- Should have sent refund
			assert.is_true(#testGlobals.sentMessages > 0)
		end)

		it('should validate intent exists', function()
			local msg = createMockMsg({
				From = 'ant-token-123',
				Tags = {
					Sender = 'user-123',
					Quantity = '1',
					['X-Intent-Id'] = 'intent-nonexistent',
				},
			})

			notices.creditNoticeHandler(msg)
			
			-- Should have sent refund
			assert.is_true(#testGlobals.sentMessages > 0)
		end)

		it('should validate sender matches intent initiator', function()
			-- Create intent
			local msg = { From = 'user-123', Timestamp = 1000 }
			local intent = intents.createParentIntent(msg, 'Create-Order', {})
			local intentId = intent.intentId

			local msg = createMockMsg({
				From = 'ant-token-123',
				Tags = {
					Sender = 'user-456', -- Different sender
					Quantity = '1',
					['X-Intent-Id'] = intentId,
				},
			})

			notices.creditNoticeHandler(msg)
			
			-- Should have sent refund
			assert.is_true(#testGlobals.sentMessages > 0)
		end)

		it('should validate intent TTL not expired', function()
			-- Create intent with TTL
			local msg = { From = 'user-123', Timestamp = 1000 }
			local intent = intents.createParentIntent(msg, 'Create-Order', {})
			local intentId = intent.intentId
			-- Manually set TTL
			Intents[intentId].ttl = 2000

			local msg = createMockMsg({
				From = 'ant-token-123',
				Timestamp = 2500, -- After TTL
				Tags = {
					Sender = 'user-123',
					Quantity = '1',
					['X-Intent-Id'] = intentId,
				},
			})

			notices.creditNoticeHandler(msg)
			
			-- Should have sent refund
			assert.is_true(#testGlobals.sentMessages > 0)
		end)

		it('should validate sender address format', function()
			-- Create intent
			local msg = { From = 'short', Timestamp = 1000 }
			local intent = intents.createParentIntent(msg, 'Create-Order', {})
			local intentId = intent.intentId

			local msg = createMockMsg({
				From = 'ant-token-123',
				Tags = {
					Sender = 'short', -- Invalid address
					Quantity = '1',
					['X-Intent-Id'] = intentId,
				},
			})

			notices.creditNoticeHandler(msg)
			
			-- Should have sent refund
			assert.is_true(#testGlobals.sentMessages > 0)
		end)

		it('should validate quantity is valid amount', function()
			-- Create intent
			local msg = { From = 'user-123-1234567890123456789012345678901234567890', Timestamp = 1000 }
			local intent = intents.createParentIntent(msg, 'Create-Order', {})
			local intentId = intent.intentId

			local msg = createMockMsg({
				From = 'ant-token-123',
				Tags = {
					Sender = 'user-123-1234567890123456789012345678901234567890',
					Quantity = '-100', -- Invalid quantity
					['X-Intent-Id'] = intentId,
				},
			})

			notices.creditNoticeHandler(msg)
			
			-- Should have sent refund
			assert.is_true(#testGlobals.sentMessages > 0)
		end)
	end)

	describe('creditNoticeHandler - Order Creation', function()
		it('should create ANT order with valid Credit-Notice', function()
			-- Create intent
			local msg = { From = 'user-123-1234567890123456789012345678901234567890', Timestamp = 1000 }
			local intent = intents.createParentIntent(msg, 'Create-Order', {})
			local intentId = intent.intentId

			-- Add ARIO balance for matching
			ARIOBalances['seller-123'] = {
				balance = '10000',
				orders = {}
			}

			local msg = createMockMsg({
				From = 'ant-token-123',
				Tags = {
					Sender = 'user-123-1234567890123456789012345678901234567890',
					Quantity = '1',
					['X-Intent-Id'] = intentId,
					['X-Order-Action'] = 'Create-Order',
					['X-Swap-Token'] = 'ario-token-123',
					['X-Order-Type'] = 'fixed',
					['X-Price'] = '1000',
					['X-Expiration-Time'] = '2000',
				},
			})

			notices.creditNoticeHandler(msg)
			
			-- Should send acknowledgment
			local creditNoticeProcessed = false
			for _, sentMsg in ipairs(testGlobals.sentMessages) do
				if sentMsg.Action == 'Credit-Notice-Processed' then
					creditNoticeProcessed = true
					assert.are.equal(msg.Id, sentMsg.Tags['Order-Id'])
					assert.are.equal(intentId, sentMsg.Tags['Intent-Id'])
					break
				end
			end
			assert.is_true(creditNoticeProcessed)
		end)

		it('should validate ARIO in trade', function()
			-- Create intent
			local msg = { From = 'user-123-1234567890123456789012345678901234567890', Timestamp = 1000 }
			local intent = intents.createParentIntent(msg, 'Create-Order', {})
			local intentId = intent.intentId

			local msg = createMockMsg({
				From = 'ant-token-123',
				Tags = {
					Sender = 'user-123-1234567890123456789012345678901234567890',
					Quantity = '1',
					['X-Intent-Id'] = intentId,
					['X-Order-Action'] = 'Create-Order',
					['X-Swap-Token'] = 'other-token-123', -- Not ARIO
					['X-Order-Type'] = 'fixed',
					['X-Price'] = '1000',
				},
			})

			notices.creditNoticeHandler(msg)
			
			-- Should have sent refund
			local refundSent = false
			for _, sentMsg in ipairs(testGlobals.sentMessages) do
				if sentMsg.Action == 'Transfer' then
					refundSent = true
					break
				end
			end
			assert.is_true(refundSent)
		end)

		it('should handle order creation errors gracefully', function()
			-- Create intent
			local msg = { From = 'user-123-1234567890123456789012345678901234567890', Timestamp = 1000 }
			local intent = intents.createParentIntent(msg, 'Create-Order', {})
			local intentId = intent.intentId

			local msg = createMockMsg({
				From = 'ant-token-123',
				Tags = {
					Sender = 'user-123-1234567890123456789012345678901234567890',
					Quantity = '2', -- Invalid quantity for ANT
					['X-Intent-Id'] = intentId,
					['X-Order-Action'] = 'Create-Order',
					['X-Swap-Token'] = 'ario-token-123',
					['X-Order-Type'] = 'fixed',
					['X-Price'] = '1000',
				},
			})

			-- Should not crash
			notices.creditNoticeHandler(msg)
			
			-- Should have sent refund
			assert.is_true(#testGlobals.sentMessages > 0)
		end)
	end)

	describe('debitNoticeHandler', function()
		it('should resolve child intent on Debit-Notice', function()
			-- Create parent intent
			local parentMsg = { From = 'user-123', Timestamp = 1000 }
			local parentIntent = intents.createParentIntent(parentMsg, 'Create-Order', {})
			local parentId = parentIntent.intentId

			-- Create child intent
			local childMsg = { From = 'user-123', Timestamp = 1000 }
			local childIntent = intents.createChildIntent(parentId, childMsg, 'ant-token-123', {})
			local childId = childIntent.intentId

			local msg = createMockMsg({
				From = 'ant-token-123',
				Tags = {
					['X-Intent-Id'] = childId,
				},
			})

			notices.debitNoticeHandler(msg)

			-- Child should be resolved
			local child = intents.getIntentById(childId)
			assert.are.equal('resolved', child.status)
			
			-- Should send acknowledgment
			local debitProcessed = false
			for _, sentMsg in ipairs(testGlobals.sentMessages) do
				if sentMsg.Action == 'Debit-Notice-Processed' then
					debitProcessed = true
					assert.are.equal(childId, sentMsg.Tags['Intent-Id'])
					assert.are.equal(parentId, sentMsg.Tags['Parent-Intent-Id'])
					break
				end
			end
			assert.is_true(debitProcessed)
		end)

		it('should return early if no X-Intent-Id', function()
			local msg = createMockMsg({
				From = 'ant-token-123',
				Tags = {},
			})

			-- Should not crash
			notices.debitNoticeHandler(msg)
		end)

		it('should return early if invalid intent ID format', function()
			local msg = createMockMsg({
				From = 'ant-token-123',
				Tags = {
					['X-Intent-Id'] = 'invalid',
				},
			})

			-- Should not crash
			notices.debitNoticeHandler(msg)
		end)

		it('should return early if intent not found', function()
			local msg = createMockMsg({
				From = 'ant-token-123',
				Tags = {
					['X-Intent-Id'] = 'intent-nonexistent',
				},
			})

			-- Should not crash
			notices.debitNoticeHandler(msg)
		end)

		it('should validate expected sender matches', function()
			-- Fund user for listing fee
			ARIOBalances['user-123'] = { balance = '10000000000', orders = {} }
			
			-- Create parent intent
			local parentMsg = { From = 'user-123', Timestamp = 1000 }
			local parentIntent = intents.createParentIntent(parentMsg, 'Create-Order', {})
			local parentId = parentIntent.intentId

			-- Create child intent
			local childMsg = { From = 'user-123', Timestamp = 1000 }
			local childIntent = intents.createChildIntent(parentId, childMsg, 'ant-token-123', {})
			local childId = childIntent.intentId

			local msg = createMockMsg({
				From = 'wrong-token-456', -- Wrong sender
				Tags = {
					['X-Intent-Id'] = childId,
				},
			})

			notices.debitNoticeHandler(msg)

			-- Child should NOT be resolved
			local child = intents.getIntentById(childId)
			assert.are.equal('pending', child.status)
		end)
	end)

	describe('transferErrorHandler', function()
		it('should fail child intent on Transfer-Error', function()
			-- Fund user for listing fee
			ARIOBalances['user-123'] = { balance = '10000000000', orders = {} }
			
			-- Create parent intent
			local parentMsg = { From = 'user-123', Timestamp = 1000 }
			local parentIntent = intents.createParentIntent(parentMsg, 'Create-Order', {})
			local parentId = parentIntent.intentId

			-- Create child intent
			local childMsg = { From = 'user-123', Timestamp = 1000 }
			local childIntent = intents.createChildIntent(parentId, childMsg, 'ant-token-123', {})
			local childId = childIntent.intentId

			local msg = createMockMsg({
				From = 'ant-token-123',
				Tags = {
					['X-Intent-Id'] = childId,
					Message = 'Transfer failed: insufficient balance',
				},
			})

			notices.transferErrorHandler(msg)

			-- Child should be failed
			local child = intents.getIntentById(childId)
			assert.are.equal('failed', child.status)
			
			-- Parent should also be failed
			local parent = intents.getIntentById(parentId)
			assert.are.equal('failed', parent.status)
		end)

		it('should return early if no X-Intent-Id', function()
			local msg = createMockMsg({
				From = 'ant-token-123',
				Tags = {},
			})

			-- Should not crash
			notices.transferErrorHandler(msg)
		end)

		it('should return early if invalid intent ID format', function()
			local msg = createMockMsg({
				From = 'ant-token-123',
				Tags = {
					['X-Intent-Id'] = 'invalid',
				},
			})

			-- Should not crash
			notices.transferErrorHandler(msg)
		end)

		it('should return early if intent not found', function()
			local msg = createMockMsg({
				From = 'ant-token-123',
				Tags = {
					['X-Intent-Id'] = 'intent-nonexistent',
				},
			})

			-- Should not crash
			notices.transferErrorHandler(msg)
		end)

		it('should return early if intent is not a child intent', function()
			-- Fund user for listing fee
			ARIOBalances['user-123'] = { balance = '10000000000', orders = {} }
			
			-- Create parent intent (not child)
			local parentMsg = { From = 'user-123', Timestamp = 1000 }
			local parentIntent = intents.createParentIntent(parentMsg, 'Create-Order', {})
			local parentId = parentIntent.intentId

			local msg = createMockMsg({
				From = 'ant-token-123',
				Tags = {
					['X-Intent-Id'] = parentId,
					Message = 'Some error',
				},
			})

			notices.transferErrorHandler(msg)

			-- Parent should NOT be failed
			local parent = intents.getIntentById(parentId)
			assert.are.not_equal('failed', parent.status)
		end)

		it('should use Data field if Message/Error tags not present', function()
			-- Fund user for listing fee
			ARIOBalances['user-123'] = { balance = '10000000000', orders = {} }
			
			-- Create parent intent
			local parentMsg = { From = 'user-123', Timestamp = 1000 }
			local parentIntent = intents.createParentIntent(parentMsg, 'Create-Order', {})
			local parentId = parentIntent.intentId

			-- Create child intent
			local childMsg = { From = 'user-123', Timestamp = 1000 }
			local childIntent = intents.createChildIntent(parentId, childMsg, 'ant-token-123', {})
			local childId = childIntent.intentId

			local msg = createMockMsg({
				From = 'ant-token-123',
				Data = 'Error in Data field',
				Tags = {
					['X-Intent-Id'] = childId,
				},
			})

			notices.transferErrorHandler(msg)

			-- Child should be failed
			local child = intents.getIntentById(childId)
			assert.are.equal('failed', child.status)
			assert.is_true(string.find(child.failureReason or '', 'Error in Data field') ~= nil)
		end)
	end)
end)

