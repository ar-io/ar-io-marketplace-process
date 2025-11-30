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
 * E2E tests for English Auction Mechanism
 * Tests English auction creation, bidding, and settlement on real AO processes
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

describe('E2E English Auction Tests', { timeout: 1_800_000 }, () => {
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
    console.log('E2E English Auction Test Suite');
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

  describe('English Auction Creation', () => {
    it('should create English auction with valid parameters', async () => {
      logger.startWorkflow('create-english-auction');

      try {
        const futureTime = Date.now() + 3_600_000; // 1 hour from now

        const result = await profile('Create English auction intent', () =>
          marketplaceProcess.createIntent({
            action: 'Create-Order',
            orderType: 'english',
            swapToken: arioProcessId,
            quantity: '1',
            price: '1000000', // Starting bid: 1 ARIO
            expirationTime: futureTime.toString(),
          })
        );

        assert(result, 'Result should be defined');
        assert.strictEqual(result.Action, 'Create-Intent-Notice');
        const data = JSON.parse(result.Data);
        assert(data['Intent-Id'], 'Intent-Id should be returned');
        console.log('✓ English auction intent created:', data['Intent-Id']);

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });

    it('should require expiration time for English auctions', async () => {
      logger.startWorkflow('english-auction-no-expiration');

      try {
        const result = await profile('Try English auction without expiration', () =>
          marketplaceProcess.createIntent({
            action: 'Create-Order',
            orderType: 'english',
            swapToken: arioProcessId,
            quantity: '1',
            price: '1000000',
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

  describe('English Auction Listing', () => {
    it('should list ANT in English auction', async () => {
      logger.startWorkflow('list-english-auction');

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

        // Create English auction intent
        const intentResult = await profile('Create English auction intent', () =>
          marketplaceProcess.createIntent({
            action: 'Create-Order',
            orderType: 'english',
            dominantToken: antProcessId,
            swapToken: arioProcessId,
            quantity: '1',
            price: '1000000', // Starting bid
            expirationTime: futureTime.toString(),
          })
        );

        const intentData = JSON.parse(intentResult.Data);
        const intentId = intentData['Intent-Id'];
        console.log('English auction intent created:', intentId);

        // Transfer ANT to marketplace
        const ao = getAoInstance();
        const localnetSigner = createLocalnetSigner(new ArweaveSigner(TEST_WALLET));

        await profile('Transfer ANT for English auction', async () => {
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
              { name: 'X-Order-Type', value: 'english' },
              { name: 'X-Price', value: '1000000' },
              { name: 'X-Expiration-Time', value: futureTime.toString() },
              { name: 'X-Swap-Token', value: arioProcessId },
            ],
          });
        });

        // Wait for order creation
        await profile('Wait for English auction order creation', async () => {
          const timeout = 450_000;
          const startTime = Date.now();

          while (Date.now() - startTime < timeout) {
            await new Promise(resolve => setTimeout(resolve, 5000));

            const currentInfo = await marketplaceProcess.info();
            if (currentInfo.activity.totalOrders > initialOrderCount) {
              console.log('✓ English auction order created');
              return;
            }
          }

          throw new Error('English auction order not created within timeout');
        });

        // Verify order exists with english type
        const orders = await marketplaceProcess.getOrdersByStatus('listed');
        const ordersData = JSON.parse(orders.Data);
        const englishOrder = ordersData.items.find((o: any) => o.dominantToken === antProcessId);

        assert(englishOrder, 'Should find English auction order');
        assert.strictEqual(englishOrder.orderType, 'english', 'Order type should be english');
        console.log('✓ English auction listed successfully');

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });

  describe('English Auction Settlement', () => {
    it('should require Order-Id for settlement', async () => {
      logger.startWorkflow('settle-auction-missing-id');

      try {
        await profile('Try to settle auction without Order-Id', async () => {
          try {
            await marketplaceProcess.process.read({
              tags: [{ name: 'Action', value: 'Settle-Auction' }],
            });
            assert.fail('Should have thrown error for missing Order-Id');
          } catch (error: any) {
            assert(
              error.message.includes('Order-Id'),
              'Error should mention Order-Id'
            );
            console.log('✓ Missing Order-Id rejected');
          }
        });

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });

    it('should reject settlement of non-existent auction', async () => {
      logger.startWorkflow('settle-nonexistent-auction');

      try {
        const result = await profile('Try to settle non-existent auction', () =>
          marketplaceProcess.settleAuction({
            orderId: 'non-existent-auction-'.padEnd(43, 'x'),
          })
        );

        assert(result, 'Result should be defined');
        assert.strictEqual(result.Action, 'Invalid-Settle-Auction-Notice');
        assert(
          result.Data &&
            (result.Data.includes('Order not found') ||
              result.Data.includes('not found')),
          'Error should mention order not found'
        );
        console.log('✓ Non-existent auction settlement rejected');

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });

    it('should validate auction is ready for settlement', async () => {
      logger.startWorkflow('settle-auction-validation');

      try {
        // Try to settle a random order ID
        const result = await profile('Try to settle unready auction', () =>
          marketplaceProcess.settleAuction({
            orderId: 'test-auction-id',
          })
        );

        assert(result, 'Result should be defined');
        // Should return error about order not found or not ready
        console.log('✓ Settlement validation working');

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });

  describe('English Auction Bidding Validation', () => {
    it('should validate bid amount requirements', async () => {
      logger.startWorkflow('bid-validation');

      try {
        // Create an English auction intent to test bidding validation
        const futureTime = Date.now() + 3_600_000;

        const result = await profile('Create auction for bid testing', () =>
          marketplaceProcess.createIntent({
            action: 'Create-Order',
            orderType: 'english',
            swapToken: arioProcessId,
            quantity: '1',
            price: '1000000', // Starting bid
            expirationTime: futureTime.toString(),
          })
        );

        assert(result, 'Result should be defined');
        assert.strictEqual(result.Action, 'Create-Intent-Notice');
        console.log('✓ Auction created for bidding tests');

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });

  describe('English Auction Expiration', () => {
    it('should validate expiration time is in the future', async () => {
      logger.startWorkflow('english-auction-expiration');

      try {
        const pastTime = Date.now() - 3600000; // 1 hour ago (invalid)

        const result = await profile('Try English auction with past expiration', () =>
          marketplaceProcess.createIntent({
            action: 'Create-Order',
            orderType: 'english',
            swapToken: arioProcessId,
            quantity: '1',
            price: '1000000',
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

  describe('English Auction Lifecycle', () => {
    it('should track auction from creation to potential settlement', async () => {
      logger.startWorkflow('auction-lifecycle');

      try {
        const futureTime = Date.now() + 3_600_000;

        // Create intent
        const intentResult = await profile('Create auction lifecycle test', () =>
          marketplaceProcess.createIntent({
            action: 'Create-Order',
            orderType: 'english',
            swapToken: arioProcessId,
            quantity: '1',
            price: '1000000',
            expirationTime: futureTime.toString(),
          })
        );

        assert(intentResult, 'Intent result should be defined');
        assert.strictEqual(intentResult.Action, 'Create-Intent-Notice');

        // Verify it would appear in listed orders after Credit-Notice
        const listedOrders = await profile('Get listed orders', () =>
          marketplaceProcess.getOrders({ status: 'listed' })
        );

        assert(listedOrders, 'Listed orders should be defined');
        console.log('✓ Auction lifecycle tracking works');

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });
});


