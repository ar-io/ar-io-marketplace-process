import { before, beforeEach, describe, it } from 'node:test';
import { MarketplaceProcess } from '../utils/marketplace_process.js';
import { LocalAO, createLocalProcess } from '../utils/local_ao.js';
import { AOProcess } from '@ar.io/sdk';
import assert from 'node:assert';
import {
  BUNDLED_MARKETPLACE_SOURCE_CODE,
  TEST_SIGNER,
} from '../utils/constants.js';

describe('Intent Workflow Tracking', () => {
  let marketplaceProcess: MarketplaceProcess;
  let ao_mock: LocalAO;

  // create a new process and mock before the tests
  const TEST_ANT_PROCESS = 'test-ant-process-'.padEnd(43, '1');
  const TEST_ARIO_PROCESS = 'test-ario-process'.padEnd(43, '1');
  const TEST_SENDER = 'y0yFQVYWtQblOKClbuBmo6rqxCiKD1KHOt_Aizgm8w8'; // Address from TEST_SIGNER

  before(async () => {
    // Inject test ARIO token process BEFORE the bundle loads (so globals.lua picks it up)
    const luaWithTestConfig = `ARIO_TOKEN_PROCESS_ID = "${TEST_ARIO_PROCESS}"\n` + BUNDLED_MARKETPLACE_SOURCE_CODE;
    
    const process = await createLocalProcess({
      processId: 'my-marketplace-process-'.padEnd(43, '1'),
      lua: luaWithTestConfig,
    });
    ao_mock = process.ao as any as LocalAO;
    marketplaceProcess = new MarketplaceProcess({
      process: new AOProcess({ ao: process.ao, processId: process.processId }),
			signer: TEST_SIGNER,
    });
  });

  beforeEach(async () => {
    // clear the current memory and resultsCache of the mock before each new test
    await ao_mock.reset();
    
    // Re-set ARIO token after reset (append to loaded code state)
    await marketplaceProcess.process.send({
      tags: [{ name: 'Action', value: 'Eval' }],
      data: `ARIO_TOKEN_PROCESS_ID = "${TEST_ARIO_PROCESS}"`,
      signer: TEST_SIGNER,
    });
  });

  describe('Create-Intent', () => {
    it('should create an intent for Create-Order action', async () => {
      const result = await marketplaceProcess.createIntent({
        action: 'Create-Order',
        orderType: 'fixed',
        swapToken: 'test-swap-token-'.padEnd(43, '1'),
        quantity: '1000',
        price: '500',
      });

      assert(result, 'Create intent result should be defined');
      assert.strictEqual(result.Action, 'Create-Intent-Notice');
      const data = JSON.parse(result.Data);
      assert(data['Intent-Id'], 'Intent-Id should be returned');
    });

    it('should fail to create intent without required X-Intent-Action', async () => {
      try {
        await marketplaceProcess.process.send({
          tags: [{ name: 'Action', value: 'Create-Intent' }],
          signer: TEST_SIGNER,
        });
        assert.fail('Should have thrown an error for missing X-Intent-Action');
      } catch (error: any) {
        assert(
          error.message.includes('X-Intent-Action'),
          'Error should mention X-Intent-Action',
        );
      }
    });

    it('should fail to create intent without required parameters for Create-Order', async () => {
      const result = await marketplaceProcess.createIntent({
        action: 'Create-Order',
        // Missing orderType, swapToken, quantity
      });

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Invalid-Create-Intent-Notice');
      assert(result.Tags?.Error, 'Should have Error tag');
    });

    it('should fail to create buy intent without X-Intent-Swap-Token', async () => {
      const result = await marketplaceProcess.createIntent({
        action: 'Create-Order',
        requestedOrderId: 'test-order-123',
        quantity: '1000000', // Has quantity but missing swapToken
      });

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Invalid-Create-Intent-Notice');
      assert(
        result.Data.includes('X-Intent-Swap-Token required'),
        'Error should mention X-Intent-Swap-Token is required',
      );
    });

    it('should fail to create buy intent without X-Intent-Quantity', async () => {
      const result = await marketplaceProcess.createIntent({
        action: 'Create-Order',
        requestedOrderId: 'test-order-123',
        swapToken: TEST_ARIO_PROCESS, // Has swapToken but missing quantity
      });

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Invalid-Create-Intent-Notice');
      assert(
        result.Data.includes('X-Intent-Quantity required'),
        'Error should mention X-Intent-Quantity is required',
      );
    });

    it('should successfully create buy intent with all required parameters', async () => {
      const result = await marketplaceProcess.createIntent({
        action: 'Create-Order',
        requestedOrderId: 'test-order-123',
        swapToken: TEST_ARIO_PROCESS,
        quantity: '1000000',
      });

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Create-Intent-Notice');
      const data = JSON.parse(result.Data);
      assert(data['Intent-Id'], 'Intent-Id should be returned');
      assert.strictEqual(data['Intent-Id'], '1', 'First intent should have ID 1');
    });

    it('should create an intent for Cancel-Order action', async () => {
      const result = await marketplaceProcess.createIntent({
        action: 'Cancel-Order',
        orderId: 'test-order-123',
      });

      assert(result, 'Create intent result should be defined');
      assert.strictEqual(result.Action, 'Create-Intent-Notice');
      const data = JSON.parse(result.Data);
      assert(data['Intent-Id'], 'Intent-Id should be returned');
    });

    it('should create an intent for Settle-Auction action', async () => {
      const result = await marketplaceProcess.createIntent({
        action: 'Settle-Auction',
        orderId: 'test-auction-456',
      });

      assert(result, 'Create intent result should be defined');
      assert.strictEqual(result.Action, 'Create-Intent-Notice');
      const data = JSON.parse(result.Data);
      assert(data['Intent-Id'], 'Intent-Id should be returned');
    });
  });

  describe('Get-Paginated-Intents', () => {
    it('should return empty list when no intents exist', async () => {
      const result = await marketplaceProcess.getPaginatedIntents();

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Get-Paginated-Intents-Notice');
      const data = JSON.parse(result.Data);
      assert(Array.isArray(data.items), 'Items should be an array');
      assert.strictEqual(data.items.length, 0, 'Should have no intents');
    });

    it('should return created intents', async () => {
      // Create an intent first
      await marketplaceProcess.createIntent({
        action: 'Create-Order',
        orderType: 'fixed',
        swapToken: 'test-swap-token-'.padEnd(43, '1'),
        quantity: '1000',
      });

      const result = await marketplaceProcess.getPaginatedIntents();

      assert(result, 'Result should be defined');
      const data = JSON.parse(result.Data);
      assert.strictEqual(data.items.length, 1, 'Should have one intent');
      assert.strictEqual(data.items[0].action, 'Create-Order');
      assert.strictEqual(data.items[0].type, 'parent');
      assert.strictEqual(data.items[0].status, 'pending');
    });

    it('should support pagination with limit', async () => {
      // Create multiple intents
      await marketplaceProcess.createIntent({
        action: 'Create-Order',
        orderType: 'fixed',
        swapToken: 'test-swap-token-'.padEnd(43, '1'),
        quantity: '1000',
      });

      await marketplaceProcess.createIntent({
        action: 'Cancel-Order',
        orderId: 'test-order-123',
      });

      const result = await marketplaceProcess.getPaginatedIntents({
        limit: 1,
      });

      assert(result, 'Result should be defined');
      const data = JSON.parse(result.Data);
      assert.strictEqual(data.items.length, 1, 'Should return only 1 intent');
      assert.strictEqual(data.limit, 1);
      assert.strictEqual(data.hasMore, true);
      assert(data.nextCursor, 'Should have nextCursor');
    });
  });

  describe('Get-Intent-By-Id', () => {
    it('should return intent by ID', async () => {
      // Create an intent
      const createResult = await marketplaceProcess.createIntent({
        action: 'Create-Order',
        orderType: 'fixed',
        swapToken: 'test-swap-token-'.padEnd(43, '1'),
        quantity: '1000',
      });

      const createData = JSON.parse(createResult.Data);
      const intentId = createData['Intent-Id'];

      const result = await marketplaceProcess.getIntentById(intentId);

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Get-Intent-By-Id-Notice');
      const data = JSON.parse(result.Data);
      assert.strictEqual(data.intentId, intentId);
      assert.strictEqual(data.action, 'Create-Order');
      assert.strictEqual(data.type, 'parent');
    });

    it('should return error for non-existent intent', async () => {
      const result = await marketplaceProcess.getIntentById('non-existent-id');

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Invalid-Get-Intent-By-Id-Notice');
      assert(result.Tags?.Error, 'Should have Error tag');
    });

    it('should return error when Intent-Id is missing', async () => {
      try {
        await marketplaceProcess.process.read({
          tags: [{ name: 'Action', value: 'Get-Intent-By-Id' }],
        });
        assert.fail('Should have thrown an error for missing Intent-Id');
      } catch (error: any) {
        assert(
          error.message.includes('Intent-Id'),
          'Error should mention Intent-Id',
        );
      }
    });
  });

  describe('Info (Intent Stats)', () => {
    it('should return statistics about intents via info handler', async () => {
      // Create various intents
      await marketplaceProcess.createIntent({
        action: 'Create-Order',
        orderType: 'fixed',
        swapToken: 'test-swap-token-'.padEnd(43, '1'),
        quantity: '1000',
      });

      await marketplaceProcess.createIntent({
        action: 'Cancel-Order',
        orderId: 'test-order-123',
      });

      const info = await marketplaceProcess.info();

      assert(info, 'Info should be defined');
      assert(info.intents, 'Intents should be defined');
      assert.strictEqual(info.intents.total, 2, 'Should have 2 total intents');
      assert.strictEqual(
        info.intents.byStatus.pending,
        2,
        'Should have 2 pending intents',
      );
      assert.strictEqual(
        info.intents.byType.parent,
        2,
        'Should have 2 parent intents',
      );
      assert.strictEqual(info.intents.byAction['Create-Order'], 1);
      assert.strictEqual(info.intents.byAction['Cancel-Order'], 1);
    });

    it('should return zero stats when no intents exist via info handler', async () => {
      const info = await marketplaceProcess.info();

      assert(info, 'Info should be defined');
      assert(info.intents, 'Intents should be defined');
      assert.strictEqual(info.intents.total, 0);
      assert.deepStrictEqual(info.intents.byStatus, []);
      assert.deepStrictEqual(info.intents.byType, []);
      assert.deepStrictEqual(info.intents.byAction, []);
    });
  });
});

