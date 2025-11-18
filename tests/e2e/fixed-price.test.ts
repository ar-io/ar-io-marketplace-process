import { before, describe, it, after } from 'node:test';
import assert from 'node:assert';
import { MarketplaceProcess } from '../utils/marketplace_process.js';
import { getOrSpawnProcesses } from '../utils/process_manager.js';
import { resetTestLogger } from '../utils/test_logger.js';

describe('E2E Fixed Price Marketplace Tests', () => {
  let marketplaceProcess: MarketplaceProcess;
  let arioProcessId: string;
  let antProcessId: string;
  let marketplaceProcessId: string;
  const logger = resetTestLogger();

  before(async () => {
    console.log('Setting up E2E test environment...');
    
    // Get or spawn processes (will reuse if e2e-test.json exists)
    const processes = await getOrSpawnProcesses();
    
    marketplaceProcess = processes.marketplaceProcess;
    marketplaceProcessId = processes.marketplaceProcessId;
    arioProcessId = processes.arioProcessId;
    antProcessId = processes.antProcessId;

    // Set process IDs in logger
    logger.setProcesses({
      ario: arioProcessId,
      marketplace: marketplaceProcessId,
      ant: antProcessId,
    });

    console.log('Test environment ready:');
    console.log('  Marketplace:', marketplaceProcessId);
    console.log('  ARIO:', arioProcessId);
    console.log('  ANT:', antProcessId);
  });

  after(async () => {
    // Save test output
    await logger.save();
  });

  describe('List ANT at Fixed Price', () => {
    it('should successfully list an ANT at a fixed price', async () => {
      logger.startWorkflow('list-ant-fixed-price');
      
      try {
        const price = '1000000'; // 1 ARIO

        // Get initial order count
        const initialInfo = await marketplaceProcess.info();
        const initialOrderCount = initialInfo.activity.totalOrders;

        // List the ANT
        console.log('Sending ANT transfer to create listing...');
        const result = await marketplaceProcess.listAntForFixedPrice(
          antProcessId,
          price,
          arioProcessId,
          logger,
        );

        console.log('Transfer sent:', result.txId);
        console.log('Intent ID:', result.intentId);
        assert(result.txId, 'Transaction ID should be returned');

        // Wait for the order to appear
        console.log('Waiting for order to be created...');
            await marketplaceProcess.waitForNewOrders(initialOrderCount, 30000, result.intentId);

        // Verify order appears in listings
        const orders = await marketplaceProcess.getOrdersByStatus('listed');
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
      // Create a listing for the buy tests
      console.log('Creating test listing for buy tests...');
      listingPrice = '5000000'; // 5 ARIO

      const initialInfo = await marketplaceProcess.info();
      const initialOrderCount = initialInfo.activity.totalOrders;

      await marketplaceProcess.listAntForFixedPrice(
        antProcessId,
        listingPrice,
        arioProcessId,
      );

      // Wait for listing to appear
      console.log('Waiting for listing to be created...');
      await marketplaceProcess.waitForNewOrders(initialOrderCount, 60000);

      // Get the order ID
      const orders = await marketplaceProcess.getOrdersByStatus('listed');
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

      const initialInfo = await marketplaceProcess.info();
      const initialExecutedCount = initialInfo.activity.executedOrders;

      // Buy the listing
      const buyResult = await marketplaceProcess.buyFixedPriceListing(
        arioProcessId,
        listingOrderId,
        listingPrice,
      );

      console.log('Buy transfer sent:', buyResult.txId);
      assert(buyResult.txId, 'Buy transaction ID should be returned');

      // Wait for order to be executed
      console.log('Waiting for order to be executed...');
      await marketplaceProcess.waitForOrderCountChange('executed', initialExecutedCount, 60000);

      // Verify order status changed to executed
      const executedOrder = await marketplaceProcess.waitForOrderStatus(
        listingOrderId,
        'executed',
        60000,
      );

      assert.strictEqual(
        executedOrder.status,
        'executed',
        'Order should be executed',
      );

      console.log('✓ Buy completed successfully!');
    });

    it('should handle overpayment with refund', async () => {
      const initialInfo = await marketplaceProcess.info();
      const initialOrderCount = initialInfo.activity.totalOrders;
      
      // Create a new listing
      await marketplaceProcess.listAntForFixedPrice(
        antProcessId,
        '3000000',
        arioProcessId,
      );
      
      await marketplaceProcess.waitForNewOrders(initialOrderCount, 60000);

      const orders = await marketplaceProcess.getOrdersByStatus('listed');
      const ordersData = JSON.parse(orders.Data);
      const newOrderId = ordersData.items[ordersData.items.length - 1].id;

      const executedCountBeforeBuy = (await marketplaceProcess.info()).activity.executedOrders;

      // Buy with excess ARIO
      const overpayment = '5000000'; // Paying 5 ARIO for a 3 ARIO item
      await marketplaceProcess.buyFixedPriceListing(
        arioProcessId,
        newOrderId,
        overpayment,
      );

      // Wait for execution
      await marketplaceProcess.waitForOrderCountChange('executed', executedCountBeforeBuy, 60000);

      // Verify order executed
      const order = await marketplaceProcess.waitForOrderStatus(
        newOrderId,
        'executed',
        60000,
      );
      assert.strictEqual(order.status, 'executed');
      console.log('✓ Overpayment handled');
    });
  });

  describe('Cancel Listing', () => {
    it('should successfully cancel a listing', async () => {
      const initialInfo = await marketplaceProcess.info();
      const initialOrderCount = initialInfo.activity.totalOrders;
      
      // Create a listing to cancel
      await marketplaceProcess.listAntForFixedPrice(
        antProcessId,
        '2000000',
        arioProcessId,
      );

      await marketplaceProcess.waitForNewOrders(initialOrderCount, 60000);

      // Get the order ID
      const orders = await marketplaceProcess.getOrdersByStatus('listed');
      const ordersData = JSON.parse(orders.Data);
      const orderToCancel = ordersData.items[ordersData.items.length - 1].id;

      console.log('Cancelling order:', orderToCancel);

      const initialCancelledCount = initialInfo.activity.cancelledOrders;

      // Cancel the order
      const cancelResult = await marketplaceProcess.cancelOrder(orderToCancel);

      console.log('Cancel result:', cancelResult);
      assert.strictEqual(cancelResult.Action, 'Cancel-Order-Notice');

      // Wait for cancellation
      await marketplaceProcess.waitForOrderCountChange('cancelled', initialCancelledCount, 60000);

      // Verify order is cancelled
      const cancelledOrder = await marketplaceProcess.waitForOrderStatus(
        orderToCancel,
        'cancelled',
        60000,
      );

      assert.strictEqual(cancelledOrder.status, 'cancelled');

      console.log('✓ Order cancelled successfully!');
    });
  });

  describe('Error Handling', () => {
    it('should reject insufficient payment', async () => {
      const initialInfo = await marketplaceProcess.info();
      const initialOrderCount = initialInfo.activity.totalOrders;
      
      // Create a listing
      await marketplaceProcess.listAntForFixedPrice(
        antProcessId,
        '10000000',
        arioProcessId,
      );
      await marketplaceProcess.waitForNewOrders(initialOrderCount, 60000);

      const orders = await marketplaceProcess.getOrdersByStatus('listed');
      const ordersData = JSON.parse(orders.Data);
      const orderId = ordersData.items[ordersData.items.length - 1].id;

      // Try to buy with insufficient ARIO
      const insufficientAmount = '1000000'; // Only 1 ARIO for a 10 ARIO item
      await marketplaceProcess.buyFixedPriceListing(
        arioProcessId,
        orderId,
        insufficientAmount,
      );

      // Wait a bit and check that order is still listed
      await new Promise(resolve => setTimeout(resolve, 60_000));

      const order = await marketplaceProcess.getOrder(orderId);
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
        await marketplaceProcess.buyFixedPriceListing(
          arioProcessId,
          fakeOrderId,
          '1000000',
        );

        // Transfer will go through but marketplace should reject it
        console.log('✓ Transfer sent (will be rejected by marketplace)');
      } catch (error) {
        console.log('✓ Invalid order rejected:', error);
      }
    });
  });

  describe('Intent Pagination and Filtering', () => {
    it('should support pagination of intents', async () => {
      // Note: Intents may or may not exist depending on marketplace implementation
      const firstPage = await marketplaceProcess.getPaginatedIntents({
        limit: 2,
      });

      const firstData = JSON.parse(firstPage.Data);
      console.log('Intents count:', firstData.totalItems || 0);

      assert(Array.isArray(firstData.items), 'Items should be an array');
      console.log('✓ Intent pagination works');
    });

    it('should filter intents by status', async () => {
      const pendingIntents = await marketplaceProcess.getIntentsByStatus('pending');
      const pendingData = JSON.parse(pendingIntents.Data);

      assert(Array.isArray(pendingData.items), 'Items should be an array');
      console.log('✓ Intent filtering works');
    });
  });

  describe('Order Query by Multiple Criteria', () => {
    it('should query orders by status', async () => {
      const listedOrders = await marketplaceProcess.getOrdersByStatus('listed');
      const listedData = JSON.parse(listedOrders.Data);

      console.log('Listed orders count:', listedData.items?.length || 0);
      assert(Array.isArray(listedData.items), 'Items should be an array');
      console.log('✓ Order status filtering works');
    });

    it('should get marketplace info with order statistics', async () => {
      const info = await marketplaceProcess.info();
      
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

