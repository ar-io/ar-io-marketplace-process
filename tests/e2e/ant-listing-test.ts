import { describe, it, before } from 'node:test';
import assert from 'node:assert';
import { MarketplaceProcess } from '../utils/marketplace_process.js';
import { getOrSpawnProcesses } from '../utils/process_manager.js';
import { ANT, AOProcess } from '@ar.io/sdk';
import { connect } from '@permaweb/aoconnect';
import { TEST_SIGNER } from '../utils/constants.js';

/**
 * Minimal test to debug ANT listing Credit-Notice issue
 */

describe('ANT Listing Debug Test', { timeout: 900_000 }, () => {
  let marketplaceProcess: MarketplaceProcess;
  let arioProcessId: string;
  let marketplaceProcessId: string;

  before(async () => {
    console.log('========================================');
    console.log('ANT Listing Debug Test');
    console.log('========================================');

    const result = await getOrSpawnProcesses();
    marketplaceProcess = result.marketplaceProcess;
    arioProcessId = result.arioProcessId;
    marketplaceProcessId = result.marketplaceProcessId;

    console.log('Test environment ready:');
    console.log('  Marketplace:', marketplaceProcessId);
    console.log('  ARIO:', arioProcessId);
  });

  it('should create an ANT listing with proper initialization', async () => {
    // Spawn ANT with initialization wait
    console.log('\n=== Spawning ANT ===');
    
    // Use SDK for configuration
    const { getAoInstance, getScheduler, getAuthorityAddress, getAntModuleId } = await import('../utils/constants.js');
    const { loadProcessConfig } = await import('../utils/process_manager.js');
    
    const ao = getAoInstance();
    const scheduler = getScheduler();
    const authority = await getAuthorityAddress();
    const antModule = await getAntModuleId(); // ANT-specific WASM module
    
    // Get ANT Registry ID from the spawned processes
    const config = loadProcessConfig();
    if (!config) {
      throw new Error('No process config found! Run getOrSpawnProcesses first.');
    }
    
    // Use ANT.spawn from the SDK - returns processId directly
    const antProcessId = await ANT.spawn({
      ao,
      signer: TEST_SIGNER,
      scheduler,
      authority,
      module: antModule,
      antRegistryId: config.antRegistryProcessId,
    });
    console.log('✓ ANT spawned:', antProcessId);
    
    // Wait for ANT to be ready on localnet (gateway propagation)
    console.log('Waiting 3s for ANT to propagate...');
    await new Promise(resolve => setTimeout(resolve, 3000));
    
    // Initialize ANT with AOProcess (passing ao instance)
    const ant = ANT.init({
      process: new AOProcess({ ao, processId: antProcessId }),
      signer: TEST_SIGNER,
    });
    try {
      const info = await ant.getInfo();
      console.log('✓ ANT responsive:', info.Name || 'unnamed');
    } catch (e) {
      console.log('ANT info check failed (may be normal for fresh spawn):', e instanceof Error ? e.message : String(e));
    }

    // Get initial marketplace state
    console.log('\n=== Creating Listing ===');
    const initialInfo = await marketplaceProcess.info();
    console.log('Initial orders:', initialInfo.activity.totalOrders);
    console.log('Initial intents:', initialInfo.intents.total);

    // List the ANT
    const listingPrice = '1000000'; // 1 ARIO
    const listingStartTime = Date.now();
    
    console.log(`Listing at ${new Date().toISOString()}`);
    const result = await marketplaceProcess.listAntForFixedPrice(
      antProcessId,
      listingPrice,
      arioProcessId,
      undefined, // no logger
    );
    
    console.log('✓ Transfer sent:', result.txId);
    console.log('✓ Intent created:', result.intentId);
    console.log(`✓ Listing initiated at ${new Date().toISOString()} (${((Date.now() - listingStartTime)/1000).toFixed(1)}s since start)`);

    // Poll for order creation (should be much faster now!)
    console.log('\n=== Waiting for Order Creation ===');
    const startTime = Date.now();
    const timeout = 60_000; // 60 seconds
    let orderCreated = false;
    
    while (Date.now() - startTime < timeout) {
      await new Promise(resolve => setTimeout(resolve, 5000)); // Check every 5s
      
      const currentInfo = await marketplaceProcess.info();
      const elapsed = ((Date.now() - startTime) / 1000).toFixed(0);
      console.log(`[${elapsed}s] Orders: ${currentInfo.activity.totalOrders}, Intents: ${currentInfo.intents.total}`);
      
      if (currentInfo.activity.totalOrders > initialInfo.activity.totalOrders) {
        orderCreated = true;
        const orderCreatedTime = Date.now();
        console.log(`✓ Order created at ${new Date().toISOString()}!`);
        console.log(`  Time since listing: ${((orderCreatedTime - listingStartTime)/1000).toFixed(1)}s`);
        break;
      }
    }

    assert(orderCreated, 'Order should have been created within 1 minute');

    // Verify order exists
    const orders = await marketplaceProcess.getOrdersByStatus('listed');
    const ordersData = JSON.parse(orders.Data);
    const ourOrder = ordersData.items.find((o: any) => o.dominantToken === antProcessId);
    
    assert(ourOrder, 'Should find our ANT in listed orders');
    assert.strictEqual(ourOrder.price, listingPrice, 'Order price should match');
    
    console.log('\n✓ Test passed! Order created successfully');
    console.log('  Order ID:', ourOrder.id);
    console.log('  Price:', ourOrder.price);
  });
});

