import { createDataItemSigner } from '@permaweb/aoconnect';
import { getAoInstance, getAosModule, getScheduler, createAoSigner as createLocalnetSigner } from '../tests/utils/ao_localnet_config.js';
import fs from 'fs';

async function testSigner() {
  const wallet = JSON.parse(fs.readFileSync('tests/fixtures/wallets/localnet_wallet.json', 'utf8'));
  
  console.log('\n🧪 Test 1: Using createDataItemSigner from @permaweb/aoconnect');
  const signer1 = createDataItemSigner(wallet);
  
  console.log('\n🧪 Test 2: Using createAoSigner from ao-localnet');
  const signer2 = createLocalnetSigner();
  
  const ao = getAoInstance();
  const moduleId = getAosModule();
  const scheduler = getScheduler();

  console.log('✅ Signer1 type:', typeof signer1);
  console.log('✅ Signer2 type:', typeof signer2);

  console.log('\n🔍 Test 1: Attempting ao.spawn with signer1 (aoconnect)...');
  try {
    const processId1 = await ao.spawn({
      module: moduleId,
      scheduler: scheduler,
      signer: signer1,
      tags: [{ name: 'Name', value: 'Test Process 1' }],
    });
    console.log('✅ Process 1 spawned:', processId1);
  } catch (err: any) {
    console.error('❌ Spawn error:', err.message);
  }

  console.log('\n🔍 Test 2: Attempting ao.spawn with signer2 (ao-localnet)...');
  try {
    const processId2 = await ao.spawn({
      module: moduleId,
      scheduler: scheduler,
      signer: signer2,
      tags: [{ name: 'Name', value: 'Test Process 2' }],
    });
    console.log('✅ Process 2 spawned:', processId2);
  } catch (err: any) {
    console.error('❌ Spawn error:', err.message);
  }
}

testSigner();

