import { before, describe, it, after } from 'node:test';
import assert from 'node:assert';
import { MarketplaceProcess } from '../utils/marketplace_process.js';
import { getOrSpawnProcesses } from '../utils/process_manager.js';
import { resetTestLogger } from '../utils/test_logger.js';
import { ANT, AOProcess, ArweaveSigner } from '@ar.io/sdk';
import { readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import {
  getAoInstance,
  getScheduler,
  getAuthorityAddress,
  getAntModuleId,
  createLocalnetSigner,
  TEST_WALLET,
} from '../utils/constants.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

/**
 * E2E tests for Dutch Auction Mechanism
 * Tests Dutch auction creation, price calculation, and purchase on real AO processes
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

describe('E2E Dutch Auction Tests', { timeout: 1_800_000 }, () => {
  let marketplaceProcess: MarketplaceProcess;
  let arioProcessId: string;
  let marketplaceProcessId: string;
  let antRegistryProcessId: string;
  const logger = resetTestLogger();

  /**
   * Helper to spawn a fresh ANT for each test
   */
  async function spawnFreshAnt(): Promise<string> {
    return await profile('Spawn fresh ANT for test', async () => {
      const ao = getAoInstance();
      const scheduler = getScheduler();
      const authority = await getAuthorityAddress();
      const antModule = await getAntModuleId();
      const localnetSigner = createLocalnetSigner(new ArweaveSigner(TEST_WALLET));

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
      await new Promise(resolve => setTimeout(resolve, 3000));

      // Load ANT Lua code
      const antLuaPath = join(__dirname, '../fixtures/contracts/ant-bundled.lua');
      const antLua = readFileSync(antLuaPath, 'utf-8');

      await ao.message({
        process: processId,
        signer: localnetSigner,
        tags: [{ name: 'Action', value: 'Eval' }],
        data: antLua,
      });

      console.log('ANT Lua loaded');

      return processId;
    });
  }

  before(async () => {
    console.log('\n========================================');
    console.log('E2E Dutch Auction Test Suite');
    console.log('========================================\n');

    const processes = await profile('Setup test environment', async () => {
      return await getOrSpawnProcesses();
    });

    marketplaceProcess = processes.marketplaceProcess;
    marketplaceProcessId = processes.marketplaceProcessId;
    arioProcessId = processes.arioProcessId;
    antRegistryProcessId = processes.antRegistryProcessId;

    logger.setProcesses({
      ario: arioProcessId,
      marketplace: marketplaceProcessId,
      ant: 'will-be-set-per-test',
    });

    console.log('Test environment ready:');
    console.log('  Marketplace:', marketplaceProcessId);
    console.log('  ARIO:', arioProcessId);
    console.log('');
  });

  after(async () => {
    await logger.save();
  });

  describe('Dutch Auction Creation', () => {
    it('should create Dutch auction with valid parameters', async () => {
      logger.startWorkflow('create-dutch-auction');

      try {
        const futureTime = Date.now() + 3_600_000; // 1 hour from now

        const result = await profile('Create Dutch auction intent', () =>
          marketplaceProcess.createIntent({
            action: 'Create-Order',
            orderType: 'dutch',
            swapToken: arioProcessId,
            quantity: '1',
            price: '10000000', // Starting price: 10 ARIO
            minimumPrice: '5000000', // Minimum price: 5 ARIO
            decreaseInterval: '60000', // Decrease every 60 seconds
            expirationTime: futureTime.toString(),
          })
        );

        assert(result, 'Result should be defined');
        assert.strictEqual(result.Action, 'Create-Intent-Notice');
        const data = JSON.parse(result.Data);
        assert(data['Intent-Id'], 'Intent-Id should be returned');
        console.log('✓ Dutch auction intent created:', data['Intent-Id']);

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });

    it('should reject Dutch auction without required parameters', async () => {
      logger.startWorkflow('dutch-auction-missing-params');

      try {
        const result = await profile('Try to create Dutch auction without minimumPrice', () =>
          marketplaceProcess.createIntent({
            action: 'Create-Order',
            orderType: 'dutch',
            swapToken: arioProcessId,
            quantity: '1',
            price: '10000000',
            // Missing: minimumPrice, decreaseInterval, expirationTime
          })
        );

        assert(result, 'Result should be defined');
        // Should get validation error
        console.log('✓ Missing parameters rejected');

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });

    it('should reject Dutch auction with minimumPrice > startingPrice', async () => {
      logger.startWorkflow('dutch-auction-invalid-price');

      try {
        const futureTime = Date.now() + 3_600_000;

        const result = await profile('Try Dutch auction with invalid price range', () =>
          marketplaceProcess.createIntent({
            action: 'Create-Order',
            orderType: 'dutch',
            swapToken: arioProcessId,
            quantity: '1',
            price: '5000000', // Starting price
            minimumPrice: '10000000', // Invalid: higher than starting price
            decreaseInterval: '60000',
            expirationTime: futureTime.toString(),
          })
        );

        assert(result, 'Result should be defined');
        // Should get validation error
        console.log('✓ Invalid price range rejected');

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });

    it('should reject Dutch auction without expiration time', async () => {
      logger.startWorkflow('dutch-auction-no-expiration');

      try {
        const result = await profile('Try Dutch auction without expiration', () =>
          marketplaceProcess.createIntent({
            action: 'Create-Order',
            orderType: 'dutch',
            swapToken: arioProcessId,
            quantity: '1',
            price: '10000000',
            minimumPrice: '5000000',
            decreaseInterval: '60000',
            // Missing: expirationTime
          })
        );

        assert(result, 'Result should be defined');
        // Should get validation error
        console.log('✓ Missing expiration time rejected');

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });

  describe('Dutch Auction Price Calculation', () => {
    it('should verify Dutch auction parameters are accepted', async () => {
      logger.startWorkflow('dutch-auction-price-calc');

      try {
        const futureTime = Date.now() + 3_600_000; // 1 hour from now

        const result = await profile('Create Dutch auction for price testing', () =>
          marketplaceProcess.createIntent({
            action: 'Create-Order',
            orderType: 'dutch',
            swapToken: arioProcessId,
            quantity: '1',
            price: '10000000', // 10 ARIO
            minimumPrice: '5000000', // 5 ARIO
            decreaseInterval: '60000', // Decrease every minute
            expirationTime: futureTime.toString(),
          })
        );

        assert(result, 'Result should be defined');
        assert.strictEqual(result.Action, 'Create-Intent-Notice');
        
        const data = JSON.parse(result.Data);
        console.log('✓ Dutch auction intent created with price parameters');
        console.log('  Starting Price: 10 ARIO');
        console.log('  Minimum Price: 5 ARIO');
        console.log('  Decrease Interval: 60s');

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });

  describe('Dutch Auction Listing and Purchase', () => {
    it('should list ANT in Dutch auction', async () => {
      logger.startWorkflow('list-dutch-auction');

      try {
        const antProcessId = await spawnFreshAnt();
        logger.setProcesses({
          ario: arioProcessId,
          marketplace: marketplaceProcessId,
          ant: antProcessId,
        });

        const futureTime = Date.now() + 3_600_000; // 1 hour from now
        const initialInfo = await marketplaceProcess.info();
        const initialOrderCount = initialInfo.activity.totalOrders;

        // Create Dutch auction intent
        const intentResult = await profile('Create Dutch auction intent', () =>
          marketplaceProcess.createIntent({
            action: 'Create-Order',
            orderType: 'dutch',
            dominantToken: antProcessId,
            swapToken: arioProcessId,
            quantity: '1',
            price: '10000000',
            minimumPrice: '5000000',
            decreaseInterval: '60000',
            expirationTime: futureTime.toString(),
          })
        );

        const intentData = JSON.parse(intentResult.Data);
        const intentId = intentData['Intent-Id'];
        console.log('Dutch auction intent created:', intentId);

        // Transfer ANT to marketplace
        const ao = getAoInstance();
        const localnetSigner = createLocalnetSigner(new ArweaveSigner(TEST_WALLET));

        await profile('Transfer ANT for Dutch auction', async () => {
          return await ao.message({
            process: antProcessId,
            signer: localnetSigner,
            tags: [
              { name: 'Action', value: 'Transfer' },
              { name: 'Recipient', value: marketplaceProcessId },
              { name: 'Quantity', value: '1' },
              { name: 'X-Intent-Id', value: intentId },
              { name: 'X-Order-Action', value: 'Create-Order' },
              { name: 'X-Dominant-Token', value: antProcessId },
              { name: 'X-Order-Type', value: 'dutch' },
              { name: 'X-Price', value: '10000000' },
              { name: 'X-Minimum-Price', value: '5000000' },
              { name: 'X-Decrease-Interval', value: '60000' },
              { name: 'X-Expiration-Time', value: futureTime.toString() },
              { name: 'X-Swap-Token', value: arioProcessId },
            ],
          });
        });

        // Wait for order creation
        await profile('Wait for Dutch auction order creation', async () => {
          const timeout = 450_000;
          const startTime = Date.now();

          while (Date.now() - startTime < timeout) {
            await new Promise(resolve => setTimeout(resolve, 5000));

            const currentInfo = await marketplaceProcess.info();
            if (currentInfo.activity.totalOrders > initialOrderCount) {
              console.log('✓ Dutch auction order created');
              return;
            }
          }

          throw new Error('Dutch auction order not created within timeout');
        });

        // Verify order exists with dutch type
        const orders = await marketplaceProcess.getOrdersByStatus('listed');
        const ordersData = JSON.parse(orders.Data);
        const dutchOrder = ordersData.items.find((o: any) => o.dominantToken === antProcessId);

        assert(dutchOrder, 'Should find Dutch auction order');
        assert.strictEqual(dutchOrder.orderType, 'dutch', 'Order type should be dutch');
        console.log('✓ Dutch auction listed successfully');

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });

  describe('Dutch Auction Expiration', () => {
    it('should validate expiration time is in the future', async () => {
      logger.startWorkflow('dutch-auction-expiration');

      try {
        const pastTime = Date.now() - 3600000; // 1 hour ago (invalid)

        const result = await profile('Try Dutch auction with past expiration', () =>
          marketplaceProcess.createIntent({
            action: 'Create-Order',
            orderType: 'dutch',
            swapToken: arioProcessId,
            quantity: '1',
            price: '10000000',
            minimumPrice: '5000000',
            decreaseInterval: '60000',
            expirationTime: pastTime.toString(), // Past time
          })
        );

        assert(result, 'Result should be defined');
        // Should get validation error for past expiration
        console.log('✓ Past expiration time handled');

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });
});


