print('\n=== Loading balances module for testing ===')
local testGlobals = require('test_globals')
local balances = require('balances')
print('✓ balances module loaded')

describe('Balance Management', function()
	print('\n--- Starting Balance Management tests ---')
	before_each(function()
		-- Reset global state
		testGlobals.resetState()
		testGlobals.setArioTokenId('ario-token-123')
	end)

	describe('increaseBalance', function()
		it('should increase balance for new address', function()
			balances.increaseBalance('user-123', '1000')

			assert.are.equal('1000', ARIOBalances['user-123'].balance)
		end)

		it('should increase existing balance', function()
			ARIOBalances['user-456'] = {balance = '500', orders = {}}
			balances.increaseBalance('user-456', '300')

			assert.are.equal('800', ARIOBalances['user-456'].balance)
		end)

		it('should fail with invalid quantity', function()
			local success, _ = pcall(function()
				balances.increaseBalance('user-789', '-100')
			end)

			assert.is_false(success)
		end)
	end)

	describe('reduceBalance', function()
		it('should reduce balance', function()
			ARIOBalances['user-123'] = {balance = '1000', orders = {}}
			balances.reduceBalance('user-123', '300')

			assert.are.equal('700', ARIOBalances['user-123'].balance)
		end)

		it('should fail if insufficient balance', function()
			ARIOBalances['user-456'] = {balance = '100', orders = {}}

			local success, _ = pcall(function()
				balances.reduceBalance('user-456', '200')
			end)

			assert.is_false(success)
		end)

		it('should fail with invalid quantity', function()
			ARIOBalances['user-789'] = {balance = '1000', orders = {}}

			local success, _ = pcall(function()
				balances.reduceBalance('user-789', '-100')
			end)

			assert.is_false(success)
		end)
	end)

	describe('transfer', function()
		it('should transfer from one address to another', function()
			ARIOBalances['user-from'] = {balance = '1000', orders = {}}
			ARIOBalances['user-to'] = {balance = '500', orders = {}}

			local result = balances.transfer('user-to', 'user-from', '300', true)

			assert.are.equal('700', ARIOBalances['user-from'].balance)
			assert.are.equal('800', ARIOBalances['user-to'].balance)
			assert.is_table(result)
		end)

		it('should fail if insufficient balance', function()
			ARIOBalances['user-poor'] = {balance = '100', orders = {}}

			local success, _ = pcall(function()
				balances.transfer('user-rich', 'user-poor', '200', true)
			end)

			assert.is_false(success)
		end)

		it('should fail for self-transfer', function()
			ARIOBalances['user-self'] = {balance = '1000', orders = {}}

			local success, _ = pcall(function()
				balances.transfer('user-self', 'user-self', '100', true)
			end)

			assert.is_false(success)
		end)
	end)

	describe('walletHasSufficientBalance', function()
		it('should return true for sufficient balance', function()
			ARIOBalances['user-123'] = {balance = '1000', orders = {}}

			assert.is_true(balances.walletHasSufficientBalance('user-123', '500'))
			assert.is_true(balances.walletHasSufficientBalance('user-123', '1000'))
		end)

		it('should return false for insufficient balance', function()
			ARIOBalances['user-456'] = {balance = '100', orders = {}}

			assert.is_false(balances.walletHasSufficientBalance('user-456', '200'))
		end)

		it('should return false for non-existent address', function()
			assert.is_false(balances.walletHasSufficientBalance('user-nonexistent', '100'))
		end)
	end)

	describe('getBalance', function()
		it('should return balance for existing address', function()
			ARIOBalances['user-123'] = {balance = '1500', orders = {}}

			local balance = balances.getBalance('user-123')

			assert.are.equal('1500', balance)
		end)

		it('should return 0 for non-existent address', function()
			local balance = balances.getBalance('user-nonexistent')

			assert.are.equal('0', balance)
		end)
	end)

	describe('handleDeposit', function()
		it('should increase balance and send notice', function()
			local msg = {
				Tags = {
					Sender = 'user-depositor',
					Quantity = '5000',
				},
			}

			balances.handleDeposit(msg)

			assert.are.equal('5000', ARIOBalances['user-depositor'].balance)
		end)

		it('should handle multiple deposits', function()
			local msg1 = {
				Tags = {
					Sender = 'user-multi',
					Quantity = '1000',
				},
			}

			local msg2 = {
				Tags = {
					Sender = 'user-multi',
					Quantity = '2000',
				},
			}

			balances.handleDeposit(msg1)
			balances.handleDeposit(msg2)

			assert.are.equal('3000', ARIOBalances['user-multi'].balance)
		end)
	end)

	describe('withdrawArioHandler', function()
		local sentMessages

		before_each(function()
			-- Mock ao.send to track messages
			sentMessages = {}
			---@diagnostic disable-next-line: duplicate-set-field
			_G.ao.send = function(msg)
				table.insert(sentMessages, msg)
				return true
			end
		end)

		it('should reduce balance and send direct transfer (no intent)', function()
			ARIOBalances['user-withdraw'] = {balance = '10000', orders = {}}

			local msg = {
				From = 'user-withdraw',
				Tags = {
					Quantity = '3000',
				},
			}

			local result = balances.withdrawArioHandler(msg)

			-- Balance should be reduced
			assert.are.equal('7000', ARIOBalances['user-withdraw'].balance)

			-- Should return JSON with status and details
			local json = require('json')
			local resultData = json.decode(result)
			assert.are.equal('Success', resultData.Status)
			assert.are.equal('ARIO withdrawal initiated', resultData.Message)
			assert.are.equal('3000', resultData.Quantity)
			assert.are.equal('user-withdraw', resultData.Recipient)

			-- Should send Transfer message (ucm.transfer, not ucm.transferWithIntent)
			assert.are.equal(1, #sentMessages) -- Only Transfer (notice sent by wrapper)
			
			-- Message should be the Transfer (no X-Intent-Id tag)
			local transferMsg = sentMessages[1]
			assert.are.equal('Transfer', transferMsg.Action)
			assert.are.equal(ARIO_TOKEN_PROCESS_ID, transferMsg.Target)
			assert.are.equal('user-withdraw', transferMsg.Tags.Recipient)
			assert.are.equal('3000', transferMsg.Tags.Quantity)
			
			-- Verify NO intent tracking (no X-Intent-Id tag)
			assert.is_nil(transferMsg.Tags['X-Intent-Id'])
		end)
		
		it('should support custom recipient', function()
			ARIOBalances['user-withdraw'] = {balance = '10000', orders = {}}

			local msg = {
				From = 'user-withdraw',
				Tags = {
					Quantity = '3000',
					Recipient = 'other-user',
				},
			}

			local result = balances.withdrawArioHandler(msg)

			-- Balance should be reduced from sender
			assert.are.equal('7000', ARIOBalances['user-withdraw'].balance)

			-- Result should show custom recipient
			local json = require('json')
			local resultData = json.decode(result)
			assert.are.equal('other-user', resultData.Recipient)

			-- Transfer should go to custom recipient
			local transferMsg = sentMessages[1]
			assert.are.equal('other-user', transferMsg.Tags.Recipient)
		end)

		it('should fail with insufficient balance', function()
			ARIOBalances['user-poor'] = {balance = '100', orders = {}}

			local msg = {
				From = 'user-poor',
				Tags = {
					Quantity = '200',
				},
			}

			local success, err = pcall(function()
				balances.withdrawArioHandler(msg)
			end)

			assert.is_false(success)
			assert.is_not_nil(err)
			assert.is_true(string.find(tostring(err), 'Insufficient balance') ~= nil)
			
			-- Balance should remain unchanged
			assert.are.equal('100', ARIOBalances['user-poor'].balance)
		end)
	end)

	describe('English Auction Bid Balances', function()
		local orderId = 'order-auction-123'
		local bidder1 = 'bidder-alice'
		local bidder2 = 'bidder-bob'

		before_each(function()
			-- Reset state and give bidders some balance
			testGlobals.resetState()
			ARIOBalances[bidder1] = {balance = '10000', orders = {}}
			ARIOBalances[bidder2] = {balance = '20000', orders = {}}
		end)

		describe('lockBalanceForOrder', function()
			it('should transfer ARIO from available balance to locked', function()
				balances.lockBalanceForOrder(orderId, bidder1, '1000')

				-- Available balance should be reduced
				assert.are.equal('9000', ARIOBalances[bidder1].balance)
				-- Locked balance should be set
				assert.are.equal('1000', ARIOBalances[bidder1].orders[orderId])
			end)

			it('should accumulate multiple locks for same bidder', function()
				balances.lockBalanceForOrder(orderId, bidder1, '1000')
				balances.lockBalanceForOrder(orderId, bidder1, '500')

				assert.are.equal('8500', ARIOBalances[bidder1].balance)
				assert.are.equal('1500', ARIOBalances[bidder1].orders[orderId])
			end)

			it('should handle multiple bidders on same order', function()
				balances.lockBalanceForOrder(orderId, bidder1, '1000')
				balances.lockBalanceForOrder(orderId, bidder2, '2000')

				assert.are.equal('9000', ARIOBalances[bidder1].balance)
				assert.are.equal('18000', ARIOBalances[bidder2].balance)
				assert.are.equal('1000', ARIOBalances[bidder1].orders[orderId])
				assert.are.equal('2000', ARIOBalances[bidder2].orders[orderId])
			end)

			it('should fail with insufficient balance', function()
				local success = pcall(function()
					balances.lockBalanceForOrder(orderId, bidder1, '15000')
				end)

				assert.is_false(success)
			end)
		end)

		describe('unlockBalanceFromOrder', function()
			it('should transfer ARIO from locked back to bidder available balance', function()
				-- Lock first
				balances.lockBalanceForOrder(orderId, bidder1, '1000')
				assert.are.equal('9000', ARIOBalances[bidder1].balance)

				-- Unlock back to bidder
				balances.unlockBalanceFromOrder(orderId, bidder1, bidder1, '1000')
				assert.are.equal('10000', ARIOBalances[bidder1].balance)
				assert.is_nil(ARIOBalances[bidder1].orders[orderId])
			end)

			it('should handle partial transfer back to bidder', function()
				balances.lockBalanceForOrder(orderId, bidder1, '1000')
				balances.unlockBalanceFromOrder(orderId, bidder1, bidder1, '600')

				assert.are.equal('9600', ARIOBalances[bidder1].balance)
				assert.are.equal('400', ARIOBalances[bidder1].orders[orderId])
			end)

			it('should fail if no locked balance exists', function()
				local success = pcall(function()
					balances.unlockBalanceFromOrder(orderId, bidder1, bidder1, '500')
				end)

				assert.is_false(success)
			end)

			it('should fail if insufficient locked balance', function()
				balances.lockBalanceForOrder(orderId, bidder1, '1000')

				local success = pcall(function()
					balances.unlockBalanceFromOrder(orderId, bidder1, bidder1, '1500')
				end)

				assert.is_false(success)
			end)

			it('should transfer ARIO from locked to different recipient', function()
				-- Setup: bidder locks ARIO
				balances.lockBalanceForOrder(orderId, bidder1, '1000')
				local recipient = 'seller-xyz'

				-- Transfer locked to recipient
				balances.unlockBalanceFromOrder(orderId, bidder1, recipient, '1000')

				-- Bidder's available balance should still be 9000 (was reduced by lock)
				assert.are.equal('9000', ARIOBalances[bidder1].balance)
				-- Recipient should receive the locked amount
				assert.are.equal('1000', ARIOBalances[recipient].balance)
				-- Locked balance should be cleared
				assert.is_nil(ARIOBalances[bidder1].orders[orderId])
			end)

			it('should handle partial transfer to recipient', function()
				balances.lockBalanceForOrder(orderId, bidder1, '1000')
				local recipient = 'seller-xyz'

				balances.unlockBalanceFromOrder(orderId, bidder1, recipient, '600')

				assert.are.equal('9000', ARIOBalances[bidder1].balance)
				assert.are.equal('600', ARIOBalances[recipient].balance)
				assert.are.equal('400', ARIOBalances[bidder1].orders[orderId])
			end)

			it('should fail if no locked balance exists', function()
				local recipient = 'seller-xyz'

				local success = pcall(function()
					balances.unlockBalanceFromOrder(orderId, bidder1, recipient, '500')
				end)

				assert.is_false(success)
			end)
		end)

		describe('getOrderLockedBalance', function()
			it('should return locked balance for user on order', function()
				balances.lockBalanceForOrder(orderId, bidder1, '1500')

				local lockedBalance = balances.getOrderLockedBalance(orderId, bidder1)
				assert.are.equal('1500', lockedBalance)
			end)

			it('should return 0 if no locked balance', function()
				local lockedBalance = balances.getOrderLockedBalance(orderId, bidder1)
				assert.are.equal('0', lockedBalance)
			end)

			it('should return 0 for different order', function()
				balances.lockBalanceForOrder(orderId, bidder1, '1000')

				local lockedBalance = balances.getOrderLockedBalance('other-order-456', bidder1)
				assert.are.equal('0', lockedBalance)
			end)
		end)

		describe('getUserTotalLockedBalance', function()
			it('should return total locked balance across all orders', function()
				local order2 = 'order-auction-456'
				
				-- Lock to multiple orders
				balances.lockBalanceForOrder(orderId, bidder1, '1000')
				balances.lockBalanceForOrder(order2, bidder1, '2000')
				
				local totalLocked = balances.getUserTotalLockedBalance(bidder1)
				assert.are.equal('3000', totalLocked)
			end)

			it('should return 0 if no locked balance', function()
				local totalLocked = balances.getUserTotalLockedBalance(bidder1)
				assert.are.equal('0', totalLocked)
			end)
		end)

		describe('getUserBalanceBreakdown', function()
			it('should return available, locked, and total', function()
				-- Setup: user starts with 5000, locks 1500
				ARIOBalances[bidder1] = {balance = '5000', orders = {}}
				
				-- Lock some balance
				balances.lockBalanceForOrder(orderId, bidder1, '1500')
				
				local breakdown = balances.getUserBalanceBreakdown(bidder1)
				assert.are.equal('3500', breakdown.available) -- 5000 - 1500 locked
				assert.are.equal('1500', breakdown.locked)
				assert.are.equal('5000', breakdown.total)
			end)

			it('should handle user with no locked balance', function()
				ARIOBalances[bidder1] = {balance = '10000', orders = {}}
				
				local breakdown = balances.getUserBalanceBreakdown(bidder1)
				assert.are.equal('10000', breakdown.available)
				assert.are.equal('0', breakdown.locked)
				assert.are.equal('10000', breakdown.total)
			end)

		it('should handle user with no balance at all', function()
			-- Clear balance set by before_each
			ARIOBalances[bidder1] = nil
			
			local breakdown = balances.getUserBalanceBreakdown(bidder1)
			assert.are.equal('0', breakdown.available)
			assert.are.equal('0', breakdown.locked)
			assert.are.equal('0', breakdown.total)
		end)
		end)
	end)
end)

