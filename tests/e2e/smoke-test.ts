/**
 * Quick smoke test to demonstrate test logger functionality
 * This test runs a single workflow and generates test-output.json
 */
import { after, before, describe, it } from 'node:test';
import { MarketplaceProcess } from '../utils/marketplace_process.js';
import { getOrSpawnProcesses } from '../utils/process_manager.js';
import { resetTestLogger } from '../utils/test_logger.js';

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
      const { connect } = await import('@permaweb/aoconnect');
      const { TEST_SIGNER } = await import('../utils/constants.js');
      
      const ao = connect({
        CU_URL: process.env.CU_URL || 'https://cu.ardrive.io',
      });
      
      const processId = await ANT.spawn({
        ao,
        signer: TEST_SIGNER,
      });
      
      console.log('Fresh ANT spawned:', processId);
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

