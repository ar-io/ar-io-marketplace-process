/**
 * Quick smoke test to demonstrate test logger functionality
 * This test runs a single workflow and generates test-output.json
 */
import { config } from 'dotenv';
import { after, before, describe, it } from 'node:test';
import { MarketplaceProcess } from '../utils/marketplace_process.js';
import { getOrSpawnProcesses } from '../utils/process_manager.js';
import { resetTestLogger } from '../utils/test_logger.js';

// Load environment variables
config();

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

describe('Smoke Test - Logger Demo', { timeout: 600_000 }, () => {
  let marketplaceProcess: MarketplaceProcess;
  let arioProcessId: string;
  let marketplaceProcessId: string;
  const logger = resetTestLogger();
  
  /**
   * Helper to spawn a fresh ANT for the smoke test
   */
  async function spawnFreshAnt(): Promise<string> {
    return await profile('Spawn fresh ANT for smoke test', async () => {
      const { ANT } = await import('@ar.io/sdk');
      const { TEST_SIGNER } = await import('../utils/constants.js');
      const { getAoInstance, getScheduler, getAuthorityAddress, getAntModuleId } = await import('../utils/constants.js');
      
      // Use SDK for configuration
      const ao = getAoInstance();
      const scheduler = getScheduler();
      const authority = await getAuthorityAddress();
      const antModule = await getAntModuleId(); // ANT-specific WASM module
      
      // Get ANT Registry ID from the spawned processes
      const { antRegistryProcessId } = await import('../utils/process_manager.js').then(m => m.loadProcessConfig()!);
      
      // Use ANT.spawn from the SDK - returns processId directly
      const processId = await ANT.spawn({
        ao,
        signer: TEST_SIGNER,
        scheduler,
        authority,
        module: antModule,
        antRegistryId: antRegistryProcessId,
      });
      
      console.log('Fresh ANT spawned:', processId);
      
      // Verify ANT is responsive
      try {
        const { AOProcess } = await import('@ar.io/sdk');
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
    console.log('\n=== Smoke Test: Demonstrating Test Logger ===\n');
    
    const processes = await profile('Setup smoke test environment', async () => {
      return await getOrSpawnProcesses();
    });
    
    marketplaceProcess = processes.marketplaceProcess;
    marketplaceProcessId = processes.marketplaceProcessId;
    arioProcessId = processes.arioProcessId;

    logger.setProcesses({
      ario: arioProcessId,
      marketplace: marketplaceProcessId,
      ant: 'will-be-set-in-test',
    });

    console.log('Processes ready:');
    console.log('  Marketplace:', marketplaceProcessId);
    console.log('  ARIO:', arioProcessId);
    console.log('  Note: Test will spawn its own ANT');
  });

  after(async () => {
    console.log('\n=== Saving Test Output ===\n');
    await logger.save();
    console.log('\n✓ Check test-output.json for detailed results\n');
  });

  it('should attempt to create a listing and log the result', async () => {
    logger.startWorkflow('smoke-test-listing');
    
    try {
      // Spawn fresh ANT for this test
      const antProcessId = await spawnFreshAnt();
      
      const price = '1000000';

      const result = await profile('Send ANT transfer for smoke test listing', () =>
        marketplaceProcess.listAntForFixedPrice(
          antProcessId,
          price,
          arioProcessId,
          logger,
        )
      );

      console.log(`Transfer successful: ${result.txId.substring(0, 16)}...`);
      console.log(`Intent ID: ${result.intentId}`);

      // Wait up to 15 seconds for order creation
      const maxWait = 15000;
      const checkInterval = 3000;
      let elapsed = 0;
      let orderCreated = false;

      await profile('Wait for Credit-Notice processing (up to 15s)', async () => {
        while (elapsed < maxWait) {
          await new Promise(resolve => setTimeout(resolve, checkInterval));
          elapsed += checkInterval;
          
          const info = await marketplaceProcess.info();
          console.log(`[${elapsed/1000}s] Orders: ${info.activity.totalOrders}, Intents: ${info.intents.total}`);
          
          if (info.activity.totalOrders > 0) {
            console.log('✓ Order was created!');
            orderCreated = true;
            
            // Check intent status
            try {
              const intentResult = await marketplaceProcess.getIntentById(result.intentId);
              const intent = JSON.parse(intentResult.Data);
              console.log('Intent status:', intent.Status);
              logger.updateIntent(result.intentId, { status: intent.Status });
            } catch (e) {
              console.log('Could not fetch intent status');
            }
            
            logger.completeWorkflow(true);
            break;
          }
        }
        
        if (!orderCreated) {
          console.log('✗ No order created after 15s');
          
          // Check intent status
          try {
            const intentResult = await marketplaceProcess.getIntentById(result.intentId);
            const intent = JSON.parse(intentResult.Data);
            console.log('Intent status:', intent.Status);
            console.log('Intent data:', JSON.stringify(intent, null, 2));
            logger.updateIntent(result.intentId, { status: intent.Status });
          } catch (e) {
            console.log('Could not fetch intent:', e);
          }
          
          logger.completeWorkflow(false, 'Order not created after 15s');
        }
      });
    } catch (error: any) {
      console.log('✗ Test failed:', error.message);
      logger.completeWorkflow(false, error.message);
    }
  });

  it('should check marketplace info', async () => {
    logger.startWorkflow('check-marketplace-info');
    
    try {
      const info = await profile('Get marketplace info', () =>
        marketplaceProcess.info()
      );
      console.log('\nMarketplace status:');
      console.log('  Total orders:', info.activity.totalOrders);
      console.log('  Listed orders:', info.activity.listedOrders);
      console.log('  ARIO token:', info.ucm.arioTokenProcess);
      
      logger.completeWorkflow(true);
    } catch (error: any) {
      logger.completeWorkflow(false, error.message);
      throw error;
    }
  });
});

