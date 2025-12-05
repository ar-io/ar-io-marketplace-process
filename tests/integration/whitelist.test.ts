import assert from 'node:assert';
import { before, beforeEach, describe, it } from 'node:test';
import { AOProcess } from '@ar.io/sdk';
import {
  BUNDLED_MARKETPLACE_SOURCE_CODE,
  PROCESS_OWNER,
  STUB_TIMESTAMP,
  TEST_ANT_MODULE_NOT_WHITELISTED,
  TEST_ANT_MODULE_WHITELISTED,
  TEST_ANT_PROCESS,
  TEST_ARIO_PROCESS,
  TEST_SENDER,
  TEST_SIGNER,
} from '../utils/constants.js';
import { LocalAO, createLocalProcess } from '../utils/local_ao.js';
import { MarketplaceProcess } from '../utils/marketplace_process.js';

describe('Module Whitelist Management', () => {
  let marketplaceProcess: MarketplaceProcess;
  let ao_mock: LocalAO;

  before(async () => {
    const luaWithTestConfig =
      `ARIO_TOKEN_PROCESS_ID = "${TEST_ARIO_PROCESS}"\n` +
      BUNDLED_MARKETPLACE_SOURCE_CODE;

    const process = await createLocalProcess({
      processId: 'my-marketplace-process-'.padEnd(43, '1'),
      lua: luaWithTestConfig,
    });
    ao_mock = process.ao as any as LocalAO;
    marketplaceProcess = new MarketplaceProcess({
      process: new AOProcess({ ao: process.ao, processId: process.processId }),
      signer: TEST_SIGNER,
    });

    // Deposit ARIO for listing fees (intents cost 1 ARIO)
    await marketplaceProcess.depositArio(
      '100000000000',
      TEST_ARIO_PROCESS,
      TEST_SENDER,
    );
  });

  beforeEach(async () => {
    // Reset WhitelistedModules before each test
    await ao_mock.message({
      processId: marketplaceProcess.process.processId,
      data: `WhitelistedModules = {}`,
      tags: [
        { name: 'Action', value: 'Eval' },
        { name: 'From', value: PROCESS_OWNER },
        { name: 'Owner', value: PROCESS_OWNER },
      ],
    });
  });

  describe('Whitelist-Module Action', () => {
    it('should add a module to the whitelist', async () => {
      await marketplaceProcess.process.send({
        tags: [
          { name: 'Action', value: 'Whitelist-Module' },
          { name: 'Module-Id', value: TEST_ANT_MODULE_WHITELISTED },
        ],
        signer: TEST_SIGNER,
      });

      // Verify by checking Info endpoint
      const infoResult = await marketplaceProcess.info();
      assert.ok(
        Array.isArray(infoResult.whitelistedModules),
        'whitelistedModules should be an array',
      );
      assert.ok(
        infoResult.whitelistedModules.includes(TEST_ANT_MODULE_WHITELISTED),
        'Module should be in whitelistedModules array',
      );
    });

    it('should reject adding an already whitelisted module', async () => {
      // First add the module
      await marketplaceProcess.process.send({
        tags: [
          { name: 'Action', value: 'Whitelist-Module' },
          { name: 'Module-Id', value: TEST_ANT_MODULE_WHITELISTED },
        ],
        signer: TEST_SIGNER,
      });

      // Try to add it again
      try {
        await marketplaceProcess.process.send({
          tags: [
            { name: 'Action', value: 'Whitelist-Module' },
            { name: 'Module-Id', value: TEST_ANT_MODULE_WHITELISTED },
          ],
          signer: TEST_SIGNER,
        });
        assert.fail('Should have thrown an error for duplicate module');
      } catch (error: any) {
        assert.ok(
          error.message.includes('already whitelisted'),
          'Error should mention already whitelisted: ' + error.message,
        );
      }
    });

    it('should reject adding an invalid module ID', async () => {
      try {
        await marketplaceProcess.process.send({
          tags: [
            { name: 'Action', value: 'Whitelist-Module' },
            { name: 'Module-Id', value: 'invalid-id' },
          ],
          signer: TEST_SIGNER,
        });
        assert.fail('Should have thrown an error for invalid module ID');
      } catch (error: any) {
        assert.ok(
          error.message.includes('Invalid module ID'),
          'Error should mention invalid module ID: ' + error.message,
        );
      }
    });

    it('should reject when Module-Id tag is missing', async () => {
      try {
        await marketplaceProcess.process.send({
          tags: [{ name: 'Action', value: 'Whitelist-Module' }],
          signer: TEST_SIGNER,
        });
        assert.fail('Should have thrown an error for missing Module-Id');
      } catch (error: any) {
        assert.ok(
          error.message.includes('Module-Id is required'),
          'Error should mention Module-Id is required: ' + error.message,
        );
      }
    });
  });

  describe('Unwhitelist-Module Action', () => {
    it('should remove a module from the whitelist', async () => {
      // First add the module
      await marketplaceProcess.process.send({
        tags: [
          { name: 'Action', value: 'Whitelist-Module' },
          { name: 'Module-Id', value: TEST_ANT_MODULE_WHITELISTED },
        ],
        signer: TEST_SIGNER,
      });

      // Now remove it
      await marketplaceProcess.process.send({
        tags: [
          { name: 'Action', value: 'Unwhitelist-Module' },
          { name: 'Module-Id', value: TEST_ANT_MODULE_WHITELISTED },
        ],
        signer: TEST_SIGNER,
      });

      // Verify by checking Info endpoint
      const infoResult = await marketplaceProcess.info();
      assert.ok(
        Array.isArray(infoResult.whitelistedModules),
        'whitelistedModules should be an array',
      );
      assert.ok(
        !infoResult.whitelistedModules.includes(TEST_ANT_MODULE_WHITELISTED),
        'Module should not be in whitelistedModules array',
      );
    });

    it('should reject removing a module that is not whitelisted', async () => {
      try {
        await marketplaceProcess.process.send({
          tags: [
            { name: 'Action', value: 'Unwhitelist-Module' },
            { name: 'Module-Id', value: TEST_ANT_MODULE_WHITELISTED },
          ],
          signer: TEST_SIGNER,
        });
        assert.fail('Should have thrown an error for non-whitelisted module');
      } catch (error: any) {
        assert.ok(
          error.message.includes('not whitelisted'),
          'Error should mention not whitelisted: ' + error.message,
        );
      }
    });

    it('should reject removing an invalid module ID', async () => {
      try {
        await marketplaceProcess.process.send({
          tags: [
            { name: 'Action', value: 'Unwhitelist-Module' },
            { name: 'Module-Id', value: 'invalid-id' },
          ],
          signer: TEST_SIGNER,
        });
        assert.fail('Should have thrown an error for invalid module ID');
      } catch (error: any) {
        assert.ok(
          error.message.includes('Invalid module ID'),
          'Error should mention invalid module ID: ' + error.message,
        );
      }
    });

    it('should reject when Module-Id tag is missing', async () => {
      try {
        await marketplaceProcess.process.send({
          tags: [{ name: 'Action', value: 'Unwhitelist-Module' }],
          signer: TEST_SIGNER,
        });
        assert.fail('Should have thrown an error for missing Module-Id');
      } catch (error: any) {
        assert.ok(
          error.message.includes('Module-Id is required'),
          'Error should mention Module-Id is required: ' + error.message,
        );
      }
    });
  });

  describe('Whitelist Enforcement', () => {
    it('should reject Credit-Notice from non-whitelisted module', async () => {
      // Create intent
      const intentResult = await marketplaceProcess.createIntent({
        antId: TEST_ANT_PROCESS,
        orderType: 'fixed',
        price: '1000000000000',
        quantity: '1',
        expirationTime: (STUB_TIMESTAMP + 3600000).toString(),
      });

      const intentId = JSON.parse(intentResult.Data)['Intent-Id'];
      assert.ok(intentId, 'Intent should be created');

      // Try to send Credit-Notice with non-whitelisted module (no modules whitelisted yet)
      const creditMsg = await marketplaceProcess.process.ao.message({
        process: marketplaceProcess.process.processId,
        tags: [
          { name: 'Action', value: 'Credit-Notice' },
          { name: 'Sender', value: TEST_SENDER },
          { name: 'Quantity', value: '1' },
          { name: 'X-Intent-Id', value: intentId },
          { name: 'X-Order-Action', value: 'Create-Order' },
          { name: 'From-Module', value: TEST_ANT_MODULE_NOT_WHITELISTED }, // Not whitelisted!
        ],
        data: '',
        signer: TEST_SIGNER,
        From: TEST_ANT_PROCESS,
      } as any);

      const creditResult = await marketplaceProcess.process.ao.result({
        message: creditMsg,
        process: marketplaceProcess.process.processId,
      });

      // Should have Intent-Resolved message with failed status
      const resolvedMsg = creditResult.Messages?.find((m: any) =>
        m.Tags?.find(
          (t: any) => t.name === 'Action' && t.value === 'Intent-Resolved',
        ),
      );

      assert(resolvedMsg, 'Should have Intent-Resolved message');

      const statusTag = resolvedMsg.Tags?.find((t: any) => t.name === 'Status');
      assert.strictEqual(
        statusTag?.value,
        'failed',
        'Intent should have failed status',
      );

      const reasonTag = resolvedMsg.Tags?.find(
        (t: any) => t.name === 'Failure-Reason',
      );
      assert(
        reasonTag?.value?.includes('whitelisted'),
        'Failure reason should mention whitelist: ' + reasonTag?.value,
      );
    });

    it('should accept Credit-Notice from whitelisted module', async () => {
      // Add module to whitelist
      await marketplaceProcess.process.send({
        tags: [
          { name: 'Action', value: 'Whitelist-Module' },
          { name: 'Module-Id', value: TEST_ANT_MODULE_WHITELISTED },
        ],
        signer: TEST_SIGNER,
      });

      // Create intent
      const intentResult = await marketplaceProcess.createIntent({
        antId: TEST_ANT_PROCESS,
        orderType: 'fixed',
        price: '1000000000000',
        quantity: '1',
        expirationTime: (STUB_TIMESTAMP + 3600000).toString(),
      });

      const intentId = JSON.parse(intentResult.Data)['Intent-Id'];
      assert.ok(intentId, 'Intent should be created');

      // Send Credit-Notice with whitelisted module
      const creditMsg = await marketplaceProcess.process.ao.message({
        process: marketplaceProcess.process.processId,
        tags: [
          { name: 'Action', value: 'Credit-Notice' },
          { name: 'Sender', value: TEST_SENDER },
          { name: 'Quantity', value: '1' },
          { name: 'X-Intent-Id', value: intentId },
          { name: 'X-Order-Action', value: 'Create-Order' },
          { name: 'From-Module', value: TEST_ANT_MODULE_WHITELISTED }, // Whitelisted!
        ],
        data: '',
        signer: TEST_SIGNER,
        From: TEST_ANT_PROCESS,
      } as any);

      const creditResult = await marketplaceProcess.process.ao.result({
        message: creditMsg,
        process: marketplaceProcess.process.processId,
      });

      // Should have Intent-Resolved message with completed status
      const resolvedMsg = creditResult.Messages?.find((m: any) =>
        m.Tags?.find(
          (t: any) => t.name === 'Action' && t.value === 'Intent-Resolved',
        ),
      );

      assert(resolvedMsg, 'Should have Intent-Resolved message');

      const statusTag = resolvedMsg.Tags?.find((t: any) => t.name === 'Status');
      assert.strictEqual(
        statusTag?.value,
        'completed',
        'Intent should be completed',
      );
    });

    it('should reject Credit-Notice after module is removed from whitelist', async () => {
      // Add module to whitelist
      await marketplaceProcess.process.send({
        tags: [
          { name: 'Action', value: 'Whitelist-Module' },
          { name: 'Module-Id', value: TEST_ANT_MODULE_WHITELISTED },
        ],
        signer: TEST_SIGNER,
      });

      // Remove module from whitelist
      await marketplaceProcess.process.send({
        tags: [
          { name: 'Action', value: 'Unwhitelist-Module' },
          { name: 'Module-Id', value: TEST_ANT_MODULE_WHITELISTED },
        ],
        signer: TEST_SIGNER,
      });

      // Create intent
      const intentResult = await marketplaceProcess.createIntent({
        antId: TEST_ANT_PROCESS,
        orderType: 'fixed',
        price: '1000000000000',
        quantity: '1',
        expirationTime: (STUB_TIMESTAMP + 3600000).toString(),
      });

      const intentId = JSON.parse(intentResult.Data)['Intent-Id'];
      assert.ok(intentId, 'Intent should be created');

      // Try to send Credit-Notice with module that was just removed
      const creditMsg = await marketplaceProcess.process.ao.message({
        process: marketplaceProcess.process.processId,
        tags: [
          { name: 'Action', value: 'Credit-Notice' },
          { name: 'Sender', value: TEST_SENDER },
          { name: 'Quantity', value: '1' },
          { name: 'X-Intent-Id', value: intentId },
          { name: 'X-Order-Action', value: 'Create-Order' },
          { name: 'From-Module', value: TEST_ANT_MODULE_WHITELISTED }, // No longer whitelisted!
        ],
        data: '',
        signer: TEST_SIGNER,
        From: TEST_ANT_PROCESS,
      } as any);

      const creditResult = await marketplaceProcess.process.ao.result({
        message: creditMsg,
        process: marketplaceProcess.process.processId,
      });

      // Should have Intent-Resolved message with failed status
      const resolvedMsg = creditResult.Messages?.find((m: any) =>
        m.Tags?.find(
          (t: any) => t.name === 'Action' && t.value === 'Intent-Resolved',
        ),
      );

      assert(resolvedMsg, 'Should have Intent-Resolved message');

      const statusTag = resolvedMsg.Tags?.find((t: any) => t.name === 'Status');
      assert.strictEqual(
        statusTag?.value,
        'failed',
        'Intent should have failed after module removed',
      );
    });
  });

  describe('Multiple Module Management', () => {
    it('should manage multiple modules in whitelist', async () => {
      // Add first module
      await marketplaceProcess.process.send({
        tags: [
          { name: 'Action', value: 'Whitelist-Module' },
          { name: 'Module-Id', value: TEST_ANT_MODULE_WHITELISTED },
        ],
        signer: TEST_SIGNER,
      });

      // Add second module
      await marketplaceProcess.process.send({
        tags: [
          { name: 'Action', value: 'Whitelist-Module' },
          { name: 'Module-Id', value: TEST_ANT_MODULE_NOT_WHITELISTED },
        ],
        signer: TEST_SIGNER,
      });

      // Verify both are in whitelist
      const infoResult = await marketplaceProcess.info();
      assert.ok(
        infoResult.whitelistedModules.includes(TEST_ANT_MODULE_WHITELISTED),
        'First module should be whitelisted',
      );
      assert.ok(
        infoResult.whitelistedModules.includes(TEST_ANT_MODULE_NOT_WHITELISTED),
        'Second module should be whitelisted',
      );

      // Remove first module
      await marketplaceProcess.process.send({
        tags: [
          { name: 'Action', value: 'Unwhitelist-Module' },
          { name: 'Module-Id', value: TEST_ANT_MODULE_WHITELISTED },
        ],
        signer: TEST_SIGNER,
      });

      // Verify only second module remains
      const infoResult2 = await marketplaceProcess.info();
      assert.ok(
        !infoResult2.whitelistedModules.includes(TEST_ANT_MODULE_WHITELISTED),
        'First module should be removed',
      );
      assert.ok(
        infoResult2.whitelistedModules.includes(
          TEST_ANT_MODULE_NOT_WHITELISTED,
        ),
        'Second module should still be whitelisted',
      );
    });
  });
});
