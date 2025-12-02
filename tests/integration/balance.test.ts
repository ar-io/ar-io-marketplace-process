import { before, beforeEach, describe, it } from 'node:test';
import { MarketplaceProcess } from '../utils/marketplace_process.js';
import { LocalAO, createLocalProcess } from '../utils/local_ao.js';
import { AOProcess } from '@ar.io/sdk';
import assert from 'node:assert';
import {
  BUNDLED_MARKETPLACE_SOURCE_CODE,
  TEST_ARIO_PROCESS,
  TEST_SENDER,
  TEST_SIGNER,
} from '../utils/constants.js';

describe('Balance Management', () => {
  let marketplaceProcess: MarketplaceProcess;
  let ao_mock: LocalAO;

  before(async () => {
    // Create marketplace process
    const luaWithTestConfig =
      `ARIO_TOKEN_PROCESS_ID = "${TEST_ARIO_PROCESS}"\n` +
      BUNDLED_MARKETPLACE_SOURCE_CODE;

    const process = await createLocalProcess({
      processId: 'my-marketplace-process-'.padEnd(43, '1'),
      lua: luaWithTestConfig,
    });
    ao_mock = process.ao as any as LocalAO;
    marketplaceProcess = new MarketplaceProcess({
      process: new AOProcess({ ao: process.ao, processId: process.processId }),
      signer: TEST_SIGNER,
    });

    // Note: We don't need a separate ARIO process for testing deposits
    // We'll simulate Credit-Notices directly
  });

  beforeEach(async () => {
    // Reset marketplace process before each test
    await ao_mock.reset();

    // Re-set ARIO token after reset
    await marketplaceProcess.process.send({
      tags: [{ name: 'Action', value: 'Eval' }],
      data: `ARIO_TOKEN_PROCESS_ID = "${TEST_ARIO_PROCESS}"`,
      signer: TEST_SIGNER,
    });
  });

  describe('Get-Balance', () => {
    it('should return zero balance for new address', async () => {
      const balance =
        await marketplaceProcess.getMarketplaceBalance(TEST_SENDER);
      assert.strictEqual(balance, '0', 'New address should have zero balance');
    });

    it('should return balance after deposit', async () => {
      // Deposit ARIO for TEST_SENDER
      await marketplaceProcess.depositArio(
        '5000000000',
        TEST_ARIO_PROCESS,
        TEST_SENDER,
      );

      // Check balance
      const balance =
        await marketplaceProcess.getMarketplaceBalance(TEST_SENDER);
      assert.strictEqual(
        balance,
        '5000000000',
        'Balance should match deposit amount',
      );
    });
  });

  describe('Deposit-ARIO (Credit-Notice)', () => {
    it('should accept ARIO deposits via Credit-Notice', async () => {
      const result = await marketplaceProcess.depositArio(
        '10000000000',
        TEST_ARIO_PROCESS,
        TEST_SENDER,
      );

      assert.strictEqual(
        result.Action,
        'Credit-Notice-Processed',
        'Should process deposit',
      );

      // Verify balance increased
      const balance =
        await marketplaceProcess.getMarketplaceBalance(TEST_SENDER);
      assert.strictEqual(
        balance,
        '10000000000',
        'Balance should reflect deposit',
      );
    });

    it('should handle multiple deposits', async () => {
      await marketplaceProcess.depositArio(
        '1000000000',
        TEST_ARIO_PROCESS,
        TEST_SENDER,
      );
      await marketplaceProcess.depositArio(
        '2000000000',
        TEST_ARIO_PROCESS,
        TEST_SENDER,
      );

      const balance =
        await marketplaceProcess.getMarketplaceBalance(TEST_SENDER);
      assert.strictEqual(
        balance,
        '3000000000',
        'Balance should be sum of deposits',
      );
    });
  });

  describe('Withdraw-Ario', () => {
    it('should withdraw ARIO from marketplace balance', async () => {
      // Deposit for the actual signer address (msg.From will be this when withdrawing)
      // In the test environment, msg.From is the signer's address
      // We need to deposit to whatever address will be used as msg.From in the withdrawal
      await marketplaceProcess.depositArio(
        '10000000000',
        TEST_ARIO_PROCESS,
        TEST_SENDER,
      );

      // Then withdraw
      const result = await marketplaceProcess.withdrawArio('5000000000');

      assert.strictEqual(
        result.Action,
        'Withdraw-Ario-Notice',
        'Should process withdrawal',
      );

      // Verify balance decreased
      const balance =
        await marketplaceProcess.getMarketplaceBalance(TEST_SENDER);
      assert.strictEqual(
        balance,
        '5000000000',
        'Balance should reflect withdrawal',
      );
    });

    it('should fail to withdraw more than balance', async () => {
      // Deposit only 1000
      await marketplaceProcess.depositArio(
        '1000000000',
        TEST_ARIO_PROCESS,
        TEST_SENDER,
      );

      // Try to withdraw 2000
      const result = await marketplaceProcess.withdrawArio('2000000000');

      // Should return error notice
      assert.strictEqual(
        result.Action,
        'Invalid-Withdraw-Notice',
        'Should reject withdrawal',
      );
      assert(
        result.Data.includes('Insufficient'),
        'Should mention insufficient balance',
      );
    });

    it('should fail to withdraw with zero balance', async () => {
      const result = await marketplaceProcess.withdrawArio('1000000000');

      assert.strictEqual(
        result.Action,
        'Invalid-Withdraw-Notice',
        'Should reject withdrawal',
      );
    });
  });

  describe('Get-Paginated-Balances', () => {
    it('should return empty list when no balances exist', async () => {
      const result = await marketplaceProcess.process.read({
        tags: [{ name: 'Action', value: 'Get-Paginated-Balances' }],
      });

      const data = JSON.parse(JSON.stringify(result));
      assert(data.items, 'Should return items array');
      assert.strictEqual(data.items.length, 0, 'Should have no balances');
    });

    it('should return balances after deposits', async () => {
      // Make a deposit
      await marketplaceProcess.depositArio(
        '5000000000',
        TEST_ARIO_PROCESS,
        TEST_SENDER,
      );

      const result = await marketplaceProcess.process.read({
        tags: [{ name: 'Action', value: 'Get-Paginated-Balances' }],
      });

      // Parse the result - process.read() returns the data directly, not wrapped in .Data
      const data = typeof result === 'string' ? JSON.parse(result) : result;
      assert(data.items, 'Should return items array');
      assert(data.items.length > 0, 'Should have at least one balance');

      const userBalance = data.items.find(
        (b: any) => b.address === TEST_SENDER,
      );
      assert(userBalance, 'Should find user balance');
      assert.strictEqual(
        userBalance.balance,
        '5000000000',
        'Balance should match deposit',
      );
    });
  });
});
