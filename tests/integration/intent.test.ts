import { before, beforeEach, describe, it } from 'node:test';
import { MarketplaceProcess } from '../utils/marketplace_process.js';
import { LocalAO, createLocalProcess } from '../utils/local_ao.js';
import { AOProcess } from '@ar.io/sdk';
import assert from 'node:assert';
import {
  BUNDLED_MARKETPLACE_SOURCE_CODE,
  TEST_SIGNER,
} from '../utils/constants.js';

describe('Intent Workflow Tracking', () => {
  let marketplaceProcess: MarketplaceProcess;
  let ao_mock: LocalAO;

  // create a new process and mock before the tests
  before(async () => {
    const process = await createLocalProcess({
      processId: 'my-marketplace-process-'.padEnd(43, '1'),
      lua: BUNDLED_MARKETPLACE_SOURCE_CODE,
    });
    ao_mock = process.ao as any as LocalAO;
    marketplaceProcess = new MarketplaceProcess({
      process: new AOProcess({ ao: process.ao, processId: process.processId }),
			signer: TEST_SIGNER,
    });
  });

  beforeEach(async () => {
    // clear the current memory and resultsCache of the mock before each new test
    await ao_mock.reset();
  });

  describe('Create-Intent', () => {
    it('should create an intent for Create-Order action', async () => {
      const result = await marketplaceProcess.createIntent({
        action: 'Create-Order',
        orderType: 'fixed',
        swapToken: 'test-swap-token-'.padEnd(43, '1'),
        quantity: '1000',
        price: '500',
      });

      assert(result, 'Create intent result should be defined');
      assert.strictEqual(result.Action, 'Create-Intent-Notice');
      const data = JSON.parse(result.Data);
      assert(data['Intent-Id'], 'Intent-Id should be returned');
    });

    it('should fail to create intent without required X-Intent-Action', async () => {
      try {
        await marketplaceProcess.process.send({
          tags: [{ name: 'Action', value: 'Create-Intent' }],
          signer: TEST_SIGNER,
        });
        assert.fail('Should have thrown an error for missing X-Intent-Action');
      } catch (error: any) {
        assert(
          error.message.includes('X-Intent-Action'),
          'Error should mention X-Intent-Action',
        );
      }
    });

    it('should fail to create intent without required parameters for Create-Order', async () => {
      const result = await marketplaceProcess.createIntent({
        action: 'Create-Order',
        // Missing orderType, swapToken, quantity
      });

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Invalid-Create-Intent-Notice');
      assert(result.Tags?.Error, 'Should have Error tag');
    });

    it('should create an intent for Cancel-Order action', async () => {
      const result = await marketplaceProcess.createIntent({
        action: 'Cancel-Order',
        orderId: 'test-order-123',
      });

      assert(result, 'Create intent result should be defined');
      assert.strictEqual(result.Action, 'Create-Intent-Notice');
      const data = JSON.parse(result.Data);
      assert(data['Intent-Id'], 'Intent-Id should be returned');
    });

    it('should create an intent for Settle-Auction action', async () => {
      const result = await marketplaceProcess.createIntent({
        action: 'Settle-Auction',
        orderId: 'test-auction-456',
      });

      assert(result, 'Create intent result should be defined');
      assert.strictEqual(result.Action, 'Create-Intent-Notice');
      const data = JSON.parse(result.Data);
      assert(data['Intent-Id'], 'Intent-Id should be returned');
    });
  });

  describe('Get-Paginated-Intents', () => {
    it('should return empty list when no intents exist', async () => {
      const result = await marketplaceProcess.getPaginatedIntents();

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Get-Paginated-Intents-Notice');
      const data = JSON.parse(result.Data);
      assert(Array.isArray(data.items), 'Items should be an array');
      assert.strictEqual(data.items.length, 0, 'Should have no intents');
    });

    it('should return created intents', async () => {
      // Create an intent first
      await marketplaceProcess.createIntent({
        action: 'Create-Order',
        orderType: 'fixed',
        swapToken: 'test-swap-token-'.padEnd(43, '1'),
        quantity: '1000',
      });

      const result = await marketplaceProcess.getPaginatedIntents();

      assert(result, 'Result should be defined');
      const data = JSON.parse(result.Data);
      assert.strictEqual(data.items.length, 1, 'Should have one intent');
      assert.strictEqual(data.items[0].action, 'Create-Order');
      assert.strictEqual(data.items[0].type, 'parent');
      assert.strictEqual(data.items[0].status, 'pending');
    });

    it('should support pagination with limit', async () => {
      // Create multiple intents
      await marketplaceProcess.createIntent({
        action: 'Create-Order',
        orderType: 'fixed',
        swapToken: 'test-swap-token-'.padEnd(43, '1'),
        quantity: '1000',
      });

      await marketplaceProcess.createIntent({
        action: 'Cancel-Order',
        orderId: 'test-order-123',
      });

      const result = await marketplaceProcess.getPaginatedIntents({
        limit: 1,
      });

      assert(result, 'Result should be defined');
      const data = JSON.parse(result.Data);
      assert.strictEqual(data.items.length, 1, 'Should return only 1 intent');
      assert.strictEqual(data.limit, 1);
      assert.strictEqual(data.hasMore, true);
      assert(data.nextCursor, 'Should have nextCursor');
    });
  });

  describe('Get-Intent-By-Id', () => {
    it('should return intent by ID', async () => {
      // Create an intent
      const createResult = await marketplaceProcess.createIntent({
        action: 'Create-Order',
        orderType: 'fixed',
        swapToken: 'test-swap-token-'.padEnd(43, '1'),
        quantity: '1000',
      });

      const createData = JSON.parse(createResult.Data);
      const intentId = createData['Intent-Id'];

      const result = await marketplaceProcess.getIntentById(intentId);

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Get-Intent-By-Id-Notice');
      const data = JSON.parse(result.Data);
      assert.strictEqual(data.intentId, intentId);
      assert.strictEqual(data.action, 'Create-Order');
      assert.strictEqual(data.type, 'parent');
    });

    it('should return error for non-existent intent', async () => {
      const result = await marketplaceProcess.getIntentById('non-existent-id');

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Invalid-Get-Intent-By-Id-Notice');
      assert(result.Tags?.Error, 'Should have Error tag');
    });

    it('should return error when Intent-Id is missing', async () => {
      try {
        await marketplaceProcess.process.read({
          tags: [{ name: 'Action', value: 'Get-Intent-By-Id' }],
        });
        assert.fail('Should have thrown an error for missing Intent-Id');
      } catch (error: any) {
        assert(
          error.message.includes('Intent-Id'),
          'Error should mention Intent-Id',
        );
      }
    });
  });

  describe('Info (Intent Stats)', () => {
    it('should return statistics about intents via info handler', async () => {
      // Create various intents
      await marketplaceProcess.createIntent({
        action: 'Create-Order',
        orderType: 'fixed',
        swapToken: 'test-swap-token-'.padEnd(43, '1'),
        quantity: '1000',
      });

      await marketplaceProcess.createIntent({
        action: 'Cancel-Order',
        orderId: 'test-order-123',
      });

      const info = await marketplaceProcess.info();

      assert(info, 'Info should be defined');
      assert(info.intents, 'Intents should be defined');
      assert.strictEqual(info.intents.total, 2, 'Should have 2 total intents');
      assert.strictEqual(
        info.intents.byStatus.pending,
        2,
        'Should have 2 pending intents',
      );
      assert.strictEqual(
        info.intents.byType.parent,
        2,
        'Should have 2 parent intents',
      );
      assert.strictEqual(info.intents.byAction['Create-Order'], 1);
      assert.strictEqual(info.intents.byAction['Cancel-Order'], 1);
    });

    it('should return zero stats when no intents exist via info handler', async () => {
      const info = await marketplaceProcess.info();

      assert(info, 'Info should be defined');
      assert(info.intents, 'Intents should be defined');
      assert.strictEqual(info.intents.total, 0);
      assert.deepStrictEqual(info.intents.byStatus, []);
      assert.deepStrictEqual(info.intents.byType, []);
      assert.deepStrictEqual(info.intents.byAction, []);
    });
  });
});
