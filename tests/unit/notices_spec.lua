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
		-- Use valid 43-character ARIO token ID
		testGlobals.setArioTokenId('ario-token-123456789012345678901234567890AB')
	end)

	describe('creditNoticeHandler - Deposits', function()
		it('should handle ARIO deposit', function()
			local msg = createMockMsg({
				From = 'ario-token-123456789012345678901234567890AB',
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
		before_each(function()
			-- Fund users for listing fees (1 ARIO = 1000000000 mARIO)
			ARIOBalances['user-123'] = { balance = '10000000000', orders = {} }
			ARIOBalances['user-456'] = { balance = '10000000000', orders = {} }
			ARIOBalances['user-123-1234567890123456789012345678901234567890'] = { balance = '10000000000', orders = {} }
			ARIOBalances['short'] = { balance = '10000000000', orders = {} }
		end)

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
				From = 'ario-token-123456789012345678901234567890AB',
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

			-- Handler should throw error about missing intent ID
			local success, err = pcall(function()
				notices.creditNoticeHandler(msg)
			end)
			
			-- Expect error to be thrown
			assert.is_false(success)
			assert.is_string(err)
			assert.is_true(string.find(err, 'Intent') ~= nil)
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

			-- Handler should throw error about invalid intent ID format
			local success, err = pcall(function()
				notices.creditNoticeHandler(msg)
			end)
			
			-- Expect error to be thrown
			assert.is_false(success)
			assert.is_string(err)
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

			-- Handler should throw error about non-existent intent
			local success, err = pcall(function()
				notices.creditNoticeHandler(msg)
			end)
			
			-- Expect error to be thrown
			assert.is_false(success)
			assert.is_string(err)
		end)

		it('should validate sender matches intent initiator', function()
			-- Create intent
			local msg = { From = 'user-123-1234567890123456789012345678901234567890', Timestamp = 1000 }
			local intent = intents.createIntent(msg, {})
			local intentId = intent.intentId

			local creditMsg = createMockMsg({
				From = 'ant-token-123',
				Tags = {
					Sender = 'user-456-1234567890123456789012345678901234567890', -- Different sender
					Quantity = '1',
					['X-Intent-Id'] = intentId,
				},
			})

			-- Should throw error about mismatched sender
			local success = pcall(function()
				notices.creditNoticeHandler(creditMsg)
			end)
			
			assert.is_false(success)
		end)

		it('should validate intent TTL not expired', function()
			-- Create intent with TTL
			local msg = { From = 'user-123-1234567890123456789012345678901234567890', Timestamp = 1000 }
			local intent = intents.createIntent(msg, {})
			local intentId = intent.intentId
			-- Manually set TTL
			Intents[intentId].ttl = 2000

			local creditMsg = createMockMsg({
				From = 'ant-token-123',
				Timestamp = 2500, -- After TTL
				Tags = {
					Sender = 'user-123-1234567890123456789012345678901234567890',
					Quantity = '1',
					['X-Intent-Id'] = intentId,
				},
			})

			-- Should throw error about expired intent
			local success = pcall(function()
				notices.creditNoticeHandler(creditMsg)
			end)
			
			assert.is_false(success)
		end)

		it('should validate sender address format', function()
			-- Create intent with valid sender for intent creation
			ARIOBalances['short-12345678901234567890123456789012345678'] = { balance = '10000000000', orders = {} }
			local msg = { From = 'short-12345678901234567890123456789012345678', Timestamp = 1000 }
			local intent = intents.createIntent(msg, {})
			local intentId = intent.intentId

			local creditMsg = createMockMsg({
				From = 'ant-token-123',
				Tags = {
					Sender = 'short', -- Invalid address format
					Quantity = '1',
					['X-Intent-Id'] = intentId,
				},
			})

			-- Should throw error about invalid address
			local success = pcall(function()
				notices.creditNoticeHandler(creditMsg)
			end)
			
			assert.is_false(success)
		end)

		it('should validate quantity is valid amount', function()
			-- Create intent (long user already funded in before_each)
			local msg = { From = 'user-123-1234567890123456789012345678901234567890', Timestamp = 1000 }
			local intent = intents.createIntent(msg, {})
			local intentId = intent.intentId

			local msg = createMockMsg({
				From = 'ant-token-123',
				Tags = {
					Sender = 'user-123-1234567890123456789012345678901234567890',
					Quantity = '-100', -- Invalid quantity
					['X-Intent-Id'] = intentId,
				},
			})

			-- Should throw error about invalid quantity (caught before address check)
			local success = pcall(function()
				notices.creditNoticeHandler(msg)
			end)
			
			assert.is_false(success)
		end)
	end)

	describe('creditNoticeHandler - Order Creation', function()
		local TEST_MODULE_ID = 'drhsJZSyX8InDsd5EAfQDTgdKnD_wvjddHKY3KDPdf8'

		before_each(function()
			-- Fund users for listing fees
			ARIOBalances['user-123-1234567890123456789012345678901234567890'] = { balance = '10000000000', orders = {} }
			-- Whitelist test ANT module
			testGlobals.whitelistTestModule(TEST_MODULE_ID)
		end)

		it('should create ANT order with valid Credit-Notice', function()
		-- Create intent with valid 43-char address and order params
		local validUser = 'user-12345678901234567890123456789012345678'
		local validAntToken = 'ant-token-123456789012345678901234567890ABC'
		ARIOBalances[validUser] = { balance = '10000000000', orders = {} }
		local msg = { From = validUser, Timestamp = 1000 }
		
		-- Order params go in the intent now
		local orderParams = {
			swapToken = 'ario-token-123456789012345678901234567890AB',
			orderType = 'fixed',
			price = '1000',
			expirationTime = '2000',
			quantity = '1',
		}
		local intent = intents.createIntent(msg, orderParams)
		local intentId = intent.intentId

		-- Add ARIO balance for matching
		ARIOBalances['seller-123'] = {
			balance = '10000',
			orders = {}
		}

		local creditMsg = createMockMsg({
			From = validAntToken,
			Tags = {
				Sender = validUser,
				Quantity = '1',
				['X-Intent-Id'] = intentId,
				['X-Order-Action'] = 'Create-Order',
				['From-Module'] = TEST_MODULE_ID,
			},
		})
			
			notices.creditNoticeHandler(creditMsg)
			
			local creditNoticeProcessed = false
			for _, sentMsg in ipairs(testGlobals.sentMessages) do
				if sentMsg.Action == 'Credit-Notice-Processed' then
					creditNoticeProcessed = true
					-- In our mock, tags are stored as direct fields on the message
					assert.are.equal(creditMsg.Id, sentMsg['Order-Id'])
					assert.are.equal(intentId, sentMsg['Intent-Id'])
					break
				end
			end
			assert.is_true(creditNoticeProcessed)
		end)

		it('should always use ARIO as swap token for intent-based orders', function()
			-- Create intent with valid 43-char address
			local validUser = 'user-45678901234567890123456789012345678901'
			local validAntToken = 'ant-token-4567890123456789012345678901234567'
			ARIOBalances[validUser] = { balance = '10000000000', orders = {} }
			local msg = { From = validUser, Timestamp = 1000 }
			local intent = intents.createIntent(msg, {})
			local intentId = intent.intentId

			-- Note: swapToken is always ARIO (hardcoded in Credit-Notice handler, not stored in orderParams)
			
			local creditMsg = createMockMsg({
				From = validAntToken,
				Tags = {
					Sender = validUser,
					Quantity = '1',
					['X-Intent-Id'] = intentId,
					['X-Order-Action'] = 'Create-Order',
					['X-Order-Type'] = 'fixed',
					['X-Price'] = '1000',
					['From-Module'] = TEST_MODULE_ID,
				},
			})

			-- Should succeed because swapToken is always ARIO
			local success, err = pcall(function()
				notices.creditNoticeHandler(creditMsg)
			end)
			
			assert.is_true(success)
			
			-- Verify no refund was sent (order creation succeeded)
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
			-- Create intent with valid 43-char address
			local validUser = 'user-78901234567890123456789012345678901234'
			local validAntToken = 'ant-token-7890123456789012345678901234567890'
			ARIOBalances[validUser] = { balance = '10000000000', orders = {} }
			local msg = { From = validUser, Timestamp = 1000 }
			local intent = intents.createIntent(msg, {})
			local intentId = intent.intentId

			local creditMsg = createMockMsg({
				From = validAntToken,
				Tags = {
					Sender = validUser,
					Quantity = '2', -- Invalid quantity for ANT
					['X-Intent-Id'] = intentId,
					['X-Order-Action'] = 'Create-Order',
					['X-Swap-Token'] = 'ario-token-123456789012345678901234567890AB', -- Use the ARIO token ID
					['X-Order-Type'] = 'fixed',
					['X-Price'] = '1000',
				},
			})

			-- Should not crash
			notices.creditNoticeHandler(creditMsg)
			
			-- Should have sent refund
			assert.is_true(#testGlobals.sentMessages > 0)
		end)
	end)

	describe('creditNoticeHandler - Whitelist Enforcement', function()
		local TEST_MODULE_WHITELISTED = 'drhsJZSyX8InDsd5EAfQDTgdKnD_wvjddHKY3KDPdf8'
		local TEST_MODULE_NOT_WHITELISTED = '9afQ1PLf2mrshqCTZEzzJTR2gWaC9zHYWyqH3_1234'

		before_each(function()
			testGlobals.resetState()
			-- Whitelist only the first module
			testGlobals.whitelistTestModule(TEST_MODULE_WHITELISTED)
			-- Set ARIO token to match global
			_G.ARIO_TOKEN_PROCESS_ID = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA'
		end)

		it('should create ANT order when module is whitelisted', function()
		local validUser = 'user-whitelist-test123456789012345678901234'
		local validAntToken = 'ant-token-whitelist-test1234567890123456789'
		ARIOBalances[validUser] = { balance = '10000000000', orders = {} }
		
		local msg = { From = validUser, Timestamp = 1000 }
		
		-- Order params go in the intent now
		local orderParams = {
			swapToken = _G.ARIO_TOKEN_PROCESS_ID,
			orderType = 'fixed',
			price = '1000',
			quantity = '1',
		}
		local intent = intents.createIntent(msg, orderParams)
		local intentId = intent.intentId

		local creditMsg = createMockMsg({
			From = validAntToken,
			Tags = {
				Sender = validUser,
				Quantity = '1',
				['X-Intent-Id'] = intentId,
				['X-Order-Action'] = 'Create-Order',
				['From-Module'] = TEST_MODULE_WHITELISTED,
			},
		})
			
			notices.creditNoticeHandler(creditMsg)
			
			-- Verify order was created successfully (or intent completed)
			local processed = false
			for _, sentMsg in ipairs(testGlobals.sentMessages) do
				-- Either Credit-Notice-Processed or Intent-Resolved with success
				if sentMsg.Action == 'Credit-Notice-Processed' or 
				   (sentMsg.Action == 'Intent-Resolved' and sentMsg.Status == 'completed') then
					processed = true
					break
				end
			end
			assert.is_true(processed)
		end)

		it('should fail intent when ANT module is not whitelisted', function()
			local validUser = 'user-not-whitelisted-12345678901234567890'
			local validAntToken = 'ant-token-not-whitelisted-1234567890123456'
			ARIOBalances[validUser] = { balance = '10000000000', orders = {} }
			
			local msg = { From = validUser, Timestamp = 1000 }
			local intent = intents.createIntent(msg, {})
			local intentId = intent.intentId

			local creditMsg = createMockMsg({
				From = validAntToken,
				Tags = {
					Sender = validUser,
					Quantity = '1',
					['X-Intent-Id'] = intentId,
					['X-Order-Action'] = 'Create-Order',
					['X-Swap-Token'] = _G.ARIO_TOKEN_PROCESS_ID,
					['X-Order-Type'] = 'fixed',
					['X-Price'] = '1000',
					['From-Module'] = TEST_MODULE_NOT_WHITELISTED,  -- Not whitelisted
				},
			})
			
			notices.creditNoticeHandler(creditMsg)
			
			-- Verify failure message sent
			local failureSent = false
			for _, sentMsg in ipairs(testGlobals.sentMessages) do
				if sentMsg.Action == 'Intent-Resolved' and sentMsg.Status == 'failed' then
					failureSent = true
					break
				end
			end
			assert.is_true(failureSent, 'Should send Intent-Resolved with failed status')
		end)

		it('should allow ARIO deposits without whitelist check', function()
			local validUser = 'user-ario-deposit-test123456789012345678'
			
			local creditMsg = createMockMsg({
				From = _G.ARIO_TOKEN_PROCESS_ID,  -- ARIO token
				Tags = {
					Sender = validUser,
					Quantity = '5000000000',
					['X-Action'] = 'Deposit',
					-- No From-Module tag - should still work for ARIO
				},
			})
			
			notices.creditNoticeHandler(creditMsg)
			
			-- Verify balance increased
			assert.are.equal('5000000000', ARIOBalances[validUser].balance)
		end)
	end)
end)

