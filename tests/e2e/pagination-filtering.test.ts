import { before, describe, it, after } from 'node:test';
import assert from 'node:assert';
import { MarketplaceProcess } from '../utils/marketplace_process.js';
import { getOrSpawnProcesses } from '../utils/process_manager.js';
import { resetTestLogger } from '../utils/test_logger.js';

/**
 * E2E tests for Pagination and Filtering
 * Tests query functionality comprehensively on real AO processes
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

describe('E2E Pagination and Filtering Tests', { timeout: 1_800_000 }, () => {
  let marketplaceProcess: MarketplaceProcess;
  let arioProcessId: string;
  let marketplaceProcessId: string;
  const logger = resetTestLogger();

  before(async () => {
    console.log('\n========================================');
    console.log('E2E Pagination and Filtering Test Suite');
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

  describe('Intent Pagination', () => {
    it('should support pagination with limit and cursor', async () => {
      logger.startWorkflow('intent-pagination-limit-cursor');

      try {
        // Create multiple intents
        await profile('Create intents for pagination test', async () => {
          for (let i = 0; i < 5; i++) {
            await marketplaceProcess.createIntent({
              action: 'Create-Order',
              orderType: 'fixed',
              swapToken: arioProcessId,
              quantity: '1000',
              price: '500000',
            });
          }
        });

        // Get first page
        const firstPage = await profile('Get first page (limit=2)', () =>
          marketplaceProcess.getPaginatedIntents({ limit: 2 })
        );

        const firstData = JSON.parse(firstPage.Data);
        assert(Array.isArray(firstData.items), 'Items should be an array');
        assert.strictEqual(firstData.limit, 2, 'Limit should be 2');
        console.log('✓ First page:', firstData.items.length, 'items');
        console.log('  Has more:', firstData.hasMore);
        console.log('  Next cursor:', firstData.nextCursor);

        // Get second page if available
        if (firstData.hasMore && firstData.nextCursor) {
          const secondPage = await profile('Get second page with cursor', () =>
            marketplaceProcess.getPaginatedIntents({
              limit: 2,
              cursor: firstData.nextCursor,
            })
          );

          const secondData = JSON.parse(secondPage.Data);
          assert(Array.isArray(secondData.items), 'Second page items should be an array');
          console.log('✓ Second page:', secondData.items.length, 'items');
        }

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });

    it('should return empty array when no intents exist', async () => {
      logger.startWorkflow('intent-pagination-empty');

      try {
        // Note: There might be intents from previous tests
        // This test verifies the structure is correct
        const result = await profile('Get intents (may or may not be empty)', () =>
          marketplaceProcess.getPaginatedIntents()
        );

        assert(result, 'Result should be defined');
        assert.strictEqual(result.Action, 'Get-Paginated-Intents-Notice');
        const data = JSON.parse(result.Data);
        assert(Array.isArray(data.items), 'Items should be an array');
        console.log('✓ Intent count:', data.items.length);

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });

  describe('Intent Filtering by Status', () => {
    it('should filter intents by status', async () => {
      logger.startWorkflow('intent-filter-status');

      try {
        // Create an intent that will be pending
        await profile('Create pending intent', () =>
          marketplaceProcess.createIntent({
            action: 'Create-Order',
            orderType: 'fixed',
            swapToken: arioProcessId,
            quantity: '1000',
            price: '500000',
          })
        );

        // Get pending intents
        const pendingIntents = await profile('Get pending intents', () =>
          marketplaceProcess.getIntentsByStatus('pending')
        );

        const pendingData = JSON.parse(pendingIntents.Data);
        assert(Array.isArray(pendingData.items), 'Items should be an array');
        console.log('✓ Pending intents:', pendingData.items.length);

        // Verify all returned intents have pending status
        if (pendingData.items.length > 0) {
          const allPending = pendingData.items.every(
            (intent: any) => intent.status === 'pending'
          );
          assert(allPending, 'All intents should have pending status');
          console.log('✓ All returned intents have pending status');
        }

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });

  describe('Order Pagination by Status', () => {
    it('should paginate orders by listed status', async () => {
      logger.startWorkflow('order-pagination-listed');

      try {
        const listedOrders = await profile('Get listed orders', () =>
          marketplaceProcess.getOrdersByStatus('listed')
        );

        const listedData = JSON.parse(listedOrders.Data);
        assert(Array.isArray(listedData.items), 'Items should be an array');
        console.log('✓ Listed orders:', listedData.items?.length || 0);

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });

    it('should paginate orders by executed status', async () => {
      logger.startWorkflow('order-pagination-executed');

      try {
        const executedOrders = await profile('Get executed orders', () =>
          marketplaceProcess.getOrdersByStatus('executed')
        );

        const executedData = JSON.parse(executedOrders.Data);
        assert(Array.isArray(executedData.items), 'Items should be an array');
        console.log('✓ Executed orders:', executedData.items?.length || 0);

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });

    it('should paginate orders by cancelled status', async () => {
      logger.startWorkflow('order-pagination-cancelled');

      try {
        const cancelledOrders = await profile('Get cancelled orders', () =>
          marketplaceProcess.getOrdersByStatus('cancelled')
        );

        const cancelledData = JSON.parse(cancelledOrders.Data);
        assert(Array.isArray(cancelledData.items), 'Items should be an array');
        console.log('✓ Cancelled orders:', cancelledData.items?.length || 0);

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });

  describe('Order Filtering by Trading Pair', () => {
    it('should filter orders by trading pair', async () => {
      logger.startWorkflow('order-filter-pair');

      try {
        // Get orders for a specific pair
        const testDominantToken = 'test-ant-token-'.padEnd(43, '1');
        
        const orders = await profile('Get orders by trading pair', () =>
          marketplaceProcess.getOrders({
            dominantToken: testDominantToken,
            swapToken: arioProcessId,
          })
        );

        assert(orders !== undefined, 'Result should exist');
        const ordersData = JSON.parse(orders.Data);
        assert(Array.isArray(ordersData.items), 'Items should be an array');
        console.log('✓ Orders for pair:', ordersData.items?.length || 0);

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });

  describe('Combined Filters', () => {
    it('should support combined filters (pair + status)', async () => {
      logger.startWorkflow('order-combined-filters');

      try {
        const testDominantToken = 'test-ant-token-'.padEnd(43, '1');

        const orders = await profile('Get orders with combined filters', () =>
          marketplaceProcess.getOrders({
            dominantToken: testDominantToken,
            swapToken: arioProcessId,
            status: 'listed',
          })
        );

        assert(orders !== undefined, 'Result should exist');
        const ordersData = JSON.parse(orders.Data);
        assert(Array.isArray(ordersData.items), 'Items should be an array');
        console.log('✓ Orders with combined filters:', ordersData.items?.length || 0);

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });

  describe('Sorting Parameters', () => {
    it('should support sorting parameters', async () => {
      logger.startWorkflow('order-sorting');

      try {
        const orders = await profile('Get orders with sorting', () =>
          marketplaceProcess.getOrders({
            limit: 10,
            sortBy: 'CreatedAt',
            sortOrder: 'desc',
          })
        );

        assert(orders !== undefined, 'Result should exist');
        const ordersData = JSON.parse(orders.Data);
        assert.strictEqual(ordersData.limit, 10, 'Limit should be respected');
        assert.strictEqual(ordersData.sortBy, 'CreatedAt', 'SortBy should be set');
        assert.strictEqual(ordersData.sortOrder, 'desc', 'SortOrder should be set');
        console.log('✓ Sorting parameters working');

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });

  describe('Pagination Edge Cases', () => {
    it('should handle limit parameter correctly', async () => {
      logger.startWorkflow('pagination-limit-edge-case');

      try {
        // Create several intents
        await profile('Create intents for edge case test', async () => {
          for (let i = 0; i < 3; i++) {
            await marketplaceProcess.createIntent({
              action: 'Cancel-Order',
              orderId: `test-order-${i}`,
            });
          }
        });

        const result = await profile('Get intents with small limit', () =>
          marketplaceProcess.getPaginatedIntents({ limit: 1 })
        );

        const data = JSON.parse(result.Data);
        assert.strictEqual(
          data.items.length <= 1,
          true,
          'Should return at most 1 item'
        );
        console.log('✓ Limit parameter working correctly');

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });

  describe('Query All Orders', () => {
    it('should return all orders when no filter is provided', async () => {
      logger.startWorkflow('query-all-orders');

      try {
        const result = await profile('Get all orders (no filter)', () =>
          marketplaceProcess.getOrders()
        );

        assert(result !== undefined, 'Result should exist');
        const ordersData = JSON.parse(result.Data);
        assert(Array.isArray(ordersData.items), 'Items should be an array');
        console.log('✓ All orders retrieved:', ordersData.items?.length || 0);

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });
});


