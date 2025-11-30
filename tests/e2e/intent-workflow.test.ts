import { before, describe, it, after } from 'node:test';
import assert from 'node:assert';
import { MarketplaceProcess } from '../utils/marketplace_process.js';
import { getOrSpawnProcesses } from '../utils/process_manager.js';
import { resetTestLogger } from '../utils/test_logger.js';

/**
 * E2E tests for Intent Workflow
 * Tests the complete intent lifecycle on real AO processes
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

describe('E2E Intent Workflow Tests', { timeout: 1_800_000 }, () => {
  let marketplaceProcess: MarketplaceProcess;
  let arioProcessId: string;
  let marketplaceProcessId: string;
  const logger = resetTestLogger();

  before(async () => {
    console.log('\n========================================');
    console.log('E2E Intent Workflow Test Suite');
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
    console.log('');
  });

  after(async () => {
    await logger.save();
  });

  describe('Create-Intent for Create-Order Action', () => {
    it('should create an intent for fixed price order', async () => {
      logger.startWorkflow('create-intent-fixed-price');

      try {
        const result = await profile('Create intent for fixed price order', () =>
          marketplaceProcess.createIntent({
            action: 'Create-Order',
            orderType: 'fixed',
            swapToken: arioProcessId,
            quantity: '1000',
            price: '500000',
          })
        );

        assert(result, 'Create intent result should be defined');
        assert.strictEqual(result.Action, 'Create-Intent-Notice');
        const data = JSON.parse(result.Data);
        assert(data['Intent-Id'], 'Intent-Id should be returned');
        console.log('✓ Intent created:', data['Intent-Id']);

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });

    it('should fail to create intent without required X-Intent-Action', async () => {
      logger.startWorkflow('create-intent-missing-action');

      try {
        await profile('Try to create intent without action', async () => {
          try {
            await marketplaceProcess.process.send({
              tags: [{ name: 'Action', value: 'Create-Intent' }],
              signer: marketplaceProcess.signer,
            });
            assert.fail('Should have thrown an error for missing X-Intent-Action');
          } catch (error: any) {
            assert(
              error.message.includes('X-Intent-Action'),
              'Error should mention X-Intent-Action'
            );
            console.log('✓ Correctly rejected missing X-Intent-Action');
          }
        });

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });

    it('should fail to create intent without required parameters', async () => {
      logger.startWorkflow('create-intent-missing-params');

      try {
        const result = await profile('Create intent with missing parameters', () =>
          marketplaceProcess.createIntent({
            action: 'Create-Order',
            // Missing orderType, swapToken, quantity
          })
        );

        assert(result, 'Result should be defined');
        assert.strictEqual(result.Action, 'Invalid-Create-Intent-Notice');
        assert(result.Tags?.Error, 'Should have Error tag');
        console.log('✓ Correctly rejected intent with missing parameters');

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });

  describe('Create-Intent for Cancel-Order Action', () => {
    it('should create an intent for Cancel-Order', async () => {
      logger.startWorkflow('create-intent-cancel-order');

      try {
        const result = await profile('Create intent for Cancel-Order', () =>
          marketplaceProcess.createIntent({
            action: 'Cancel-Order',
            orderId: 'test-order-123',
          })
        );

        assert(result, 'Create intent result should be defined');
        assert.strictEqual(result.Action, 'Create-Intent-Notice');
        const data = JSON.parse(result.Data);
        assert(data['Intent-Id'], 'Intent-Id should be returned');
        console.log('✓ Cancel-Order intent created:', data['Intent-Id']);

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });

  describe('Create-Intent for Settle-Auction Action', () => {
    it('should create an intent for Settle-Auction', async () => {
      logger.startWorkflow('create-intent-settle-auction');

      try {
        const result = await profile('Create intent for Settle-Auction', () =>
          marketplaceProcess.createIntent({
            action: 'Settle-Auction',
            orderId: 'test-auction-456',
          })
        );

        assert(result, 'Create intent result should be defined');
        assert.strictEqual(result.Action, 'Create-Intent-Notice');
        const data = JSON.parse(result.Data);
        assert(data['Intent-Id'], 'Intent-Id should be returned');
        console.log('✓ Settle-Auction intent created:', data['Intent-Id']);

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });

  describe('Get-Paginated-Intents', () => {
    it('should return created intents', async () => {
      logger.startWorkflow('get-paginated-intents');

      try {
        // Create an intent first
        await profile('Create intent for pagination test', () =>
          marketplaceProcess.createIntent({
            action: 'Create-Order',
            orderType: 'fixed',
            swapToken: arioProcessId,
            quantity: '1000',
            price: '500000',
          })
        );

        const result = await profile('Get paginated intents', () =>
          marketplaceProcess.getPaginatedIntents()
        );

        assert(result, 'Result should be defined');
        assert.strictEqual(result.Action, 'Get-Paginated-Intents-Notice');
        const data = JSON.parse(result.Data);
        assert(Array.isArray(data.items), 'Items should be an array');
        assert(data.items.length > 0, 'Should have at least one intent');
        console.log('✓ Found', data.items.length, 'intents');

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });

    it('should support pagination with limit', async () => {
      logger.startWorkflow('intent-pagination-limit');

      try {
        // Create multiple intents
        await profile('Create first intent', () =>
          marketplaceProcess.createIntent({
            action: 'Create-Order',
            orderType: 'fixed',
            swapToken: arioProcessId,
            quantity: '1000',
            price: '500000',
          })
        );

        await profile('Create second intent', () =>
          marketplaceProcess.createIntent({
            action: 'Cancel-Order',
            orderId: 'test-order-123',
          })
        );

        const result = await profile('Get paginated intents with limit=1', () =>
          marketplaceProcess.getPaginatedIntents({ limit: 1 })
        );

        assert(result, 'Result should be defined');
        const data = JSON.parse(result.Data);
        assert.strictEqual(data.limit, 1, 'Limit should be 1');
        console.log('✓ Pagination limit working, hasMore:', data.hasMore);

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });

  describe('Get-Intent-By-Id', () => {
    it('should return intent by ID', async () => {
      logger.startWorkflow('get-intent-by-id');

      try {
        // Create an intent
        const createResult = await profile('Create intent to retrieve', () =>
          marketplaceProcess.createIntent({
            action: 'Create-Order',
            orderType: 'fixed',
            swapToken: arioProcessId,
            quantity: '1000',
            price: '500000',
          })
        );

        const createData = JSON.parse(createResult.Data);
        const intentId = createData['Intent-Id'];
        console.log('Created intent ID:', intentId);

        const result = await profile('Get intent by ID', () =>
          marketplaceProcess.getIntentById(intentId)
        );

        assert(result, 'Result should be defined');
        assert.strictEqual(result.Action, 'Get-Intent-By-Id-Notice');
        const data = JSON.parse(result.Data);
        assert.strictEqual(data.intentId, intentId);
        assert.strictEqual(data.action, 'Create-Order');
        assert.strictEqual(data.type, 'parent');
        console.log('✓ Retrieved intent, status:', data.status);

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });

    it('should return error for non-existent intent', async () => {
      logger.startWorkflow('get-nonexistent-intent');

      try {
        const result = await profile('Get non-existent intent', () =>
          marketplaceProcess.getIntentById('non-existent-id')
        );

        assert(result, 'Result should be defined');
        assert.strictEqual(result.Action, 'Invalid-Get-Intent-By-Id-Notice');
        assert(result.Tags?.Error, 'Should have Error tag');
        console.log('✓ Correctly returned error for non-existent intent');

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });

    it('should return error when Intent-Id is missing', async () => {
      logger.startWorkflow('get-intent-missing-id');

      try {
        await profile('Get intent without ID', async () => {
          try {
            await marketplaceProcess.process.read({
              tags: [{ name: 'Action', value: 'Get-Intent-By-Id' }],
            });
            assert.fail('Should have thrown an error for missing Intent-Id');
          } catch (error: any) {
            assert(
              error.message.includes('Intent-Id'),
              'Error should mention Intent-Id'
            );
            console.log('✓ Correctly rejected missing Intent-Id');
          }
        });

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });

  describe('Intent Statistics via Info Handler', () => {
    it('should return statistics about intents', async () => {
      logger.startWorkflow('intent-statistics');

      try {
        const info = await profile('Get marketplace info with intent stats', () =>
          marketplaceProcess.info()
        );

        assert(info, 'Info should be defined');
        assert(info.intents, 'Intents should be defined');
        assert(typeof info.intents.total === 'number', 'Total should be a number');
        console.log('Intent statistics:');
        console.log('  Total:', info.intents.total);
        console.log('  By Status:', info.intents.byStatus);
        console.log('  By Type:', info.intents.byType);
        console.log('  By Action:', info.intents.byAction);

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });
});


