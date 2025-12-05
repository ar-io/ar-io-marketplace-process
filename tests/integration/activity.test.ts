import assert from 'node:assert';
import { before, beforeEach, describe, it } from 'node:test';
import { AOProcess } from '@ar.io/sdk';
import Arweave from 'arweave';
import {
  BUNDLED_MARKETPLACE_SOURCE_CODE,
  TEST_SIGNER,
  TEST_WALLET,
} from '../utils/constants.js';
import { LocalAO, createLocalProcess } from '../utils/local_ao.js';
import { MarketplaceProcess } from '../utils/marketplace_process.js';

describe('Activity Tracking', () => {
  let marketplaceProcess: MarketplaceProcess;
  let ao_mock: LocalAO;

  before(async () => {
    const process = await createLocalProcess({
      processId: 'my-marketplace-process-'.padEnd(43, '1'),
      lua: BUNDLED_MARKETPLACE_SOURCE_CODE,
    });
    ao_mock = process.ao as any as LocalAO;
    const address = await Arweave.init({}).wallets.jwkToAddress(TEST_WALLET);
    marketplaceProcess = new MarketplaceProcess({
      process: new AOProcess({ ao: process.ao, processId: process.processId }),
      signer: TEST_SIGNER,
      walletAddress: address,
    });
  });

  beforeEach(async () => {
    await ao_mock.reset();
  });

  describe('Get-Orders (Listed)', () => {
    it('should return empty list when no orders exist', async () => {
      const result = await marketplaceProcess.getOrders({ status: 'listed' });

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Get-Orders-Notice');
      const data = JSON.parse(result.Data);
      assert(Array.isArray(data.items), 'Items should be an array');
      assert.strictEqual(data.items.length, 0, 'Should have no orders');
    });

    it('should support pagination', async () => {
      const result = await marketplaceProcess.getOrders({
        status: 'listed',
        limit: 10,
      });

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Get-Orders-Notice');
      const data = JSON.parse(result.Data);
      assert.strictEqual(data.limit, 10);
    });

    it('should support filtering', async () => {
      const result = await marketplaceProcess.getOrders({
        status: 'listed',
        filters: { Status: 'active' },
      });

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Get-Orders-Notice');
    });
  });

  describe('Get-Orders (Completed)', () => {
    it('should return empty list when no completed orders exist', async () => {
      const result = await marketplaceProcess.getOrders({
        status: 'completed',
      });

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Get-Orders-Notice');
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

      assert(result, 'Result should be defined');
      const data = JSON.parse(result.Data);
      assert.strictEqual(data.limit, 5);
      assert.strictEqual(data.sortBy, 'CreatedAt');
      assert.strictEqual(data.sortOrder, 'desc');
    });
  });

  describe('Get-Order', () => {
    it('should return Invalid-Get-Order-Notice for non-existent order', async () => {
      const result = await marketplaceProcess.getOrder('non-existent-order-id');

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Invalid-Get-Order-Notice');
      assert(result.Tags?.Error, 'Should have Error tag');
    });

    it('should handle missing Id parameter', async () => {
      try {
        await marketplaceProcess.process.read({
          tags: [{ name: 'Action', value: 'Get-Order' }],
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

  describe('Info (Activity Counts)', () => {
    it('should return counts of all activity via info handler', async () => {
      const info = await marketplaceProcess.info();

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
