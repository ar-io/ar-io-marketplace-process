import { before, beforeEach, describe, it } from 'node:test';
import { MarketplaceProcess } from '../utils/marketplace_process.js';
import { LocalAO, createLocalProcess } from '../utils/local_ao.js';
import { AOProcess } from '@ar.io/sdk';
import assert from 'node:assert';
import {
  BUNDLED_MARKETPLACE_SOURCE_CODE,
  TEST_SIGNER,
} from '../utils/constants.js';

describe('Info', () => {
  let marketplaceProcess: MarketplaceProcess;
  let ao_mock: LocalAO;

  // create a new process and mock before the tests
  before(async () => {
    const process = await createLocalProcess({
      processId: 'my-marketplace-process-'.padEnd(43, '1'),
      lua: BUNDLED_MARKETPLACE_SOURCE_CODE,
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
  });

  it('should return the info with correct structure', async () => {
    const info = await marketplaceProcess.info();

    // Validate top-level structure
    assert(info, 'Info should be defined');
    assert.strictEqual(typeof info.name, 'string', 'Name should be a string');
    assert.strictEqual(
      typeof info.processId,
      'string',
      'ProcessId should be a string',
    );

    // Validate activity info
    assert(info.activity, 'Activity should be defined');
    assert.strictEqual(
      typeof info.activity.totalOrders,
      'number',
      'totalOrders should be a number',
    );
    assert.strictEqual(
      typeof info.activity.activeOrders,
      'number',
      'activeOrders should be a number',
    );
    assert.strictEqual(
      typeof info.activity.readyForSettlement,
      'number',
      'readyForSettlement should be a number',
    );
    assert.strictEqual(
      typeof info.activity.executedOrders,
      'number',
      'executedOrders should be a number',
    );
    assert.strictEqual(
      typeof info.activity.cancelledOrders,
      'number',
      'cancelledOrders should be a number',
    );
    assert.strictEqual(
      typeof info.activity.expiredOrders,
      'number',
      'expiredOrders should be a number',
    );
    assert.strictEqual(
      typeof info.activity.listedOrders,
      'number',
      'listedOrders should be a number',
    );

    // Validate intents info
    assert(info.intents, 'Intents should be defined');
    assert.strictEqual(
      typeof info.intents.total,
      'number',
      'intents.total should be a number',
    );
    assert(info.intents.byStatus, 'intents.byStatus should be defined');
    assert(info.intents.byType, 'intents.byType should be defined');
    assert(info.intents.byAction, 'intents.byAction should be defined');

    // Validate UCM info
    assert(info.ucm, 'UCM should be defined');
    assert.strictEqual(
      typeof info.ucm.totalPairs,
      'number',
      'totalPairs should be a number',
    );
    assert.strictEqual(
      typeof info.ucm.accruedFees,
      'string',
      'accruedFees should be a string',
    );
    assert.strictEqual(
      typeof info.ucm.arioTokenProcess,
      'string',
      'arioTokenProcess should be a string',
    );

    // Verify initial state values
    assert.strictEqual(
      info.activity.totalOrders,
      0,
      'totalOrders should be 0 initially',
    );
    assert.strictEqual(
      info.intents.total,
      0,
      'intents.total should be 0 initially',
    );
    assert.strictEqual(
      info.ucm.totalPairs,
      0,
      'totalPairs should be 0 initially',
    );
    assert.strictEqual(
      info.ucm.accruedFees,
      '0',
      'accruedFees should be "0" initially',
    );
  });
});
