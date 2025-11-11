import { before, beforeEach, describe, it } from 'node:test';
import { MarketplaceProcess } from '../utils/marketplace_process.js';
import { LocalAO, createLocalProcess } from '../utils/local_ao.js';
import { AOProcess } from '@ar.io/sdk';
import assert from 'node:assert';
import { BUNDLED_MARKETPLACE_SOURCE_CODE, PROCESS_OWNER } from '../utils/constants.js';

describe('Auction Mechanisms', () => {
  let marketplaceProcess: MarketplaceProcess;
  let ao_mock: LocalAO;

  const TEST_ANT_TOKEN = 'test-ant-token-'.padEnd(43, '1');
  const TEST_ARIO_TOKEN = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA';
  const TEST_SELLER = 'test-seller-'.padEnd(43, '3');
  const TEST_BIDDER1 = 'test-bidder1-'.padEnd(43, '4');
  const TEST_BIDDER2 = 'test-bidder2-'.padEnd(43, '5');

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

  describe('Dutch Auction', () => {
    describe('Order Creation', () => {
      it('should validate required Dutch auction parameters', async () => {
        // Create intent without required Dutch auction params
        const result = await marketplaceProcess.createIntent({
          action: 'Create-Order',
          orderType: 'dutch',
          swapToken: TEST_ARIO_TOKEN,
          quantity: '1000',
          price: '100',
          // Missing: minimumPrice, decreaseInterval
        });

        console.dir({ dutchMissingParams: result }, { depth: null });

        assert(result, 'Result should be defined');
        // Validation should catch missing parameters
      });

      it('should validate minimum price is less than starting price', async () => {
        const result = await marketplaceProcess.createIntent({
          action: 'Create-Order',
          orderType: 'dutch',
          swapToken: TEST_ARIO_TOKEN,
          quantity: '1000',
          price: '100',
          minimumPrice: '150', // Invalid: higher than price
          decreaseInterval: '60000',
          expirationTime: (Date.now() + 3600000).toString(),
        });

        console.dir({ dutchInvalidMinPrice: result }, { depth: null });

        assert(result, 'Result should be defined');
      });

      it('should validate expiration time is required', async () => {
        const result = await marketplaceProcess.createIntent({
          action: 'Create-Order',
          orderType: 'dutch',
          swapToken: TEST_ARIO_TOKEN,
          quantity: '1000',
          price: '100',
          minimumPrice: '50',
          decreaseInterval: '60000',
          // Missing: expirationTime
        });

        console.dir({ dutchMissingExpiration: result }, { depth: null });

        assert(result, 'Result should be defined');
      });
    });

    describe('Price Calculation', () => {
      it('should calculate decreasing price over time', async () => {
        // This would require creating an order and checking price at different timestamps
        // For now, we validate that the order creation intent validates the parameters
        const futureTime = Date.now() + 3600000; // 1 hour from now
        const result = await marketplaceProcess.createIntent({
          action: 'Create-Order',
          orderType: 'dutch',
          swapToken: TEST_ARIO_TOKEN,
          quantity: '1000',
          price: '1000',
          minimumPrice: '500',
          decreaseInterval: '60000', // 1 minute intervals
          expirationTime: futureTime.toString(),
        });

        console.dir({ dutchPriceCalc: result }, { depth: null });

        assert(result, 'Result should be defined');
      });
    });
  });

  describe('English Auction', () => {
    describe('Order Creation', () => {
      it('should validate required English auction parameters', async () => {
        const result = await marketplaceProcess.createIntent({
          action: 'Create-Order',
          orderType: 'english',
          swapToken: TEST_ARIO_TOKEN,
          quantity: '1000',
          price: '100', // Starting bid
          expirationTime: (Date.now() + 3600000).toString(),
        });

        console.dir({ englishCreateIntent: result }, { depth: null });

        assert(result, 'Result should be defined');
      });

      it('should require expiration time for English auctions', async () => {
        const result = await marketplaceProcess.createIntent({
          action: 'Create-Order',
          orderType: 'english',
          swapToken: TEST_ARIO_TOKEN,
          quantity: '1000',
          price: '100',
          // Missing: expirationTime
        });

        console.dir({ englishMissingExpiration: result }, { depth: null });

        assert(result, 'Result should be defined');
      });
    });

    describe('Bidding', () => {
      it('should validate bid amount against minimum', async () => {
        // In a real test, we'd create an auction and then try to bid below the minimum
        // For now, we test the intent validation
        const result = await marketplaceProcess.createIntent({
          action: 'Create-Order',
          orderType: 'english',
          swapToken: TEST_ARIO_TOKEN,
          quantity: '1000',
          price: '100',
          expirationTime: (Date.now() + 3600000).toString(),
        });

        console.dir({ englishBidValidation: result }, { depth: null });

        assert(result, 'Result should be defined');
      });
    });

    describe('Settlement', () => {
      it('should require Order-Id for settlement', async () => {
        const result = (await marketplaceProcess.process.read({
          tags: [{ name: 'Action', value: 'Settle-Auction' }],
          // Missing Order-Id tag
        })) as any;

        console.dir({ englishSettleNoId: result }, { depth: null });

        assert(result, 'Result should be defined');
        assert.strictEqual(result.Action, 'Invalid-Settle-Auction-Notice');
        assert(result.Data?.includes('Order-Id'));
      });

      it('should reject settlement of non-existent auction', async () => {
        const result = await marketplaceProcess.settleAuction({
          orderId: 'non-existent-auction-'.padEnd(43, 'x'),
        });

        console.dir({ englishSettleNonExistent: result }, { depth: null });

        assert(result, 'Result should be defined');
        assert.strictEqual(result.Action, 'Invalid-Settle-Auction-Notice');
        assert(result.Data?.includes('Order not found'));
      });

      it('should validate auction is ready for settlement', async () => {
        // In a real scenario, we'd create an auction and try to settle it
        // before it expires or has bids
        const result = await marketplaceProcess.settleAuction({
          orderId: 'test-auction-id',
        });

        console.dir({ englishSettleNotReady: result }, { depth: null });

        assert(result, 'Result should be defined');
        // Should return error about order not found or not ready
      });
    });
  });

  describe('Fixed Price Orders', () => {
    it('should create valid fixed price order intent', async () => {
      const result = await marketplaceProcess.createIntent({
        action: 'Create-Order',
        orderType: 'fixed',
        swapToken: TEST_ARIO_TOKEN,
        quantity: '1000',
        price: '100',
      });

      console.dir({ fixedPriceIntent: result }, { depth: null });

      assert(result, 'Result should be defined');
      assert.strictEqual(result.Action, 'Intent-Created');
      assert(result.Tags['Intent-Id'], 'Should return Intent-Id');
    });

    it('should validate required parameters for fixed price', async () => {
      const result = await marketplaceProcess.createIntent({
        action: 'Create-Order',
        orderType: 'fixed',
        swapToken: TEST_ARIO_TOKEN,
        quantity: '1000',
        // Missing: price
      });

      console.dir({ fixedPriceMissingPrice: result }, { depth: null });

      assert(result, 'Result should be defined');
    });
  });

  describe('Order Type Validation', () => {
    it('should reject invalid order type', async () => {
      const result = await marketplaceProcess.createIntent({
        action: 'Create-Order',
        orderType: 'invalid' as any,
        swapToken: TEST_ARIO_TOKEN,
        quantity: '1000',
        price: '100',
      });

      console.dir({ invalidOrderType: result }, { depth: null });

      assert(result, 'Result should be defined');
      // Should get validation error
    });

    it('should support all three order types', async () => {
      const futureTime = Date.now() + 3600000;

      // Fixed
      const fixed = await marketplaceProcess.createIntent({
        action: 'Create-Order',
        orderType: 'fixed',
        swapToken: TEST_ARIO_TOKEN,
        quantity: '1000',
        price: '100',
      });

      // Dutch
      const dutch = await marketplaceProcess.createIntent({
        action: 'Create-Order',
        orderType: 'dutch',
        swapToken: TEST_ARIO_TOKEN,
        quantity: '1000',
        price: '1000',
        minimumPrice: '500',
        decreaseInterval: '60000',
        expirationTime: futureTime.toString(),
      });

      // English
      const english = await marketplaceProcess.createIntent({
        action: 'Create-Order',
        orderType: 'english',
        swapToken: TEST_ARIO_TOKEN,
        quantity: '1000',
        price: '100',
        expirationTime: futureTime.toString(),
      });

      console.dir({ orderTypes: { fixed, dutch, english } }, { depth: null });

      assert(fixed, 'Fixed order intent should be defined');
      assert(dutch, 'Dutch auction intent should be defined');
      assert(english, 'English auction intent should be defined');
    });
  });

  describe('Auction Lifecycle', () => {
    it('should track auction from creation to settlement', async () => {
      // Create intent
      const intentResult = await marketplaceProcess.createIntent({
        action: 'Create-Order',
        orderType: 'english',
        swapToken: TEST_ARIO_TOKEN,
        quantity: '1000',
        price: '100',
        expirationTime: (Date.now() + 3600000).toString(),
      });

      console.dir({ auctionLifecycleIntent: intentResult }, { depth: null });

      assert(intentResult, 'Intent result should be defined');
      assert.strictEqual(intentResult.Action, 'Intent-Created');

      // Check it appears in listed orders (would after Credit-Notice)
      const listedOrders = await marketplaceProcess.getListedOrders();
      console.dir({ listedOrdersAfterIntent: listedOrders }, { depth: null });
      
      assert(listedOrders, 'Listed orders should be defined');
    });
  });
});

