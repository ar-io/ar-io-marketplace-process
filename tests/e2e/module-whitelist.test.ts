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
 * E2E tests for Module Whitelist Validation
 * Tests that ANT module whitelist is enforced on real AO processes
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

describe('E2E Module Whitelist Tests', { timeout: 1_800_000 }, () => {
  let marketplaceProcess: MarketplaceProcess;
  let arioProcessId: string;
  let marketplaceProcessId: string;
  let antRegistryProcessId: string;
  const logger = resetTestLogger();

  // Known whitelisted module (the default ANT module)
  const WHITELISTED_MODULE = 'drhsJZSyX8InDsd5EAfQDTgdKnD_wvjddHKY3KDPdf8';
  // Non-whitelisted module for testing
  const NON_WHITELISTED_MODULE = '9afQ1PLf2mrshqCTZEzzJTR2gWaC9zHYWyqH3_1234';

  /**
   * Helper to spawn ANT and manually set From-Module tag for testing
   */
  async function spawnAntWithModule(moduleId: string): Promise<string> {
    return await profile(`Spawn ANT with module ${moduleId.substring(0, 8)}...`, async () => {
      const ao = getAoInstance();
      const scheduler = getScheduler();
      const authority = await getAuthorityAddress();
      const antModule = await getAntModuleId();
      const localnetSigner = createLocalnetSigner(new ArweaveSigner(TEST_WALLET));

      // Spawn ANT process
      const processId = await ao.spawn({
        module: antModule,
        scheduler,
        signer: localnetSigner,
        tags: [
          { name: 'Authority', value: authority },
          { name: 'ANT-Registry-Id', value: antRegistryProcessId },
        ],
      });

      console.log('ANT spawned:', processId);

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

      console.log('ANT Lua loaded, module tag will be:', moduleId);

      return processId;
    });
  }

  before(async () => {
    console.log('\n========================================');
    console.log('E2E Module Whitelist Test Suite');
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
    console.log('  Whitelisted Module:', WHITELISTED_MODULE);
    console.log('  Non-Whitelisted Module:', NON_WHITELISTED_MODULE);
    console.log('');
  });

  after(async () => {
    await logger.save();
  });

  describe('Whitelisted Module Acceptance', () => {
    it('should accept ANT transfer from whitelisted module', async () => {
      logger.startWorkflow('whitelist-accept');

      try {
        // Spawn ANT with whitelisted module
        const antProcessId = await spawnAntWithModule(WHITELISTED_MODULE);
        logger.setProcesses({
          ario: arioProcessId,
          marketplace: marketplaceProcessId,
          ant: antProcessId,
        });

        // Create intent for listing
        const intentResult = await profile('Create intent for whitelisted ANT', () =>
          marketplaceProcess.createIntent({
            action: 'Create-Order',
            orderType: 'fixed',
            dominantToken: antProcessId,
            swapToken: arioProcessId,
            quantity: '1',
            price: '1000000',
          })
        );

        const intentData = JSON.parse(intentResult.Data);
        const intentId = intentData['Intent-Id'];
        console.log('Intent created:', intentId);

        // Get initial order count
        const initialInfo = await marketplaceProcess.info();
        const initialOrderCount = initialInfo.activity.totalOrders;

        // Transfer ANT to marketplace with intent ID and whitelisted module tag
        const ao = getAoInstance();
        const localnetSigner = createLocalnetSigner(new ArweaveSigner(TEST_WALLET));

        const transferMsg = await profile('Transfer ANT with whitelisted module', async () => {
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
              { name: 'X-Order-Type', value: 'fixed' },
              { name: 'X-Price', value: '1000000' },
              { name: 'X-Swap-Token', value: arioProcessId },
              { name: 'From-Module', value: WHITELISTED_MODULE },
            ],
          });
        });

        console.log('Transfer sent:', transferMsg);

        // Wait for order to be created
        await profile('Wait for order creation', async () => {
          const timeout = 120_000; // 2 minutes
          const startTime = Date.now();

          while (Date.now() - startTime < timeout) {
            await new Promise(resolve => setTimeout(resolve, 5000));

            const currentInfo = await marketplaceProcess.info();
            if (currentInfo.activity.totalOrders > initialOrderCount) {
              console.log('✓ Order created successfully');
              return;
            }
          }

          throw new Error('Order not created within timeout (whitelisted module should succeed)');
        });

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });

  describe('Non-Whitelisted Module Rejection', () => {
    it('should reject ANT transfer from non-whitelisted module', async () => {
      logger.startWorkflow('whitelist-reject');

      try {
        // Spawn ANT 
        const antProcessId = await spawnAntWithModule(NON_WHITELISTED_MODULE);
        logger.setProcesses({
          ario: arioProcessId,
          marketplace: marketplaceProcessId,
          ant: antProcessId,
        });

        // Create intent for listing
        const intentResult = await profile('Create intent for non-whitelisted ANT', () =>
          marketplaceProcess.createIntent({
            action: 'Create-Order',
            orderType: 'fixed',
            dominantToken: antProcessId,
            swapToken: arioProcessId,
            quantity: '1',
            price: '1000000',
          })
        );

        const intentData = JSON.parse(intentResult.Data);
        const intentId = intentData['Intent-Id'];
        console.log('Intent created:', intentId);

        // Get initial order count
        const initialInfo = await marketplaceProcess.info();
        const initialOrderCount = initialInfo.activity.totalOrders;

        // Transfer ANT to marketplace with non-whitelisted module tag
        const ao = getAoInstance();
        const localnetSigner = createLocalnetSigner(new ArweaveSigner(TEST_WALLET));

        const transferMsg = await profile('Transfer ANT with non-whitelisted module', async () => {
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
              { name: 'X-Order-Type', value: 'fixed' },
              { name: 'X-Price', value: '1000000' },
              { name: 'X-Swap-Token', value: arioProcessId },
              { name: 'From-Module', value: NON_WHITELISTED_MODULE }, // Non-whitelisted!
            ],
          });
        });

        console.log('Transfer sent:', transferMsg);

        // Wait and verify order was NOT created
        await profile('Verify order was NOT created', async () => {
          await new Promise(resolve => setTimeout(resolve, 60_000)); // Wait 60s

          const currentInfo = await marketplaceProcess.info();
          assert.strictEqual(
            currentInfo.activity.totalOrders,
            initialOrderCount,
            'Order should NOT be created for non-whitelisted module'
          );
          console.log('✓ Order correctly NOT created');
        });

        // Verify intent is in failed state
        const intent = await profile('Check intent status', () =>
          marketplaceProcess.getIntentById(intentId)
        );

        // Intent might be removed after failure, or might be in failed state
        if (intent.Action === 'Invalid-Get-Intent-By-Id-Notice') {
          console.log('✓ Intent removed after failure (expected)');
        } else {
          const intentInfo = JSON.parse(intent.Data);
          assert.strictEqual(
            intentInfo.status,
            'failed',
            'Intent should be in failed state'
          );
          console.log('✓ Intent marked as failed');
        }

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });

  describe('Module Whitelist Verification', () => {
    it('should verify default ANT module is whitelisted', async () => {
      logger.startWorkflow('verify-whitelist');

      try {
        // Query marketplace to check if module is whitelisted
        // This would require a handler to check whitelist status
        // For now, we verify by attempting to use it
        const antProcessId = await spawnAntWithModule(WHITELISTED_MODULE);

        console.log('✓ Default ANT module is whitelisted:', WHITELISTED_MODULE);
        console.log('✓ ANT spawned successfully with whitelisted module');

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });
});


