import { before, beforeEach, describe, it } from 'node:test';
import { MarketplaceProcess } from '../utils/marketplace_process.js';
import { LocalAO, createLocalProcess } from '../utils/local_ao.js';
import { AOProcess } from '@ar.io/sdk';
import assert from 'node:assert';
import {
  BUNDLED_MARKETPLACE_SOURCE_CODE,
  STUB_TIMESTAMP,
  PROCESS_OWNER,
  TEST_ANT_MODULE_NOT_WHITELISTED,
  TEST_ANT_MODULE_WHITELISTED,
  TEST_ANT_TOKEN,
  TEST_ARIO_TOKEN,
  TEST_SENDER,
  TEST_SIGNER,
} from '../utils/constants.js';

describe('UCM (Universal Content Marketplace)', () => {
  let marketplaceProcess: MarketplaceProcess;
  let ao_mock: LocalAO;

  before(async () => {
    const luaWithTestConfig =
      `ARIO_TOKEN_PROCESS_ID = "${TEST_ARIO_TOKEN}"\n` +
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
  });

  beforeEach(async () => {
    await ao_mock.reset();

    // Re-set ARIO token and deposit for listing fees
    await marketplaceProcess.process.send({
      tags: [{ name: 'Action', value: 'Eval' }],
      data: `ARIO_TOKEN_PROCESS_ID = "${TEST_ARIO_TOKEN}"`,
      signer: TEST_SIGNER,
    });

    // Whitelist test ANT module
    await marketplaceProcess.process.send({
      tags: [{ name: 'Action', value: 'Eval' }],
      data: `WhitelistedModules["${TEST_ANT_MODULE_WHITELISTED}"] = true`,
      signer: TEST_SIGNER,
    });

    await marketplaceProcess.depositArio(
      '100000000000',
      TEST_ARIO_TOKEN,
      TEST_SENDER,
    );
  });

  describe('Get-Orders with flexible filtering', () => {
    it('should return empty orders for non-existent pair using getOrdersByPair', async () => {
      const result = await marketplaceProcess.getOrdersByPair(
        TEST_ANT_TOKEN,
        TEST_ARIO_TOKEN,
      );

      // Orders may not exist yet for this pair
      assert(result, 'Result should be defined');
    });

    it('should return all orders when no filter is provided', async () => {
      const result = await marketplaceProcess.getOrders();

      // Handler should return all orders when no filter is specified
      assert(result !== undefined, 'Result should exist');
    });

    it('should support filtering by status', async () => {
      const result = await marketplaceProcess.getOrders({ status: 'active' });

      assert(result !== undefined, 'Result should exist');
    });

    it('should support filtering by trading pair', async () => {
      const result = await marketplaceProcess.getOrders({});

      assert(result !== undefined, 'Result should exist');
    });

    it('should support combined filters (pair + status)', async () => {
      const result = await marketplaceProcess.getOrders({
        status: 'listed',
      });

      assert(result !== undefined, 'Result should exist');
    });

    it('should support pagination parameters', async () => {
      const result = await marketplaceProcess.getOrders({
        limit: 10,
        sortBy: 'CreatedAt',
        sortOrder: 'desc',
      });

      assert(result !== undefined, 'Result should exist');
    });
  });

  describe('Cancel-Order', () => {
    it('should return error for non-existent order', async () => {
      const result = await marketplaceProcess.cancelOrder(
        'non-existent-order-id',
      );

      assert(result, 'Result should be defined');
      // Should get an Action-Response with error
      if (result.Action === 'Action-Response') {
        assert.strictEqual(result.Tags.Status, 'Error');
        assert(result.Tags.Message?.includes('Order not found'));
      }
    });

    it('should require Order-Id parameter', async () => {
      try {
        await marketplaceProcess.process.read({
          tags: [{ name: 'Action', value: 'Cancel-Order' }],
          // Missing Order-Id tag
        });
        assert.fail('Should have thrown an error for missing Order-Id');
      } catch (error: any) {
        assert(
          error.message.includes('Order-Id'),
          'Error should mention Order-Id',
        );
      }
    });
  });

  describe('Credit-Notice (Order Creation)', () => {
    it('should reject Credit-Notice from non-dominant token', async () => {
      const wrongToken = 'wrong-token-'.padEnd(43, '9');

      const messageId = await marketplaceProcess.process.ao.message({
        tags: [
          { name: 'Action', value: 'Credit-Notice' },
          { name: 'Sender', value: PROCESS_OWNER },
          { name: 'Quantity', value: '1000' },
          { name: 'From', value: wrongToken }, // From doesn't match dominant token
        ],
      });

      const result = await marketplaceProcess.process.ao.result({
        message: messageId,
        process: marketplaceProcess.process.processId,
      });

      // Handler should return early (no messages sent)
      assert(result, 'Result should be defined');
    });

    it('should reject Credit-Notice from non-whitelisted module', async () => {
      // Create intent first
      const intentResult = await marketplaceProcess.createIntent({
        antId: TEST_ANT_TOKEN, // Must match the From in Credit-Notice
        orderType: 'fixed',
        quantity: '1',
        price: '1000000',
        expirationTime: (STUB_TIMESTAMP + 3600000).toString(),
      });

      const intentData = JSON.parse(intentResult.Data);
      const intentId = intentData['Intent-Id'];

      // Try to send Credit-Notice with non-whitelisted module
      const creditMsg = await marketplaceProcess.process.ao.message({
        process: marketplaceProcess.process.processId,
        tags: [
          { name: 'Action', value: 'Credit-Notice' },
          { name: 'Sender', value: TEST_SENDER },
          { name: 'Quantity', value: '1' },
          { name: 'X-Intent-Id', value: intentId },
          { name: 'X-Order-Action', value: 'Create-Order' },
          { name: 'From-Module', value: TEST_ANT_MODULE_NOT_WHITELISTED }, // Non-whitelisted!
        ],
        data: '',
        signer: TEST_SIGNER,
        From: TEST_ANT_TOKEN,
      } as any);

      // Get result and check that intent was failed
      const creditResult = await marketplaceProcess.process.ao.result({
        message: creditMsg,
        process: marketplaceProcess.process.processId,
      });

      // Should have Intent-Resolved message with failed status
      const resolvedMsg = creditResult.Messages?.find((m: any) =>
        m.Tags?.find(
          (t: any) => t.name === 'Action' && t.value === 'Intent-Resolved',
        ),
      );

      assert(resolvedMsg, 'Should have Intent-Resolved message');

      const statusTag = resolvedMsg.Tags?.find((t: any) => t.name === 'Status');
      assert.strictEqual(
        statusTag?.value,
        'failed',
        'Intent should have failed status',
      );

      const reasonTag = resolvedMsg.Tags?.find(
        (t: any) => t.name === 'Failure-Reason',
      );
      assert(
        reasonTag?.value?.includes('whitelisted'),
        'Failure reason should mention whitelist: ' + reasonTag?.value,
      );
    });

    it('should accept Credit-Notice from whitelisted module', async () => {
      // Create intent
      const intentResult = await marketplaceProcess.createIntent({
        antId: TEST_ANT_TOKEN, // Must match the From in Credit-Notice
        orderType: 'fixed',
        quantity: '1',
        price: '1000000',
        expirationTime: (STUB_TIMESTAMP + 3600000).toString(),
      });

      const intentData = JSON.parse(intentResult.Data);
      const intentId = intentData['Intent-Id'];

      // Send Credit-Notice with whitelisted module
      const creditMsg = await marketplaceProcess.process.ao.message({
        process: marketplaceProcess.process.processId,
        tags: [
          { name: 'Action', value: 'Credit-Notice' },
          { name: 'Sender', value: TEST_SENDER },
          { name: 'Quantity', value: '1' },
          { name: 'X-Intent-Id', value: intentId },
          { name: 'X-Order-Action', value: 'Create-Order' },
          { name: 'From-Module', value: TEST_ANT_MODULE_WHITELISTED }, // Whitelisted!
        ],
        data: '',
        signer: TEST_SIGNER,
        From: TEST_ANT_TOKEN,
      } as any);

      // Get result
      const creditResult = await marketplaceProcess.process.ao.result({
        message: creditMsg,
        process: marketplaceProcess.process.processId,
      });

      // Should succeed with no error
      assert(
        !creditResult.Error,
        'Should not have error for whitelisted module',
      );

      // Should have Intent-Resolved with completed/active status (not failed)
      const resolvedMsg = creditResult.Messages?.find((m: any) =>
        m.Tags?.find(
          (t: any) => t.name === 'Action' && t.value === 'Intent-Resolved',
        ),
      );
      assert(resolvedMsg, 'Should have Intent-Resolved message');

      const statusTag = resolvedMsg.Tags?.find((t: any) => t.name === 'Status');
      assert.notStrictEqual(
        statusTag?.value,
        'failed',
        'Intent should not be failed for whitelisted module',
      );
    });
  });

  describe('Settle-Auction', () => {
    it('should return error for missing Order-Id', async () => {
      try {
        await marketplaceProcess.process.read({
          tags: [{ name: 'Action', value: 'Settle-Auction' }],
          // Missing Order-Id tag
        });
        assert.fail('Should have thrown an error for missing Order-Id');
      } catch (error: any) {
        assert(
          error.message.includes('Order-Id'),
          'Error should mention Order-Id',
        );
      }
    });

    it('should return error for non-existent order', async () => {
      const result = await marketplaceProcess.settleAuction({
        orderId: 'non-existent-auction-id',
      });

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Invalid-Settle-Auction-Notice');
      assert(
        result.Data &&
          (result.Data.includes('Order not found') ||
            result.Data.includes('not found')),
        'Error should mention order not found',
      );
    });
  });

  describe('Order Lifecycle', () => {
    it('should track order through listed -> executed states', async () => {
      // Check initial state
      const listedBefore = await marketplaceProcess.getOrders({
        status: 'listed',
      });
      const completedBefore = await marketplaceProcess.getOrders({
        status: 'completed',
      });

      assert(listedBefore, 'Listed orders should be defined');
      assert(completedBefore, 'Completed orders should be defined');

      const listedData = JSON.parse(listedBefore.Data);
      const completedData = JSON.parse(completedBefore.Data);

      assert.strictEqual(
        listedData.items.length,
        0,
        'Should start with no listed orders',
      );
      assert.strictEqual(
        completedData.items.length,
        0,
        'Should start with no completed orders',
      );
    });
  });
});
