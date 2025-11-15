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

      console.dir({ createIntent: result }, { depth: null });

      assert(result, 'Create intent result should be defined');
      assert.strictEqual(result.Action, 'Intent-Created');
      assert(result.Tags['Intent-Id'], 'Intent-Id should be returned');
      assert.strictEqual(result.Tags.Status, 'Success');
    });

    it('should fail to create intent without required X-Intent-Action', async () => {
      const { result } = (await marketplaceProcess.process.send({
        tags: [{ name: 'Action', value: 'Create-Intent' }],
        signer: TEST_SIGNER,
      })) as any;

      console.dir({ missingAction: result }, { depth: null });

      assert(result, 'Result should be defined');
      const errorMessage = result.Messages.find((m: any) =>
        m.Tags.find(
          (t: any) =>
            t.name === 'Action' && t.value === 'Invalid-Intent-Notice',
        ),
      );
      assert(errorMessage, 'Should return Invalid-Intent-Notice');
    });

    it('should fail to create intent without required parameters for Create-Order', async () => {
      const result = await marketplaceProcess.createIntent({
        action: 'Create-Order',
        // Missing orderType, swapToken, quantity
      });

      console.dir({ missingParams: result }, { depth: null });

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Invalid-Intent-Notice');
      assert.strictEqual(result.Tags.Status, 'Error');
    });

    it('should create an intent for Cancel-Order action', async () => {
      const result = await marketplaceProcess.createIntent({
        action: 'Cancel-Order',
        orderId: 'test-order-123',
      });

      console.dir({ cancelIntent: result }, { depth: null });

      assert(result, 'Create intent result should be defined');
      assert.strictEqual(result.Action, 'Intent-Created');
      assert(result.Tags['Intent-Id'], 'Intent-Id should be returned');
    });

    it('should create an intent for Settle-Auction action', async () => {
      const result = await marketplaceProcess.createIntent({
        action: 'Settle-Auction',
        orderId: 'test-auction-456',
      });

      console.dir({ settleIntent: result }, { depth: null });

      assert(result, 'Create intent result should be defined');
      assert.strictEqual(result.Action, 'Intent-Created');
      assert(result.Tags['Intent-Id'], 'Intent-Id should be returned');
    });
  });

  describe('Get-Paginated-Intents', () => {
    it('should return empty list when no intents exist', async () => {
      const result = await marketplaceProcess.getPaginatedIntents();

      console.dir({ emptyIntents: result }, { depth: null });

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Read-Success');
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

      console.dir({ intentsWithData: result }, { depth: null });

      assert(result, 'Result should be defined');
      const data = JSON.parse(result.Data);
      assert.strictEqual(data.items.length, 1, 'Should have one intent');
      assert.strictEqual(data.items[0].Action, 'Create-Order');
      assert.strictEqual(data.items[0].Type, 'parent');
      assert.strictEqual(data.items[0].Status, 'pending');
    });

    it('should filter intents by Initiator', async () => {
      // Create intents
      await marketplaceProcess.createIntent({
        action: 'Create-Order',
        orderType: 'fixed',
        swapToken: 'test-swap-token-'.padEnd(43, '1'),
        quantity: '1000',
      });

      const result = await marketplaceProcess.getPaginatedIntents({
        filters: { Initiator: marketplaceProcess.process.processId },
      });

      console.dir({ filteredIntents: result }, { depth: null });

      assert(result, 'Result should be defined');
      const data = JSON.parse(result.Data);
      assert(data.items.length >= 1, 'Should have at least one intent');
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

      console.dir({ paginatedIntents: result }, { depth: null });

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

      const intentId = createResult.Tags['Intent-Id'];

      const result = await marketplaceProcess.getIntentById(intentId);

      console.dir({ intentById: result }, { depth: null });

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Read-Success');
      const data = JSON.parse(result.Data);
      assert.strictEqual(data.IntentId, intentId);
      assert.strictEqual(data.Action, 'Create-Order');
      assert.strictEqual(data.Type, 'parent');
    });

    it('should return error for non-existent intent', async () => {
      const result = await marketplaceProcess.getIntentById('non-existent-id');

      console.dir({ nonExistentIntent: result }, { depth: null });

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Intent-Not-Found');
    });

    it('should return Intent-Not-Found when Intent-Id is missing', async () => {
      const result = (await marketplaceProcess.process.read({
        tags: [{ name: 'Action', value: 'Get-Intent-By-Id' }],
      })) as any;

      console.dir({ missingIntentId: result }, { depth: null });

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Input-Error');
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

      console.dir({ intentStats: info.intents }, { depth: null });

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

      console.dir({ emptyStats: info.intents }, { depth: null });

      assert(info, 'Info should be defined');
      assert(info.intents, 'Intents should be defined');
      assert.strictEqual(info.intents.total, 0);
      assert.deepStrictEqual(info.intents.byStatus, {});
      assert.deepStrictEqual(info.intents.byType, {});
      assert.deepStrictEqual(info.intents.byAction, {});
    });
  });
});
