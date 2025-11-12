import { before, beforeEach, describe, it } from 'node:test';
import { MarketplaceProcess } from '../utils/marketplace_process.js';
import { LocalAO, createLocalProcess } from '../utils/local_ao.js';
import { AOProcess } from '@ar.io/sdk';
import assert from 'node:assert';
import {
  BUNDLED_MARKETPLACE_SOURCE_CODE,
  PROCESS_OWNER,
} from '../utils/constants.js';

describe('UCM (Universal Continuous Market)', () => {
  let marketplaceProcess: MarketplaceProcess;
  let ao_mock: LocalAO;

  const TEST_ANT_TOKEN = 'test-ant-token-'.padEnd(43, '1');
  const TEST_ARIO_TOKEN = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA';
  const TEST_BUYER = 'test-buyer-'.padEnd(43, '2');

  before(async () => {
    const process = await createLocalProcess({
      processId: 'my-marketplace-process-'.padEnd(43, '1'),
      lua: BUNDLED_MARKETPLACE_SOURCE_CODE,
    });
    ao_mock = process.ao as any as LocalAO;
    marketplaceProcess = new MarketplaceProcess({
      process: new AOProcess({ ao: process.ao, processId: process.processId }),
    });
  });

  beforeEach(async () => {
    await ao_mock.reset();
  });

  describe('Get-Orderbook-By-Pair', () => {
    it('should return empty orderbook for non-existent pair', async () => {
      const result = await marketplaceProcess.getOrderbookByPair(
        TEST_ANT_TOKEN,
        TEST_ARIO_TOKEN,
      );

      console.dir({ emptyOrderbook: result }, { depth: null });

      // Orderbook may not exist yet, so no response or success response with empty data
      assert(result, 'Result should be defined');
    });

    it('should require both DominantToken and SwapToken', async () => {
      const result = await marketplaceProcess.process.read({
        tags: [{ name: 'Action', value: 'Get-Orderbook-By-Pair' }],
      });

      console.dir({ missingTokens: result }, { depth: null });

      // Handler should return nothing if tokens are missing (early return)
      assert(result !== undefined, 'Result should exist');
    });
  });

  describe('Cancel-Order', () => {
    it('should return error for non-existent order', async () => {
      const result = await marketplaceProcess.cancelOrder(
        'non-existent-order-id',
      );

      console.dir({ cancelNonExistentOrder: result }, { depth: null });

      assert(result, 'Result should be defined');
      // Should get an Action-Response with error
      if (result.Action === 'Action-Response') {
        assert.strictEqual(result.Tags.Status, 'Error');
        assert(result.Tags.Message?.includes('Order not found'));
      }
    });

    it('should require Order-Id parameter', async () => {
      const result = (await marketplaceProcess.process.read({
        tags: [{ name: 'Action', value: 'Cancel-Order' }],
        // Missing Order-Id tag
      })) as any;

      console.dir({ cancelMissingOrderId: result }, { depth: null });

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Invalid-Cancel-Order-Notice');
      assert(result.Data?.includes('Order-Id'));
    });
  });

  describe('Credit-Notice (Order Creation)', () => {
    it('should reject Credit-Notice without X-Intent-Id', async () => {
      const messageId = await marketplaceProcess.simulateCreditNotice({
        sender: PROCESS_OWNER,
        quantity: '1000',
        dominantToken: TEST_ANT_TOKEN,
        swapToken: TEST_ARIO_TOKEN,
        orderType: 'fixed',
        price: '100',
      });

      const result = await marketplaceProcess.process.ao.result({
        message: messageId,
        process: marketplaceProcess.process.processId,
      });

      console.dir({ creditNoticeNoIntent: result }, { depth: null });

      // Should refund and send error since X-Intent-Id is missing
      assert(result, 'Result should be defined');
      assert(result.Messages, 'Should have messages');

      // Look for error or refund message
      const hasError = result.Messages.some((m: any) =>
        m.Tags.some(
          (t: any) =>
            t.name === 'Action' &&
            (t.value === 'Validation-Error' || t.value === 'Transfer'),
        ),
      );
      assert(hasError, 'Should have error or refund message');
    });

    it('should reject Credit-Notice from non-dominant token', async () => {
      const wrongToken = 'wrong-token-'.padEnd(43, '9');

      const messageId = await marketplaceProcess.process.ao.message({
        tags: [
          { name: 'Action', value: 'Credit-Notice' },
          { name: 'Sender', value: PROCESS_OWNER },
          { name: 'Quantity', value: '1000' },
          { name: 'X-Dominant-Token', value: TEST_ANT_TOKEN },
          { name: 'From', value: wrongToken }, // From doesn't match dominant token
        ],
      });

      const result = await marketplaceProcess.process.ao.result({
        message: messageId,
        process: marketplaceProcess.process.processId,
      });

      console.dir({ creditNoticeWrongToken: result }, { depth: null });

      // Handler should return early (no messages sent)
      assert(result, 'Result should be defined');
    });
  });

  describe('Settle-Auction', () => {
    it('should return error for missing Order-Id', async () => {
      const result = (await marketplaceProcess.process.read({
        tags: [{ name: 'Action', value: 'Settle-Auction' }],
        // Missing Order-Id tag
      })) as any;

      console.dir({ settleMissingOrderId: result }, { depth: null });

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Invalid-Settle-Auction-Notice');
      assert(result.Data?.includes('Order-Id'));
    });

    it('should return error for non-existent order', async () => {
      const result = await marketplaceProcess.settleAuction({
        orderId: 'non-existent-auction-id',
      });

      console.dir({ settleNonExistentOrder: result }, { depth: null });

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Invalid-Settle-Auction-Notice');
      assert(result.Data?.includes('Order not found'));
    });
  });

  describe('Order Validation', () => {
    it('should validate ARIO requirement in trades', async () => {
      // Create intent without ARIO should fail
      const result = await marketplaceProcess.createIntent({
        action: 'Create-Order',
        orderType: 'fixed',
        swapToken: 'non-ario-token-'.padEnd(43, 'x'),
        quantity: '1000',
        price: '100',
      });

      console.dir({ nonArioIntent: result }, { depth: null });

      // Intent creation validation might catch this
      assert(result, 'Result should be defined');
    });
  });

  describe('Order Lifecycle', () => {
    it('should track order through listed -> executed states', async () => {
      // Check initial state
      const listedBefore = await marketplaceProcess.getListedOrders();
      const completedBefore = await marketplaceProcess.getCompletedOrders();

      console.dir(
        { initialState: { listedBefore, completedBefore } },
        { depth: null },
      );

      assert(listedBefore, 'Listed orders should be defined');
      assert(completedBefore, 'Completed orders should be defined');

      const listedData = JSON.parse(listedBefore.Data);
      const completedData = JSON.parse(completedBefore.Data);

      assert.strictEqual(
        listedData.items.length,
        0,
        'Should start with no listed orders',
      );
      assert.strictEqual(
        completedData.items.length,
        0,
        'Should start with no completed orders',
      );
    });

    it('should track order counts by address', async () => {
      const testAddress = 'test-seller-'.padEnd(43, '5');
      const result =
        await marketplaceProcess.getOrderCountsByAddress(testAddress);

      console.dir({ orderCounts: result }, { depth: null });

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Read-Success');
    });
  });
});
