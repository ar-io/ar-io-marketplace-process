import { before, beforeEach, describe, it } from 'node:test';
import { MarketplaceProcess } from '../utils/marketplace_process.js';
import { LocalAO, createLocalProcess } from '../utils/local_ao.js';
import { AOProcess } from '@ar.io/sdk';
import assert from 'node:assert';
import { BUNDLED_MARKETPLACE_SOURCE_CODE } from '../utils/constants.js';

describe('Activity Tracking', () => {
  let marketplaceProcess: MarketplaceProcess;
  let ao_mock: LocalAO;

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
    await ao_mock.reset();
  });

  describe('Get-Listed-Orders', () => {
    it('should return empty list when no orders exist', async () => {
      const result = await marketplaceProcess.getListedOrders();

      console.dir({ emptyListedOrders: result }, { depth: null });

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Read-Success');
      const data = JSON.parse(result.Data);
      assert(Array.isArray(data.items), 'Items should be an array');
      assert.strictEqual(data.items.length, 0, 'Should have no orders');
    });

    it('should support pagination', async () => {
      const result = await marketplaceProcess.getListedOrders({ limit: 10 });

      console.dir({ paginatedListedOrders: result }, { depth: null });

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Read-Success');
      const data = JSON.parse(result.Data);
      assert.strictEqual(data.limit, 10);
    });

    it('should support filtering', async () => {
      const result = await marketplaceProcess.getListedOrders({
        filters: { Status: 'active' },
      });

      console.dir({ filteredListedOrders: result }, { depth: null });

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Read-Success');
    });
  });

  describe('Get-Completed-Orders', () => {
    it('should return empty list when no completed orders exist', async () => {
      const result = await marketplaceProcess.getCompletedOrders();

      console.dir({ emptyCompletedOrders: result }, { depth: null });

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Read-Success');
      const data = JSON.parse(result.Data);
      assert(Array.isArray(data.items), 'Items should be an array');
      assert.strictEqual(
        data.items.length,
        0,
        'Should have no completed orders',
      );
    });

    it('should support pagination and sorting', async () => {
      const result = await marketplaceProcess.getCompletedOrders({
        limit: 5,
        sortBy: 'CreatedAt',
        sortOrder: 'desc',
      });

      console.dir({ paginatedCompletedOrders: result }, { depth: null });

      assert(result, 'Result should be defined');
      const data = JSON.parse(result.Data);
      assert.strictEqual(data.limit, 5);
      assert.strictEqual(data.sortBy, 'CreatedAt');
      assert.strictEqual(data.sortOrder, 'desc');
    });
  });

  describe('Get-Order-By-Id', () => {
    it('should return Order-Not-Found for non-existent order', async () => {
      const result = await marketplaceProcess.getOrderById(
        'non-existent-order-id',
      );

      console.dir({ nonExistentOrder: result }, { depth: null });

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Order-Not-Found');
    });

    it('should handle missing OrderId parameter', async () => {
      const result = (await marketplaceProcess.process.read({
        tags: [{ name: 'Action', value: 'Get-Order-By-Id' }],
      })) as any;

      console.dir({ missingOrderId: result }, { depth: null });

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Input-Error');
    });
  });

  describe('Get-Order-Counts-By-Address', () => {
    it('should return zero counts for address with no orders', async () => {
      const testAddress = 'test-address-'.padEnd(43, '0');
      const result =
        await marketplaceProcess.getOrderCountsByAddress(testAddress);

      console.dir({ zeroOrderCounts: result }, { depth: null });

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Read-Success');
      const data = JSON.parse(result.Data);
      assert(data, 'Data should be defined');
    });
  });

  describe('Get-Volume', () => {
    it('should return zero volume when no trades have occurred', async () => {
      const result = (await marketplaceProcess.getVolume()) as any;

      console.dir({ volume: result }, { depth: null });

      assert(result, 'Result should be defined');
      // Volume handler sends a notice directly
      assert(
        result.Action === 'Volume-Notice' || result.Action === 'Read-Success',
      );
    });
  });

  describe('Get-Most-Traded-Tokens', () => {
    it('should return empty list when no trades exist', async () => {
      const result = await marketplaceProcess.getMostTradedTokens();

      console.dir({ mostTradedTokens: result }, { depth: null });

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Most-Traded-Tokens-Result');
      const data = JSON.parse(result.Data);
      assert(Array.isArray(data), 'Data should be an array');
      assert.strictEqual(data.length, 0, 'Should have no tokens');
    });

    it('should support custom count parameter', async () => {
      const result = await marketplaceProcess.getMostTradedTokens(5);

      console.dir({ topFiveTokens: result }, { depth: null });

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Most-Traded-Tokens-Result');
    });
  });

  describe('Get-Activity-Lengths', () => {
    it('should return counts of all activity arrays', async () => {
      const result = await marketplaceProcess.getActivityLengths();

      console.dir({ activityLengths: result }, { depth: null });

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Read-Success');
      const data = JSON.parse(result.Data);
      assert(
        typeof data.ListedOrders === 'number',
        'ListedOrders should be a number',
      );
      assert(
        typeof data.ExecutedOrders === 'number',
        'ExecutedOrders should be a number',
      );
      assert(
        typeof data.CancelledOrders === 'number',
        'CancelledOrders should be a number',
      );
    });
  });
});