// Separate describe block for Credit-Notice tests that need ARIO_TOKEN_PROCESS_ID
describe('Credit-Notice Intent Resolution Workflow', () => {
  let marketplaceProcess: MarketplaceProcess;
  let ao_mock: LocalAO;
  const TEST_ANT_PROCESS = 'test-ant-process-'.padEnd(43, '1');
  const TEST_ARIO_PROCESS = 'test-ario-process'.padEnd(43, '1');
  const TEST_SENDER = ''.padEnd(43, '1'); // Must match PROCESS_OWNER from DEFAULT_HANDLE_OPTIONS

  before(async () => {
    // Inject test ARIO token process BEFORE the bundle loads (so globals.lua picks it up)
    const luaWithTestConfig = `ARIO_TOKEN_PROCESS_ID = "${TEST_ARIO_PROCESS}"\n` + BUNDLED_MARKETPLACE_SOURCE_CODE;
    
    const process = await createLocalProcess({
      processId: 'my-marketplace-cn-'.padEnd(43, '2'),
      lua: luaWithTestConfig,
    });
    ao_mock = process.ao as any as LocalAO;
    marketplaceProcess = new MarketplaceProcess({
      process: new AOProcess({ ao: process.ao, processId: process.processId }),
      signer: TEST_SIGNER,
    });
  });

  // NO beforeEach - we don't want to reset and lose ARIO_TOKEN_PROCESS_ID
  
  describe('Positive Cases - Happy Path', () => {
      it('should complete intent after successful fixed-price order creation via Credit-Notice', async () => {
        // Debug: Check marketplace info to see ARIO token
        const initialInfo = await marketplaceProcess.info();
        console.log('Marketplace ARIO token:', initialInfo.ucm.arioTokenProcess);
        console.log('Expected ARIO token:', TEST_ARIO_PROCESS);
        
        // Step 1: Create intent
        const intentResult = await marketplaceProcess.createIntent({
          action: 'Create-Order',
          orderType: 'fixed',
          swapToken: TEST_ARIO_PROCESS,
          quantity: '1',
          price: '1000000',
          dominantToken: TEST_ANT_PROCESS,
        });

        const intentData = JSON.parse(intentResult.Data);
        const intentId = intentData['Intent-Id'];

        // Verify intent starts as pending
        let intent = await marketplaceProcess.getIntentById(intentId);
        let intentInfo = JSON.parse(intent.Data);
        assert.strictEqual(intentInfo.status, 'pending', 'Intent should start as pending');

        // Step 2: Simulate Credit-Notice from ANT process with all required tags
        // Call ao.message directly instead of through AOProcess.send
        const creditNoticeResult = await marketplaceProcess.process.ao.message({
          process: marketplaceProcess.process.processId,
          tags: [
            { name: 'Action', value: 'Credit-Notice' },
            { name: 'Sender', value: TEST_SENDER },
            { name: 'Quantity', value: '1' },
            { name: 'X-Intent-Id', value: intentId },
            { name: 'X-Order-Action', value: 'Create-Order' },
            { name: 'X-Dominant-Token', value: TEST_ANT_PROCESS },
            { name: 'X-Order-Type', value: 'fixed' },
            { name: 'X-Price', value: '1000000' },
            { name: 'X-Swap-Token', value: TEST_ARIO_PROCESS },
          ],
          data: '',
          signer: TEST_SIGNER,
          From: TEST_ANT_PROCESS, // Simulate message coming from ANT process
        } as any);

        // Debug: Check Credit-Notice result and get the actual result
        console.log('Credit-Notice message ID:', creditNoticeResult);
        const result = await marketplaceProcess.process.ao.result({ 
          message: creditNoticeResult, 
          process: marketplaceProcess.process.processId 
        });
        console.log('Credit-Notice result Messages:', result.Messages?.length || 0);
        console.log('Credit-Notice result Error:', result.Error);
        if (result.Messages && result.Messages.length > 0) {
          // Log ALL messages, not just the first one
          result.Messages.forEach((msg: any, idx: number) => {
            console.log(`\n[Message ${idx + 1}/${result.Messages.length}]`);
            console.log('  Action:', msg.Tags?.find((t: any) => t.name === 'Action')?.value);
            console.log('  Error:', msg.Tags?.find((t: any) => t.name === 'Error')?.value);
            console.log('  Status:', msg.Tags?.find((t: any) => t.name === 'Status')?.value);
            console.log('  Message:', msg.Tags?.find((t: any) => t.name === 'Message')?.value);
            console.log('  Quantity:', msg.Tags?.find((t: any) => t.name === 'Quantity')?.value);
            console.log('  Data:', msg.Data);
          });
        }

        // Debug: Check marketplace state immediately after Credit-Notice
        const infoAfterCreditNotice = await marketplaceProcess.info();
        console.log('Orders after Credit-Notice:', infoAfterCreditNotice.activity.totalOrders);
        console.log('Intents after Credit-Notice:', infoAfterCreditNotice.intents.total);
        
        // Debug: Try to get the intent
        try {
          const intentCheck = await marketplaceProcess.getIntentById(intentId);
          const intentCheckData = JSON.parse(intentCheck.Data);
          console.log('Intent after Credit-Notice - exists: true, status:', intentCheckData.status);
        } catch (e: any) {
          console.log('Intent after Credit-Notice - exists: false, error:', e.message || e.Data);
        }

        // Step 3: Verify intent is completed and pruned
        // Completed intents are removed from the Intents table, so querying them returns an error
        intent = await marketplaceProcess.getIntentById(intentId);
        
        // Check if it's an error response (intent not found - which is expected)
        if (intent.Action === 'Invalid-Get-Intent-By-Id-Notice') {
          // Expected: Intent not found because it was completed and pruned
          const errorMsg = intent.Data;
          assert(
            errorMsg.includes('Intent not found') || errorMsg.includes('not found'),
            `Expected "Intent not found" error, got: ${errorMsg}`
          );
        } else {
          // Intent still exists, parse and check status
          intentInfo = JSON.parse(intent.Data);
          assert.fail(
            `Intent should be completed and pruned, but is still in state: ${intentInfo.status}`
          );
        }

        // Step 4: Verify order was created
        const info = await marketplaceProcess.info();
        assert.strictEqual(info.activity.totalOrders, 1, 'Should have created one order');
        assert.strictEqual(info.activity.listedOrders, 1, 'Order should be listed');

        // Step 5: Verify intent stats reflect completion (intent count = 0 because pruned)
        assert.strictEqual(info.intents.total, 0, 'Completed intents should be pruned');
      });

      // REMOVED: ARIO Credit-Notice orders are no longer supported
      // ARIO must be deposited first, then use internal balance via Create-Order handler
    });

    describe('Negative Cases - Error Handling', () => {
      it('should reject Credit-Notice without X-Intent-Id', async () => {
        const initialInfo = await marketplaceProcess.info();
        const initialOrderCount = initialInfo.activity.totalOrders;

        await marketplaceProcess.process.ao.message({
          process: marketplaceProcess.process.processId,
          tags: [
            { name: 'Action', value: 'Credit-Notice' },
            { name: 'Sender', value: TEST_SENDER },
            { name: 'Quantity', value: '1' },
            // Missing X-Intent-Id
            { name: 'X-Order-Action', value: 'Create-Order' },
            { name: 'X-Dominant-Token', value: TEST_ANT_PROCESS },
          ],
          data: '',
          signer: TEST_SIGNER,
          From: TEST_ANT_PROCESS,
        } as any);

        // Verify no NEW order was created
        const info = await marketplaceProcess.info();
        assert.strictEqual(
          info.activity.totalOrders,
          initialOrderCount,
          'No order should be created without X-Intent-Id'
        );
      });

      it('should reject Credit-Notice with invalid intent ID format', async () => {
        const initialInfo = await marketplaceProcess.info();
        const initialOrderCount = initialInfo.activity.totalOrders;

        await marketplaceProcess.process.ao.message({
          process: marketplaceProcess.process.processId,
          tags: [
            { name: 'Action', value: 'Credit-Notice' },
            { name: 'Sender', value: TEST_SENDER },
            { name: 'Quantity', value: '1' },
            { name: 'X-Intent-Id', value: 'invalid-id-with-letters' }, // Invalid format
            { name: 'X-Order-Action', value: 'Create-Order' },
            { name: 'X-Dominant-Token', value: TEST_ANT_PROCESS },
          ],
          data: '',
          signer: TEST_SIGNER,
          From: TEST_ANT_PROCESS,
        } as any);

        // Verify no NEW order was created
        const info = await marketplaceProcess.info();
        assert.strictEqual(
          info.activity.totalOrders,
          initialOrderCount,
          'No order should be created with invalid intent ID'
        );
      });

      it('should reject Credit-Notice for non-existent intent', async () => {
        const initialInfo = await marketplaceProcess.info();
        const initialOrderCount = initialInfo.activity.totalOrders;

        await marketplaceProcess.process.ao.message({
          process: marketplaceProcess.process.processId,
          tags: [
            { name: 'Action', value: 'Credit-Notice' },
            { name: 'Sender', value: TEST_SENDER },
            { name: 'Quantity', value: '1' },
            { name: 'X-Intent-Id', value: '99999' }, // Non-existent intent
            { name: 'X-Order-Action', value: 'Create-Order' },
            { name: 'X-Dominant-Token', value: TEST_ANT_PROCESS },
          ],
          data: '',
          signer: TEST_SIGNER,
          From: TEST_ANT_PROCESS,
        } as any);

        // Verify no NEW order was created
        const info = await marketplaceProcess.info();
        assert.strictEqual(
          info.activity.totalOrders,
          initialOrderCount,
          'No order should be created for non-existent intent'
        );
      });

      it('should reject Credit-Notice when sender does not match intent initiator', async () => {
        const initialInfo = await marketplaceProcess.info();
        const initialOrderCount = initialInfo.activity.totalOrders;

        // Create intent
        const intentResult = await marketplaceProcess.createIntent({
          action: 'Create-Order',
          orderType: 'fixed',
          swapToken: TEST_ARIO_PROCESS,
          quantity: '1',
          price: '1000000',
          dominantToken: TEST_ANT_PROCESS,
        });

        const intentData = JSON.parse(intentResult.Data);
        const intentId = intentData['Intent-Id'];

        // Try to use the intent with a different sender
        const differentSender = 'different-sender'.padEnd(43, '2');
        await marketplaceProcess.process.ao.message({
          process: marketplaceProcess.process.processId,
          tags: [
            { name: 'Action', value: 'Credit-Notice' },
            { name: 'Sender', value: differentSender }, // Different from intent initiator
            { name: 'Quantity', value: '1' },
            { name: 'X-Intent-Id', value: intentId },
            { name: 'X-Order-Action', value: 'Create-Order' },
            { name: 'X-Dominant-Token', value: TEST_ANT_PROCESS },
          ],
          data: '',
          signer: TEST_SIGNER,
          From: TEST_ANT_PROCESS,
        } as any);

        // Verify intent remains in pending state
        const intent = await marketplaceProcess.getIntentById(intentId);
        const intentInfo = JSON.parse(intent.Data);
        assert.strictEqual(intentInfo.status, 'pending', 'Intent should remain pending on sender mismatch');

        // Verify no NEW order was created
        const info = await marketplaceProcess.info();
        assert.strictEqual(
          info.activity.totalOrders,
          initialOrderCount,
          'No order should be created with sender mismatch'
        );
      });

      it('should reject Credit-Notice without X-Dominant-Token tag', async () => {
        const initialInfo = await marketplaceProcess.info();
        const initialOrderCount = initialInfo.activity.totalOrders;

        const intentResult = await marketplaceProcess.createIntent({
          action: 'Create-Order',
          orderType: 'fixed',
          swapToken: TEST_ARIO_PROCESS,
          quantity: '1',
          price: '1000000',
          dominantToken: TEST_ANT_PROCESS,
        });

        const intentData = JSON.parse(intentResult.Data);
        const intentId = intentData['Intent-Id'];

        await marketplaceProcess.process.ao.message({
          process: marketplaceProcess.process.processId,
          tags: [
            { name: 'Action', value: 'Credit-Notice' },
            { name: 'Sender', value: TEST_SENDER },
            { name: 'Quantity', value: '1' },
            { name: 'X-Intent-Id', value: intentId },
            { name: 'X-Order-Action', value: 'Create-Order' },
            // Missing X-Dominant-Token
          ],
          data: '',
          signer: TEST_SIGNER,
          From: TEST_ANT_PROCESS,
        } as any);

        // Should not process (early return in handler)
        // Intent should remain in pending state
        const intent = await marketplaceProcess.getIntentById(intentId);
        const intentInfo = JSON.parse(intent.Data);
        assert.strictEqual(intentInfo.status, 'pending', 'Intent should remain pending');

        // No NEW order should be created
        const info = await marketplaceProcess.info();
        assert.strictEqual(
          info.activity.totalOrders,
          initialOrderCount,
          'No order should be created'
        );
      });

      it('should reject Credit-Notice when From does not match X-Dominant-Token', async () => {
        const initialInfo = await marketplaceProcess.info();
        const initialOrderCount = initialInfo.activity.totalOrders;

        const intentResult = await marketplaceProcess.createIntent({
          action: 'Create-Order',
          orderType: 'fixed',
          swapToken: TEST_ARIO_PROCESS,
          quantity: '1',
          price: '1000000',
          dominantToken: TEST_ANT_PROCESS,
        });

        const intentData = JSON.parse(intentResult.Data);
        const intentId = intentData['Intent-Id'];

        const wrongProcess = 'wrong-process-id'.padEnd(43, '9');
        await marketplaceProcess.process.ao.message({
          process: marketplaceProcess.process.processId,
          tags: [
            { name: 'Action', value: 'Credit-Notice' },
            { name: 'Sender', value: TEST_SENDER },
            { name: 'Quantity', value: '1' },
            { name: 'X-Intent-Id', value: intentId },
            { name: 'X-Order-Action', value: 'Create-Order' },
            { name: 'X-Dominant-Token', value: TEST_ANT_PROCESS }, // Says ANT
          ],
          data: '',
          signer: TEST_SIGNER,
          From: wrongProcess, // But From is different
        } as any);

        // Should not process (early return)
        const intent = await marketplaceProcess.getIntentById(intentId);
        const intentInfo = JSON.parse(intent.Data);
        assert.strictEqual(intentInfo.status, 'pending', 'Intent should remain pending');

        const info = await marketplaceProcess.info();
        assert.strictEqual(
          info.activity.totalOrders,
          initialOrderCount,
          'No order should be created'
        );
      });
    });
  });

  describe('ANT Intent Resolution', () => {
    describe('Push-ANT-Intent-Resolution', () => {
      it('should trigger ANT state query for valid intent', async () => {
        const intentResult = await marketplaceProcess.createIntent({
          action: 'Create-Order',
          orderType: 'fixed',
          swapToken: TEST_ARIO_PROCESS,
          quantity: '1000',
          price: '500',
        });

        const intentData = JSON.parse(intentResult.Data);
        const intentId = intentData['Intent-Id'];

        const result = await marketplaceProcess.process.send({
          tags: [
            { name: 'Action', value: 'Push-ANT-Intent-Resolution' },
            { name: 'X-Intent-Id', value: intentId },
          ],
          signer: TEST_SIGNER,
        });

        assert(result, 'Result should be defined');
      });

      it('should fail without X-Intent-Id', async () => {
        try {
          await marketplaceProcess.process.send({
            tags: [{ name: 'Action', value: 'Push-ANT-Intent-Resolution' }],
            signer: TEST_SIGNER,
          });
          assert.fail('Should have thrown an error for missing X-Intent-Id');
        } catch (error: any) {
          assert(error.message.includes('X-Intent-Id'), 'Error should mention X-Intent-Id');
        }
      });

      it('should fail for non-existent intent', async () => {
        try {
          await marketplaceProcess.process.send({
            tags: [
              { name: 'Action', value: 'Push-ANT-Intent-Resolution' },
              { name: 'X-Intent-Id', value: '999999' },
            ],
            signer: TEST_SIGNER,
          });
          assert.fail('Should have thrown an error for non-existent intent');
        } catch (error: any) {
          assert(error.message.includes('Intent not found'), 'Error should mention Intent not found');
        }
      });
    });

    describe('State-Notice Handler', () => {
      it('should resolve intent when marketplace owns ANT', async () => {
        const setupResult = await marketplaceProcess.process.send({
          tags: [{ name: 'Action', value: 'Eval' }],
          data: `
            local intents = require('intents')
            ARIOBalances['${TEST_SENDER}'] = {balance = '10000000000', orders = {}}
            local parentIntent = intents.createParentIntent({From = '${TEST_SENDER}', Timestamp = 1000000}, 'Create-Order', {})
            local antId = 'test-ant-process-111111111111111111111111111'
            local childIntent = intents.createChildIntent(parentIntent.intentId, {Timestamp = 1000100}, antId, {})
            return childIntent.intentId
          `,
          signer: TEST_SIGNER,
        });

        const childIntentId = (setupResult as any).result;

        const stateNoticeResult = await marketplaceProcess.process.send({
          tags: [{ name: 'Action', value: 'Eval' }],
          data: `
            local intents = require('intents')
            local json = require('json')
            local msg = {From = 'test-ant-process-111111111111111111111111111', Timestamp = 1000200, Data = json.encode({Owner = ao.id}), Tags = {['X-Intent-Id'] = '${childIntentId}'}}
            intents.stateNoticeHandler(msg)
            local child = intents.getIntentById('${childIntentId}')
            return child and child.status or 'not-found'
          `,
          signer: TEST_SIGNER,
        });

        const childStatus = (stateNoticeResult as any).result;
        assert.strictEqual(childStatus, 'resolved', 'Child intent should be resolved');
      });

      it('should fail when marketplace does not own ANT', async () => {
        const setupResult = await marketplaceProcess.process.send({
          tags: [{ name: 'Action', value: 'Eval' }],
          data: `
            local intents = require('intents')
            ARIOBalances['${TEST_SENDER}'] = {balance = '10000000000', orders = {}}
            local parentIntent = intents.createParentIntent({From = '${TEST_SENDER}', Timestamp = 1000000}, 'Create-Order', {})
            local antId = 'test-ant-process-222222222222222222222222222'
            local childIntent = intents.createChildIntent(parentIntent.intentId, {Timestamp = 1000100}, antId, {})
            return childIntent.intentId
          `,
          signer: TEST_SIGNER,
        });

        const childIntentId = (setupResult as any).result;

        try {
          await marketplaceProcess.process.send({
            tags: [{ name: 'Action', value: 'Eval' }],
            data: `
              local intents = require('intents')
              local json = require('json')
              local msg = {From = 'test-ant-process-222222222222222222222222222', Timestamp = 1000200, Data = json.encode({Owner = 'different-owner-address'}), Tags = {['X-Intent-Id'] = '${childIntentId}'}}
              intents.stateNoticeHandler(msg)
            `,
            signer: TEST_SIGNER,
          });
          assert.fail('Should have thrown error for non-marketplace owner');
        } catch (error: any) {
          assert(error.message.includes('Marketplace does not own this ANT'), 'Error should mention ownership mismatch');
        }
      });

      it('should complete parent when all children resolved', async () => {
        const setupResult = await marketplaceProcess.process.send({
          tags: [{ name: 'Action', value: 'Eval' }],
          data: `
            local intents = require('intents')
            ARIOBalances['${TEST_SENDER}'] = {balance = '10000000000', orders = {}}
            local parentIntent = intents.createParentIntent({From = '${TEST_SENDER}', Timestamp = 1000000}, 'Create-Order', {})
            local ant1 = 'test-ant-1-444444444444444444444444444444'
            local ant2 = 'test-ant-2-555555555555555555555555555555'
            local child1 = intents.createChildIntent(parentIntent.intentId, {Timestamp = 1000100}, ant1, {})
            local child2 = intents.createChildIntent(parentIntent.intentId, {Timestamp = 1000100}, ant2, {})
            return {parentId = parentIntent.intentId, child1Id = child1.intentId, child2Id = child2.intentId}
          `,
          signer: TEST_SIGNER,
        });

        const ids = (setupResult as any).result;

        await marketplaceProcess.process.send({
          tags: [{ name: 'Action', value: 'Eval' }],
          data: `local intents = require('intents'); local json = require('json'); local msg = {From = 'test-ant-1-444444444444444444444444444444', Timestamp = 1000200, Data = json.encode({Owner = ao.id}), Tags = {['X-Intent-Id'] = '${ids.child1Id}'}}; intents.stateNoticeHandler(msg)`,
          signer: TEST_SIGNER,
        });

        await marketplaceProcess.process.send({
          tags: [{ name: 'Action', value: 'Eval' }],
          data: `local intents = require('intents'); local json = require('json'); local msg = {From = 'test-ant-2-555555555555555555555555555555', Timestamp = 1000300, Data = json.encode({Owner = ao.id}), Tags = {['X-Intent-Id'] = '${ids.child2Id}'}}; intents.stateNoticeHandler(msg)`,
          signer: TEST_SIGNER,
        });

        const parentStatus = await marketplaceProcess.process.send({
          tags: [{ name: 'Action', value: 'Eval' }],
          data: `local intents = require('intents'); local parent = intents.getIntentById('${ids.parentId}'); return parent and parent.status or 'not-found'`,
          signer: TEST_SIGNER,
        });

        assert.strictEqual((parentStatus as any).result, 'completed', 'Parent should be completed');
      });
    });
  });
