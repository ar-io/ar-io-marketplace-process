#!/usr/bin/env tsx

/**
 * Test script to verify ao-localnet SDK integration
 */

import {
  getBootstrapInfo,
  waitForAllServices,
  getHealthStatus,
  getContainerLogs,
} from 'ao-localnet';

async function main() {
  console.log('🔍 Testing ao-localnet SDK Integration\n');

  // Test 1: Check service health
  console.log('1️⃣ Checking service health...');
  const healthy = await waitForAllServices(10000);
  
  if (!healthy) {
    console.error('❌ Services not healthy!');
    const health = await getHealthStatus();
    health.forEach(h => {
      if (!h.healthy) {
        console.error(`   ${h.service}: ${h.status}`);
      }
    });
    process.exit(1);
  }
  
  console.log('✅ All services healthy!\n');

  // Test 2: Get bootstrap info
  console.log('2️⃣ Getting bootstrap info from SDK...');
  const info = await getBootstrapInfo();
  
  console.log('📦 Bootstrap Information:');
  console.log(`   Scheduler: ${info.scheduler}`);
  console.log(`   Scheduler Location: ${info.schedulerLocation}`);
  console.log(`   AOS Module: ${info.aosModule}`);
  console.log(`   Authority (MU): ${info.authority}`);
  console.log('\n📡 Service URLs:');
  console.log(`   Gateway: ${info.urls.gateway}`);
  console.log(`   MU: ${info.urls.mu}`);
  console.log(`   CU: ${info.urls.cu}`);
  console.log(`   SU: ${info.urls.su}`);

  // Test 3: Show recent MU logs
  console.log('\n3️⃣ Recent MU logs (last 10 lines):');
  const muLogs = await getContainerLogs('mu', 10);
  console.log(muLogs);

  console.log('\n✅ SDK integration test complete!');
  console.log('\n💡 You can now use these exports in your tests without .env:');
  console.log('   import { getAoInstance, getScheduler, getAosModule, getAuthority } from "ao-localnet";');
}

main().catch(console.error);

