import { before, describe, it, after } from 'node:test';
import assert from 'node:assert';
import { MarketplaceProcess } from '../utils/marketplace_process.js';
import { getOrSpawnProcesses } from '../utils/process_manager.js';
import { resetTestLogger } from '../utils/test_logger.js';

/**
 * E2E tests for Info Endpoint
 * Tests all Info endpoint fields with real data on real AO processes
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

describe('E2E Info Endpoint Tests', { timeout: 1_800_000 }, () => {
  let marketplaceProcess: MarketplaceProcess;
  let arioProcessId: string;
  let marketplaceProcessId: string;
  const logger = resetTestLogger();

  before(async () => {
    console.log('\n========================================');
    console.log('E2E Info Endpoint Test Suite');
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

  describe('Info Structure Validation', () => {
    it('should return info with correct top-level structure', async () => {
      logger.startWorkflow('info-structure');

      try {
        const info = await profile('Get marketplace info', () =>
          marketplaceProcess.info()
        );

        // Validate top-level structure
        assert(info, 'Info should be defined');
        assert(typeof info.name === 'string', 'Name should be a string');
        assert(typeof info.processId === 'string', 'ProcessId should be a string');
        
        console.log('Info structure:');
        console.log('  Name:', info.name);
        console.log('  ProcessId:', info.processId);

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });

  describe('Activity Statistics', () => {
    it('should return all activity statistics fields', async () => {
      logger.startWorkflow('activity-stats');

      try {
        const info = await profile('Get activity statistics', () =>
          marketplaceProcess.info()
        );

        assert(info.activity, 'Activity should be defined');
        
        // Verify all activity fields are numbers
        assert(
          typeof info.activity.totalOrders === 'number',
          'totalOrders should be a number'
        );
        assert(
          typeof info.activity.listedOrders === 'number',
          'listedOrders should be a number'
        );
        assert(
          typeof info.activity.executedOrders === 'number',
          'executedOrders should be a number'
        );
        assert(
          typeof info.activity.cancelledOrders === 'number',
          'cancelledOrders should be a number'
        );
        assert(
          typeof info.activity.expiredOrders === 'number',
          'expiredOrders should be a number'
        );
        assert(
          typeof info.activity.activeOrders === 'number',
          'activeOrders should be a number'
        );
        assert(
          typeof info.activity.readyForSettlement === 'number',
          'readyForSettlement should be a number'
        );

        console.log('Activity statistics:');
        console.log('  Total Orders:', info.activity.totalOrders);
        console.log('  Listed Orders:', info.activity.listedOrders);
        console.log('  Executed Orders:', info.activity.executedOrders);
        console.log('  Cancelled Orders:', info.activity.cancelledOrders);
        console.log('  Expired Orders:', info.activity.expiredOrders);
        console.log('  Active Orders:', info.activity.activeOrders);
        console.log('  Ready for Settlement:', info.activity.readyForSettlement);

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });

  describe('Intent Statistics', () => {
    it('should return all intent statistics fields', async () => {
      logger.startWorkflow('intent-stats');

      try {
        const info = await profile('Get intent statistics', () =>
          marketplaceProcess.info()
        );

        assert(info.intents, 'Intents should be defined');
        
        assert(
          typeof info.intents.total === 'number',
          'intents.total should be a number'
        );
        assert(info.intents.byStatus !== undefined, 'intents.byStatus should be defined');
        assert(info.intents.byType !== undefined, 'intents.byType should be defined');
        assert(info.intents.byAction !== undefined, 'intents.byAction should be defined');

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

  describe('UCM Statistics', () => {
    it('should return all UCM statistics fields', async () => {
      logger.startWorkflow('ucm-stats');

      try {
        const info = await profile('Get UCM statistics', () =>
          marketplaceProcess.info()
        );

        assert(info.ucm, 'UCM should be defined');
        
        assert(
          typeof info.ucm.totalPairs === 'number',
          'totalPairs should be a number'
        );
        assert(
          typeof info.ucm.accruedFees === 'string',
          'accruedFees should be a string'
        );
        assert(
          typeof info.ucm.arioTokenProcess === 'string',
          'arioTokenProcess should be a string'
        );

        console.log('UCM statistics:');
        console.log('  Total Pairs:', info.ucm.totalPairs);
        console.log('  Accrued Fees:', info.ucm.accruedFees);
        console.log('  ARIO Token Process:', info.ucm.arioTokenProcess);

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });

    it('should verify ARIO token process matches expected value', async () => {
      logger.startWorkflow('ucm-ario-token');

      try {
        const info = await profile('Verify ARIO token process', () =>
          marketplaceProcess.info()
        );

        assert.strictEqual(
          info.ucm.arioTokenProcess,
          arioProcessId,
          'ARIO token process should match expected value'
        );
        console.log('✓ ARIO token process verified:', arioProcessId);

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });

  describe('Statistics Updates', () => {
    it('should show updated statistics after operations', async () => {
      logger.startWorkflow('stats-updates');

      try {
        // Get initial state
        const initialInfo = await profile('Get initial info', () =>
          marketplaceProcess.info()
        );
        console.log('Initial state:');
        console.log('  Total Orders:', initialInfo.activity.totalOrders);
        console.log('  Total Intents:', initialInfo.intents.total);

        // Create an intent
        await profile('Create intent to affect stats', () =>
          marketplaceProcess.createIntent({
            action: 'Create-Order',
            orderType: 'fixed',
            swapToken: arioProcessId,
            quantity: '1000',
            price: '500000',
          })
        );

        // Get updated state
        const updatedInfo = await profile('Get updated info', () =>
          marketplaceProcess.info()
        );
        console.log('Updated state:');
        console.log('  Total Orders:', updatedInfo.activity.totalOrders);
        console.log('  Total Intents:', updatedInfo.intents.total);

        // Verify intent count increased
        assert(
          updatedInfo.intents.total > initialInfo.intents.total,
          'Intent count should have increased'
        );
        console.log('✓ Statistics updated correctly after operation');

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });

  describe('Field Type Validation', () => {
    it('should verify all numeric fields are actually numbers', async () => {
      logger.startWorkflow('numeric-field-validation');

      try {
        const info = await profile('Get info for type validation', () =>
          marketplaceProcess.info()
        );

        // Activity fields
        const activityFields = [
          'totalOrders',
          'listedOrders',
          'executedOrders',
          'cancelledOrders',
          'expiredOrders',
          'activeOrders',
          'readyForSettlement',
        ];

        for (const field of activityFields) {
          assert(
            typeof info.activity[field] === 'number',
            `activity.${field} should be a number, got ${typeof info.activity[field]}`
          );
        }
        console.log('✓ All activity fields are numbers');

        // Intent fields
        assert(
          typeof info.intents.total === 'number',
          `intents.total should be a number, got ${typeof info.intents.total}`
        );
        console.log('✓ Intent total is a number');

        // UCM fields
        assert(
          typeof info.ucm.totalPairs === 'number',
          `ucm.totalPairs should be a number, got ${typeof info.ucm.totalPairs}`
        );
        console.log('✓ UCM totalPairs is a number');

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });

    it('should verify all string fields are actually strings', async () => {
      logger.startWorkflow('string-field-validation');

      try {
        const info = await profile('Get info for string validation', () =>
          marketplaceProcess.info()
        );

        assert(
          typeof info.name === 'string',
          `name should be a string, got ${typeof info.name}`
        );
        assert(
          typeof info.processId === 'string',
          `processId should be a string, got ${typeof info.processId}`
        );
        assert(
          typeof info.ucm.accruedFees === 'string',
          `ucm.accruedFees should be a string, got ${typeof info.ucm.accruedFees}`
        );
        assert(
          typeof info.ucm.arioTokenProcess === 'string',
          `ucm.arioTokenProcess should be a string, got ${typeof info.ucm.arioTokenProcess}`
        );

        console.log('✓ All string fields are strings');

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });

  describe('Whitelisted Modules', () => {
    it('should return whitelistedModules as array', async () => {
      logger.startWorkflow('whitelisted-modules');

      try {
        const info = await profile('Get marketplace info', () =>
          marketplaceProcess.info()
        );

        assert(
          info.whitelistedModules !== undefined,
          'whitelistedModules should be defined'
        );
        assert(
          Array.isArray(info.whitelistedModules),
          'whitelistedModules should be an array'
        );

        console.log('Whitelisted Modules:');
        console.log(JSON.stringify(info.whitelistedModules, null, 2));
        
        const moduleCount = info.whitelistedModules.length;
        console.log(`✓ Found ${moduleCount} whitelisted module(s)`);

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });

  describe('Complete Info Response', () => {
    it('should return complete info with all sections populated', async () => {
      logger.startWorkflow('complete-info');

      try {
        const info = await profile('Get complete marketplace info', () =>
          marketplaceProcess.info()
        );

        // Print complete info for verification
        console.log('\n=== Complete Marketplace Info ===');
        console.log(JSON.stringify(info, null, 2));
        console.log('=================================\n');

        // Verify all main sections exist
        assert(info.name, 'Name should exist');
        assert(info.processId, 'ProcessId should exist');
        assert(info.activity, 'Activity section should exist');
        assert(info.intents, 'Intents section should exist');
        assert(info.ucm, 'UCM section should exist');
        assert(info.whitelistedModules !== undefined, 'WhitelistedModules should exist');

        console.log('✓ All main sections present');
        console.log('✓ Info endpoint comprehensive test passed');

        logger.completeWorkflow(true);
      } catch (error: any) {
        logger.completeWorkflow(false, error.message);
        throw error;
      }
    });
  });
});


