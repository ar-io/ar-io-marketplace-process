#!/usr/bin/env tsx

/**
 * Test script to verify ao-localnet SDK integration
 */

import {
  getUrls,
  getScheduler,
  getAosModule,
  getAuthority,
  getAoInstance
} from '../tests/utils/ao_localnet_config.js';

async function main() {
  console.log('🔍 Testing ao-localnet Config Integration\n');

  // Test 1: Get bootstrap info
  console.log('1️⃣ Getting bootstrap info from config...');
  const scheduler = getScheduler();
  const aosModule = getAosModule();
  const urls = getUrls();
  
  console.log('📦 Bootstrap Information:');
  console.log(`   Scheduler: ${scheduler}`);
  console.log(`   AOS Module: ${aosModule}`);
  console.log('\n📡 Service URLs:');
  console.log(`   Gateway: ${urls.gateway}`);
  console.log(`   MU: ${urls.mu}`);
  console.log(`   CU: ${urls.cu}`);
  console.log(`   SU: ${urls.su}`);
  console.log(`   GraphQL: ${urls.graphql}`);

  // Test 2: Get AO instance
  console.log('\n2️⃣ Creating AO instance...');
  const ao = getAoInstance();
  console.log('✅ AO instance created successfully!');

  console.log('\n✅ Config integration test complete!');
  console.log('\n💡 You can now use these exports in your tests:');
  console.log('   import { getAoInstance, getScheduler, getAosModule, getAuthority } from "./ao_localnet_config.js";');
}

main().catch(console.error);

