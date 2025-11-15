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

  describe('Get-Orders (Listed)', () => {
    it('should return empty list when no orders exist', async () => {
      const result = await marketplaceProcess.getOrders({ status: 'listed' });

      console.dir({ emptyListedOrders: result }, { depth: null });

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Read-Success');
      const data = JSON.parse(result.Data);
      assert(Array.isArray(data.items), 'Items should be an array');
      assert.strictEqual(data.items.length, 0, 'Should have no orders');
    });

    it('should support pagination', async () => {
      const result = await marketplaceProcess.getOrders({
        status: 'listed',
        limit: 10,
      });

      console.dir({ paginatedListedOrders: result }, { depth: null });

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Read-Success');
      const data = JSON.parse(result.Data);
      assert.strictEqual(data.limit, 10);
    });

    it('should support filtering', async () => {
      const result = await marketplaceProcess.getOrders({
        status: 'listed',
        filters: { Status: 'active' },
      });

      console.dir({ filteredListedOrders: result }, { depth: null });

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Read-Success');
    });
  });

  describe('Get-Orders (Completed)', () => {
    it('should return empty list when no completed orders exist', async () => {
      const result = await marketplaceProcess.getOrders({
        status: 'completed',
      });

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
      const result = await marketplaceProcess.getOrders({
        status: 'completed',
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

  describe('Get-Order', () => {
    it('should return Order-Not-Found for non-existent order', async () => {
      const result = await marketplaceProcess.getOrder('non-existent-order-id');

      console.dir({ nonExistentOrder: result }, { depth: null });

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Order-Not-Found');
    });

    it('should handle missing Id parameter', async () => {
      const result = (await marketplaceProcess.process.read({
        tags: [{ name: 'Action', value: 'Get-Order' }],
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

  describe('Info (Activity Counts)', () => {
    it('should return counts of all activity via info handler', async () => {
      const info = await marketplaceProcess.info();

      console.dir({ info }, { depth: null });

      assert(info, 'Info should be defined');
      assert(info.activity, 'Activity should be defined');
      assert(
        typeof info.activity.listedOrders === 'number',
        'listedOrders should be a number',
      );
      assert(
        typeof info.activity.executedOrders === 'number',
        'executedOrders should be a number',
      );
      assert(
        typeof info.activity.cancelledOrders === 'number',
        'cancelledOrders should be a number',
      );
      assert(
        typeof info.activity.totalOrders === 'number',
        'totalOrders should be a number',
      );
    });
  });
});
