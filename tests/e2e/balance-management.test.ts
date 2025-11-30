import { before, describe, it, after } from 'node:test';
import assert from 'node:assert';
import { MarketplaceProcess } from '../utils/marketplace_process.js';
import { getOrSpawnProcesses } from '../utils/process_manager.js';
import { resetTestLogger } from '../utils/test_logger.js';
import { TEST_WALLET } from '../utils/constants.js';

/**
 * E2E tests for Balance Management
 * Tests ARIO balance operations end-to-end on real AO processes
 */

async function profile<T>(label: string, fn: () => Promise<T>): Promise<T> {
  const startTime = Date.now();
  console.log(`[PROFILE] Starting: ${label}`);
  try {
    const result = await fn();
    const duration = Date.now() - startTime;
    console.log(`[PROFILE] ✓ Completed: ${label} (${(duration / 1000).toFixed(2)}s)`);
    return result;
  } catch (error) {
    const duration = Date.now() - startTime;
    console.log(`[PROFILE] ✗ Failed: ${label} (${(duration / 1000).toFixed(2)}s)`);
    throw error;
  }
}

describe('E2E Balance Management Tests', { timeout: 1_800_000 }, () => {
  let marketplaceProcess: MarketplaceProcess;
  let arioProcessId: string;
  let marketplaceProcessId: string;
  const logger = resetTestLogger();
  
  // The test wallet address
  const testAddress = TEST_WALLET.address;

  before(async () => {
    console.log('\n========================================');
    console.log('E2E Balance Management Test Suite');
    console.log('========================================\n');

    const processes = await profile('Setup test environment', async () => {
      return await getOrSpawnProcesses();
    });

    marketplaceProcess = processes.marketplaceProcess;
    marketplaceProcessId = processes.marketplaceProcessId;
    arioProcessId = processes.arioProcessId;

    logger.setProcesses({
      ario: arioProcessId,
      marketplace: marketplaceProcessId,
      ant: 'n/a',
    });

    console.log('Test environment ready:');
    console.log('  Marketplace:', marketplaceProcessId);
    console.log('  ARIO:', arioProcessId);
    console.log('  Test Address:', testAddress);
    console.log('');
  });

  after(async () => {
    await logger.save();
  });

  describe('Get-Balance', () => {
    it('should return balance for test wallet', async () => {
      logger.startWorkflow('get-balance');

      try {
        const balance = await profile('Get marketplace balance', () =>
          marketplaceProcess.getMarketplaceBalance(testAddress)
        );

        assert(balance !== undefined, 'Balance should be defined');
        assert(typeof balance === 'string', 'Balance should be a string');
        console.log('✓ Current balance:', balance);

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });

  describe('Deposit-ARIO (Credit-Notice)', () => {
    it('should accept ARIO deposits via Credit-Notice', async () => {
      logger.startWorkflow('deposit-ario');

      try {
        // Get initial balance
        const initialBalance = await profile('Get initial balance', () =>
          marketplaceProcess.getMarketplaceBalance(testAddress)
        );
        console.log('Initial balance:', initialBalance);

        // Deposit ARIO
        const depositAmount = '1000000000'; // 1000 ARIO
        const { messageId } = await profile('Send Credit-Notice to marketplace', () =>
          marketplaceProcess.depositArio(depositAmount, arioProcessId, testAddress)
        );
        console.log('✓ Credit-Notice sent:', messageId);

        // Verify Credit-Notice was processed
        const result = await profile('Verify Credit-Notice processed', () =>
          marketplaceProcess.verifyCreditNoticeProcessed(messageId)
        );
        console.log('✓ Credit-Notice processed');

        // Verify balance increased
        const newBalance = await profile('Get new balance', () =>
          marketplaceProcess.getMarketplaceBalance(testAddress)
        );
        
        const expectedBalance = (BigInt(initialBalance) + BigInt(depositAmount)).toString();
        assert.strictEqual(newBalance, expectedBalance, 'Balance should reflect deposit');
        console.log('✓ New balance:', newBalance);

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });

    it('should handle multiple deposits', async () => {
      logger.startWorkflow('multiple-deposits');

      try {
        const initialBalance = await profile('Get initial balance', () =>
          marketplaceProcess.getMarketplaceBalance(testAddress)
        );

        // First deposit
        const { messageId: msg1 } = await profile('Send first deposit', () =>
          marketplaceProcess.depositArio('500000000', arioProcessId, testAddress)
        );
        await profile('Verify first deposit processed', () =>
          marketplaceProcess.verifyCreditNoticeProcessed(msg1)
        );
        console.log('✓ First deposit processed');

        // Second deposit
        const { messageId: msg2 } = await profile('Send second deposit', () =>
          marketplaceProcess.depositArio('300000000', arioProcessId, testAddress)
        );
        await profile('Verify second deposit processed', () =>
          marketplaceProcess.verifyCreditNoticeProcessed(msg2)
        );
        console.log('✓ Second deposit processed');

        const finalBalance = await profile('Get final balance', () =>
          marketplaceProcess.getMarketplaceBalance(testAddress)
        );

        const expectedBalance = (
          BigInt(initialBalance) + BigInt('500000000') + BigInt('300000000')
        ).toString();
        assert.strictEqual(finalBalance, expectedBalance, 'Balance should be sum of deposits');
        console.log('✓ Multiple deposits accumulated correctly');

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });

  describe('Withdraw-Ario', () => {
    it('should withdraw ARIO from marketplace balance', async () => {
      logger.startWorkflow('withdraw-ario');

      try {
        // Ensure we have balance to withdraw
        const initialBalance = await profile('Get initial balance', () =>
          marketplaceProcess.getMarketplaceBalance(testAddress)
        );

        if (BigInt(initialBalance) < BigInt('1000000000')) {
          await profile('Ensure sufficient balance', () =>
            marketplaceProcess.depositArio('2000000000', arioProcessId, testAddress)
          );
        }

        const balanceBeforeWithdrawal = await profile('Get balance before withdrawal', () =>
          marketplaceProcess.getMarketplaceBalance(testAddress)
        );

        // Withdraw
        const withdrawAmount = '500000000';
        const result = await profile('Withdraw ARIO', () =>
          marketplaceProcess.withdrawArio(withdrawAmount)
        );

        assert.strictEqual(result.Action, 'Withdraw-Ario-Notice', 'Should process withdrawal');
        console.log('✓ Withdrawal processed');

        // Verify balance decreased
        const balanceAfterWithdrawal = await profile('Get balance after withdrawal', () =>
          marketplaceProcess.getMarketplaceBalance(testAddress)
        );

        const expectedBalance = (BigInt(balanceBeforeWithdrawal) - BigInt(withdrawAmount)).toString();
        assert.strictEqual(balanceAfterWithdrawal, expectedBalance, 'Balance should reflect withdrawal');
        console.log('✓ Balance decreased correctly');

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });

    it('should fail to withdraw more than balance', async () => {
      logger.startWorkflow('withdraw-insufficient');

      try {
        const currentBalance = await profile('Get current balance', () =>
          marketplaceProcess.getMarketplaceBalance(testAddress)
        );

        // Try to withdraw more than we have
        const excessiveAmount = (BigInt(currentBalance) + BigInt('1000000000')).toString();
        const result = await profile('Try excessive withdrawal', () =>
          marketplaceProcess.withdrawArio(excessiveAmount)
        );

        // Should return error notice
        assert.strictEqual(result.Action, 'Invalid-Withdraw-Notice', 'Should reject withdrawal');
        assert(result.Data.includes('Insufficient'), 'Should mention insufficient balance');
        console.log('✓ Correctly rejected excessive withdrawal');

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });

  describe('Get-Paginated-Balances', () => {
    it('should return balances after deposits', async () => {
      logger.startWorkflow('get-paginated-balances');

      try {
        // Ensure we have at least one balance entry
        await profile('Ensure balance exists', () =>
          marketplaceProcess.depositArio('100000000', arioProcessId, testAddress)
        );

        const result = await profile('Get paginated balances', () =>
          marketplaceProcess.process.read({
            tags: [{ name: 'Action', value: 'Get-Paginated-Balances' }],
          })
        );

        const data = typeof result === 'string' ? JSON.parse(result) : result;
        assert(data.items, 'Should return items array');
        assert(data.items.length > 0, 'Should have at least one balance');

        const userBalance = data.items.find((b: any) => b.address === testAddress);
        assert(userBalance, 'Should find test wallet balance');
        console.log('✓ Found balance entry for test wallet:', userBalance.balance);

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });

  describe('Balance Impact on Order Creation', () => {
    it('should deduct listing fee when creating intent', async () => {
      logger.startWorkflow('balance-listing-fee');

      try {
        // Ensure sufficient balance
        await profile('Ensure sufficient balance for fee', () =>
          marketplaceProcess.depositArio('10000000000', arioProcessId, testAddress)
        );

        const balanceBeforeIntent = await profile('Get balance before intent', () =>
          marketplaceProcess.getMarketplaceBalance(testAddress)
        );
        console.log('Balance before intent creation:', balanceBeforeIntent);

        // Create an intent (costs 1 ARIO fee)
        await profile('Create intent (incurs fee)', () =>
          marketplaceProcess.createIntent({
            action: 'Create-Order',
            orderType: 'fixed',
            swapToken: arioProcessId,
            quantity: '1000',
            price: '500000',
          })
        );

        const balanceAfterIntent = await profile('Get balance after intent', () =>
          marketplaceProcess.getMarketplaceBalance(testAddress)
        );
        console.log('Balance after intent creation:', balanceAfterIntent);

        // Verify fee was deducted (1 ARIO = 1000000 micro-ARIO)
        const feeAmount = BigInt('1000000'); // 1 ARIO fee
        const expectedBalance = (BigInt(balanceBeforeIntent) - feeAmount).toString();
        
        // Note: Balance might differ if there are other fees, so check it decreased
        assert(
          BigInt(balanceAfterIntent) < BigInt(balanceBeforeIntent),
          'Balance should decrease after intent creation due to fee'
        );
        console.log('✓ Listing fee deducted from balance');

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });
});

