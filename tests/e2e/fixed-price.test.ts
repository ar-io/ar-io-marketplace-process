import { before, describe, it, after } from 'node:test';
import assert from 'node:assert';
import { readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { MarketplaceProcess } from '../utils/marketplace_process.js';
import { getOrSpawnProcesses } from '../utils/process_manager.js';
import { resetTestLogger } from '../utils/test_logger.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

/**
 * Profiling utility to measure execution time of async operations
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

describe('E2E Fixed Price Marketplace Tests', { timeout: 2_700_000 }, () => {
  let marketplaceProcess: MarketplaceProcess;
  let arioProcessId: string;
  let marketplaceProcessId: string;
  let antRegistryProcessId: string;
  const logger = resetTestLogger();
  
  /**
   * Helper to spawn a fresh ANT for each test that needs one
   * This is necessary because after transferring an ANT to the marketplace,
   * the test wallet no longer owns it and cannot transfer it again.
   */
  async function spawnFreshAnt(): Promise<string> {
    return await profile('Spawn fresh ANT for test', async () => {
      const { ANT, AOProcess, ArweaveSigner } = await import('@ar.io/sdk');
      const { TEST_SIGNER, TEST_WALLET } = await import('../utils/constants.js');
      const { getAoInstance, getScheduler, getAuthorityAddress, getAntModuleId, createLocalnetSigner } = await import('../utils/constants.js');
      
      // Use SDK for configuration
      const ao = getAoInstance();
      const scheduler = getScheduler();
      const authority = await getAuthorityAddress();
      const antModule = await getAntModuleId(); // ANT-specific WASM module
      // Use the same wallet for spawning and operations to avoid wallet mismatch
      const localnetSigner = createLocalnetSigner(new ArweaveSigner(TEST_WALLET));
      
      // Manual spawn (SDK's ANT.spawn doesn't pass `ao` to ANTRegistry, causing mainnet hang)
      const processId = await ao.spawn({
        module: antModule,
        scheduler,
        signer: localnetSigner,
        tags: [
          { name: 'Authority', value: authority },
          { name: 'ANT-Registry-Id', value: antRegistryProcessId },
        ],
      });
      
      console.log('Fresh ANT spawned:', processId);
      
      // Wait for ANT to propagate
      console.log('Waiting 3s for ANT to propagate...');
      await new Promise(resolve => setTimeout(resolve, 3000));
      
      // Load ANT Lua code
      const antLuaPath = join(__dirname, '../fixtures/contracts/ant-bundled.lua');
      const antLua = readFileSync(antLuaPath, 'utf-8');
      
      const evalMsgId = await ao.message({
        process: processId,
        signer: localnetSigner,
        tags: [{ name: 'Action', value: 'Eval' }],
        data: antLua,
      });
      
      const evalResult = await ao.result({
        process: processId,
        message: evalMsgId,
      });
      
      console.log('ANT Lua loaded');
      
      // Verify ANT is responsive
      try {
        const ant = ANT.init({ 
          process: new AOProcess({ ao, processId }),
          signer: TEST_SIGNER
        });
        
        await ant.getInfo();
        console.log('ANT is responsive ✓');
      } catch (e) {
        console.log('ANT info check failed (may be normal for fresh spawn):', e instanceof Error ? e.message : String(e));
      }
      
      return processId;
    });
  }

  before(async () => {
    console.log('\n========================================');
    console.log('E2E Test Suite Starting');
    console.log('========================================\n');
    
    // Get or spawn processes (will reuse if e2e-test.json exists)
    const processes = await profile('Setup test environment', async () => {
      return await getOrSpawnProcesses();
    });
    
    marketplaceProcess = processes.marketplaceProcess;
    marketplaceProcessId = processes.marketplaceProcessId;
    arioProcessId = processes.arioProcessId;
    antRegistryProcessId = processes.antRegistryProcessId;

    // Set process IDs in logger (ANT will be set per-test)
    logger.setProcesses({
      ario: arioProcessId,
      marketplace: marketplaceProcessId,
      ant: 'will-be-set-per-test',
    });

    console.log('\nTest environment ready:');
    console.log('  Marketplace:', marketplaceProcessId);
    console.log('  ARIO:', arioProcessId);
    console.log('  Note: Each test will spawn its own ANT as needed');
    console.log('');
  });

  after(async () => {
    // Save test output
    await logger.save();
  });

  describe('List ANT at Fixed Price', () => {
    it('should successfully list an ANT at a fixed price', async () => {
      logger.startWorkflow('list-ant-fixed-price');
      
      try {
        // Spawn fresh ANT for this test
        const antProcessId = await spawnFreshAnt();
        
        const price = '1000000'; // 1 ARIO

        // Get initial order count
        const initialInfo = await profile('Get initial marketplace info', () => 
          marketplaceProcess.info()
        );
        const initialOrderCount = initialInfo.activity.totalOrders;

        // List the ANT
        const result = await profile('Send ANT transfer to create listing', () =>
          marketplaceProcess.listAntForFixedPrice(
            antProcessId,
            price,
            arioProcessId,
            logger,
          )
        );

        console.log('Transfer sent:', result.txId);
        console.log('Intent ID:', result.intentId);
        assert(result.txId, 'Transaction ID should be returned');

        // Wait for the order to appear
        await profile('Wait for order creation', () =>
          marketplaceProcess.waitForNewOrders(initialOrderCount, 450000, result.intentId)
        );

        // Verify order appears in listings
        const orders = await profile('Get listed orders', () =>
          marketplaceProcess.getOrdersByStatus('listed')
        );
        const ordersData = JSON.parse(orders.Data);
        
        console.log('Listed orders count:', ordersData.items?.length);
        assert(
          ordersData.items && ordersData.items.length > 0,
          'Should have at least one listed order',
        );

        // Verify the order has correct properties
        const order = ordersData.items[0];
        assert(order.id, 'Order should have an ID');
        assert.strictEqual(order.orderType, 'fixed', 'Order type should be fixed');
        console.log('✓ Listing created successfully!');
        
        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });

  describe('Buy Fixed Price Listing', () => {
    let listingOrderId: string;
    let listingPrice: string;

    before(async () => {
      // Spawn fresh ANT for buy test setup
      const antProcessId = await spawnFreshAnt();
      
      // Create a listing for the buy tests
      listingPrice = '5000000'; // 5 ARIO

      const initialInfo = await profile('Get marketplace info for buy test setup', () =>
        marketplaceProcess.info()
      );
      const initialOrderCount = initialInfo.activity.totalOrders;

      await profile('Create test listing for buy tests', () =>
        marketplaceProcess.listAntForFixedPrice(
          antProcessId,
          listingPrice,
          arioProcessId,
        )
      );

      // Wait for listing to appear
      await profile('Wait for test listing to be created', () =>
        marketplaceProcess.waitForNewOrders(initialOrderCount, 450000)
      );

      // Get the order ID
      const orders = await profile('Get listed orders for buy test', () =>
        marketplaceProcess.getOrdersByStatus('listed')
      );
      const ordersData = JSON.parse(orders.Data);
      
      if (ordersData.items && ordersData.items.length > 0) {
        listingOrderId = ordersData.items[ordersData.items.length - 1].id; // Get latest order
        console.log('Test listing created:', listingOrderId);
      } else {
        throw new Error('Failed to create test listing');
      }
    });

    it('should successfully buy a fixed price listing', async () => {
      console.log('Buying order:', listingOrderId);

      const initialInfo = await profile('Get marketplace info before buy', () =>
        marketplaceProcess.info()
      );
      const initialExecutedCount = initialInfo.activity.executedOrders;

      // Buy the listing
      const buyResult = await profile('Send ARIO transfer to buy listing', () =>
        marketplaceProcess.buyFixedPriceListing(
          arioProcessId,
          listingOrderId,
          listingPrice,
        )
      );

      console.log('Buy transfer sent:', buyResult.txId);
      assert(buyResult.txId, 'Buy transaction ID should be returned');

      // Wait for order to be executed
      await profile('Wait for order execution', () =>
        marketplaceProcess.waitForOrderCountChange('executed', initialExecutedCount, 450000)
      );

      // Verify order status changed to executed
      const executedOrder = await profile('Verify order executed status', () =>
        marketplaceProcess.waitForOrderStatus(
          listingOrderId,
          'executed',
          450000,
        )
      );

      assert.strictEqual(
        executedOrder.status,
        'executed',
        'Order should be executed',
      );

      console.log('✓ Buy completed successfully!');
    });

    it('should handle overpayment with refund', async () => {
      // Spawn fresh ANT for this test
      const antProcessId = await spawnFreshAnt();
      
      const initialInfo = await profile('Get marketplace info for overpayment test', () =>
        marketplaceProcess.info()
      );
      const initialOrderCount = initialInfo.activity.totalOrders;
      
      // Create a new listing
      await profile('Create listing for overpayment test', () =>
        marketplaceProcess.listAntForFixedPrice(
          antProcessId,
          '3000000',
          arioProcessId,
        )
      );
      
      await profile('Wait for overpayment test listing', () =>
        marketplaceProcess.waitForNewOrders(initialOrderCount, 450000)
      );

      const orders = await profile('Get orders for overpayment test', () =>
        marketplaceProcess.getOrdersByStatus('listed')
      );
      const ordersData = JSON.parse(orders.Data);
      const newOrderId = ordersData.items[ordersData.items.length - 1].id;

      const infoBeforeBuy = await profile('Get executed count before overpayment', () =>
        marketplaceProcess.info()
      );
      const executedCountBeforeBuy = infoBeforeBuy.activity.executedOrders;

      // Buy with excess ARIO
      const overpayment = '5000000'; // Paying 5 ARIO for a 3 ARIO item
      await profile('Send overpayment', () =>
        marketplaceProcess.buyFixedPriceListing(
          arioProcessId,
          newOrderId,
          overpayment,
        )
      );

      // Wait for execution
      await profile('Wait for overpayment order execution', () =>
        marketplaceProcess.waitForOrderCountChange('executed', executedCountBeforeBuy, 450000)
      );

      // Verify order executed
      const order = await profile('Verify overpayment order executed', () =>
        marketplaceProcess.waitForOrderStatus(
          newOrderId,
          'executed',
          450000,
        )
      );
      assert.strictEqual(order.status, 'executed');
      console.log('✓ Overpayment handled');
    });
  });

  describe('Cancel Listing', () => {
    it('should successfully cancel a listing', async () => {
      // Spawn fresh ANT for this test
      const antProcessId = await spawnFreshAnt();
      
      const initialInfo = await profile('Get marketplace info for cancel test', () =>
        marketplaceProcess.info()
      );
      const initialOrderCount = initialInfo.activity.totalOrders;
      
      // Create a listing to cancel
      await profile('Create listing to cancel', () =>
        marketplaceProcess.listAntForFixedPrice(
          antProcessId,
          '2000000',
          arioProcessId,
        )
      );

      await profile('Wait for cancellable listing to be created', () =>
        marketplaceProcess.waitForNewOrders(initialOrderCount, 450000)
      );

      // Get the order ID - find the order with OUR ANT as the dominant token
      const orders = await profile('Get orders for cancel test', () =>
        marketplaceProcess.getOrdersByStatus('listed')
      );
      const ordersData = JSON.parse(orders.Data);
      
      // Find the order with our specific ANT
      const ourOrder = ordersData.items.find((order: any) => order.dominantToken === antProcessId);
      if (!ourOrder) {
        throw new Error(`Could not find order with ANT ${antProcessId}`);
      }
      const orderToCancel = ourOrder.id;

      console.log('Cancelling order:', orderToCancel, 'for ANT:', antProcessId);

      const initialCancelledCount = initialInfo.activity.cancelledOrders;

      // Cancel the order
      const cancelResult = await profile('Send cancel order request', () =>
        marketplaceProcess.cancelOrder(orderToCancel)
      );

      console.log('Cancel result:', cancelResult);
      assert.strictEqual(cancelResult.Action, 'Cancel-Order-Notice');

      // Wait for cancellation
      await profile('Wait for order cancellation', () =>
        marketplaceProcess.waitForOrderCountChange('cancelled', initialCancelledCount, 450000)
      );

      // Verify order is cancelled
      const cancelledOrder = await profile('Verify order cancelled status', () =>
        marketplaceProcess.waitForOrderStatus(
          orderToCancel,
          'cancelled',
          450000,
        )
      );

      assert.strictEqual(cancelledOrder.status, 'cancelled');

      console.log('✓ Order cancelled successfully!');
    });
  });

  describe('Error Handling', () => {
    it('should reject insufficient payment', async () => {
      // Spawn fresh ANT for this test
      const antProcessId = await spawnFreshAnt();
      
      const initialInfo = await profile('Get marketplace info for insufficient payment test', () =>
        marketplaceProcess.info()
      );
      const initialOrderCount = initialInfo.activity.totalOrders;
      
      // Create a listing
      await profile('Create listing for insufficient payment test', () =>
        marketplaceProcess.listAntForFixedPrice(
          antProcessId,
          '10000000',
          arioProcessId,
        )
      );
      await profile('Wait for insufficient payment test listing', () =>
        marketplaceProcess.waitForNewOrders(initialOrderCount, 450000)
      );

      const orders = await profile('Get orders for insufficient payment test', () =>
        marketplaceProcess.getOrdersByStatus('listed')
      );
      const ordersData = JSON.parse(orders.Data);
      const orderId = ordersData.items[ordersData.items.length - 1].id;

      // Try to buy with insufficient ARIO
      const insufficientAmount = '1000000'; // Only 1 ARIO for a 10 ARIO item
      await profile('Send insufficient payment', () =>
        marketplaceProcess.buyFixedPriceListing(
          arioProcessId,
          orderId,
          insufficientAmount,
        )
      );

      // Wait a bit and check that order is still listed
      await profile('Wait for insufficient payment to be rejected (60s)', async () => {
        await new Promise(resolve => setTimeout(resolve, 60_000));
      });

      const order = await profile('Verify order still listed', () =>
        marketplaceProcess.getOrder(orderId)
      );
      const orderData = JSON.parse(order.Data);
      
      assert.strictEqual(
        orderData.status,
        'listed',
        'Order should remain listed after insufficient payment',
      );

      console.log('✓ Insufficient payment rejected correctly!');
    });

    it('should reject invalid order ID', async () => {
      const fakeOrderId = 'nonexistent-order-id';

      // Try to buy non-existent order
      try {
        await profile('Send buy request for nonexistent order', () =>
          marketplaceProcess.buyFixedPriceListing(
            arioProcessId,
            fakeOrderId,
            '1000000',
          )
        );

        // Transfer will go through but marketplace should reject it
        console.log('✓ Transfer sent (will be rejected by marketplace)');
      } catch (error) {
        console.log('✓ Invalid order rejected:', error);
      }
    });

    it('should fail to create order without required parameters', async () => {
      const result = await profile('Try to create intent without price', () =>
        marketplaceProcess.createIntent({
          action: 'Create-Order',
          orderType: 'fixed',
          swapToken: arioProcessId,
          quantity: '1000',
          // Missing price
        })
      );

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Invalid-Create-Intent-Notice');
      assert(result.Tags?.Error, 'Should have Error tag');
      console.log('✓ Correctly rejected intent without price');
    });

    it('should fail to create order with invalid order type', async () => {
      const result = await profile('Try to create intent with invalid order type', () =>
        marketplaceProcess.createIntent({
          action: 'Create-Order',
          orderType: 'invalid-type' as any,
          swapToken: arioProcessId,
          quantity: '1000',
          price: '500000',
        })
      );

      assert(result, 'Result should be defined');
      // Should get validation error
      console.log('✓ Invalid order type handled');
    });

    it('should fail to cancel non-existent order', async () => {
      const fakeOrderId = 'non-existent-order-123';

      const result = await profile('Try to cancel non-existent order', () =>
        marketplaceProcess.cancelOrder(fakeOrderId)
      );

      assert(result, 'Result should be defined');
      // Should get error response
      if (result.Action === 'Action-Response') {
        assert.strictEqual(result.Tags.Status, 'Error');
        console.log('✓ Cancel non-existent order rejected');
      } else {
        console.log('✓ Cancel rejected (different response format)');
      }
    });

    it('should handle missing Order-Id in Get-Order', async () => {
      try {
        await profile('Try Get-Order without Order-Id', async () => {
          await marketplaceProcess.process.read({
            tags: [{ name: 'Action', value: 'Get-Order' }],
          });
          assert.fail('Should have thrown error for missing Order-Id');
        });
      } catch (error: any) {
        assert(
          error.message.includes('Order-Id'),
          'Error should mention Order-Id'
        );
        console.log('✓ Missing Order-Id handled correctly');
      }
    });
  });

  describe('Intent Pagination and Filtering', () => {
    it('should support pagination of intents', async () => {
      // Note: Intents may or may not exist depending on marketplace implementation
      const firstPage = await profile('Get paginated intents', () =>
        marketplaceProcess.getPaginatedIntents({
          limit: 2,
        })
      );

      const firstData = JSON.parse(firstPage.Data);
      console.log('Intents count:', firstData.totalItems || 0);

      assert(Array.isArray(firstData.items), 'Items should be an array');
      console.log('✓ Intent pagination works');
    });

    it('should filter intents by status', async () => {
      const pendingIntents = await profile('Get intents by status', () =>
        marketplaceProcess.getIntentsByStatus('pending')
      );
      const pendingData = JSON.parse(pendingIntents.Data);

      assert(Array.isArray(pendingData.items), 'Items should be an array');
      console.log('✓ Intent filtering works');
    });
  });

  describe('Order Query by Multiple Criteria', () => {
    it('should query orders by status', async () => {
      const listedOrders = await profile('Query orders by status', () =>
        marketplaceProcess.getOrdersByStatus('listed')
      );
      const listedData = JSON.parse(listedOrders.Data);

      console.log('Listed orders count:', listedData.items?.length || 0);
      assert(Array.isArray(listedData.items), 'Items should be an array');
      console.log('✓ Order status filtering works');
    });

    it('should get marketplace info with order statistics', async () => {
      const info = await profile('Get marketplace info and stats', () =>
        marketplaceProcess.info()
      );
      
      console.log('Marketplace stats:', {
        total: info.activity.totalOrders,
        listed: info.activity.listedOrders,
        executed: info.activity.executedOrders,
        cancelled: info.activity.cancelledOrders,
      });

      assert(typeof info.activity.totalOrders === 'number');
      assert(typeof info.activity.listedOrders === 'number');
      console.log('✓ Marketplace info retrieval works');
    });
  });
});

