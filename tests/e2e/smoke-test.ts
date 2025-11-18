/**
 * Quick smoke test to demonstrate test logger functionality
 * This test runs a single workflow and generates test-output.json
 */
import { after, before, describe, it } from 'node:test';
import { MarketplaceProcess } from '../utils/marketplace_process.js';
import { getOrSpawnProcesses } from '../utils/process_manager.js';
import { resetTestLogger } from '../utils/test_logger.js';

describe('Smoke Test - Logger Demo', () => {
  let marketplaceProcess: MarketplaceProcess;
  let arioProcessId: string;
  let antProcessId: string;
  let marketplaceProcessId: string;
  const logger = resetTestLogger();

  before(async () => {
    console.log('\n=== Smoke Test: Demonstrating Test Logger ===\n');
    
    const processes = await getOrSpawnProcesses();
    
    marketplaceProcess = processes.marketplaceProcess;
    marketplaceProcessId = processes.marketplaceProcessId;
    arioProcessId = processes.arioProcessId;
    antProcessId = processes.antProcessId;

    logger.setProcesses({
      ario: arioProcessId,
      marketplace: marketplaceProcessId,
      ant: antProcessId,
    });

    console.log('Processes ready:');
    console.log('  Marketplace:', marketplaceProcessId);
    console.log('  ARIO:', arioProcessId);
    console.log('  ANT:', antProcessId);
  });

  after(async () => {
    console.log('\n=== Saving Test Output ===\n');
    await logger.save();
    console.log('\n✓ Check test-output.json for detailed results\n');
  });

  it('should attempt to create a listing and log the result', async () => {
    logger.startWorkflow('smoke-test-listing');
    
    try {
      const price = '1000000';

      console.log('\nAttempting ANT transfer with order tags...');
      const result = await marketplaceProcess.listAntForFixedPrice(
        antProcessId,
        price,
        arioProcessId,
        logger,
      );

      console.log(`Transfer successful: ${result.txId.substring(0, 16)}...`);
      console.log(`Intent ID: ${result.intentId}`);
      console.log('Waiting for Credit-Notice to be processed...');

          // Wait up to 30 seconds for order creation
          const maxWait = 30000;
      const checkInterval = 3000;
      let elapsed = 0;
      let orderCreated = false;

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
        console.log('✗ No order created after 30s');
        
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
        
        logger.completeWorkflow(false, 'Order not created after 30s');
      }
    } catch (error: any) {
      console.log('✗ Test failed:', error.message);
      logger.completeWorkflow(false, error.message);
    }
  });

  it('should check marketplace info', async () => {
    logger.startWorkflow('check-marketplace-info');
    
    try {
      const info = await marketplaceProcess.info();
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

