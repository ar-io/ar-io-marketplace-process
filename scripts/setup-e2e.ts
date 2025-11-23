#!/usr/bin/env tsx
/**
 * Comprehensive E2E test setup script
 * - Validates configuration
 * - Checks localnet health
 * - Optionally spawns processes
 * - Generates test output with detailed diagnostics
 */

import { config } from 'dotenv';
import { existsSync } from 'fs';
import { checkLocalnetHealth, waitForHealthy } from '../tests/utils/localnet_health.js';
import { validateE2EConfig, printValidationResults } from '../tests/utils/config_validator.js';

// Load environment variables
config();

interface SetupOptions {
  validateOnly?: boolean;
  skipHealthCheck?: boolean;
  cleanStart?: boolean;
  spawnProcesses?: boolean;
}

async function main() {
  console.log('╔════════════════════════════════════════════════════════════════╗');
  console.log('║                                                                ║');
  console.log('║            AR.IO Marketplace E2E Test Setup                    ║');
  console.log('║                                                                ║');
  console.log('╚════════════════════════════════════════════════════════════════╝');
  console.log('');

  // Parse command line arguments
  const args = process.argv.slice(2);
  const options: SetupOptions = {
    validateOnly: args.includes('--validate-only'),
    skipHealthCheck: args.includes('--skip-health'),
    cleanStart: args.includes('--clean'),
    spawnProcesses: args.includes('--spawn'),
  };

  // Step 1: Validate Configuration
  console.log('📋 Step 1: Validating Configuration\n');
  const validation = validateE2EConfig();
  printValidationResults(validation);

  if (!validation.valid) {
    console.error('❌ Setup failed: Configuration is invalid\n');
    console.log('💡 To fix this:');
    console.log('   1. Ensure localnet is running: pnpm localnet:start');
    console.log('   2. Check your .env file has all required variables');
    console.log('   3. Run: pnpm localnet:config');
    console.log('');
    process.exit(1);
  }

  if (options.validateOnly) {
    console.log('✅ Validation complete (--validate-only flag set)\n');
    process.exit(0);
  }

  // Step 2: Check Localnet Health
  if (!options.skipHealthCheck) {
    console.log('🏥 Step 2: Checking Localnet Health\n');
    
    try {
      const health = await checkLocalnetHealth();
      
      if (health.overall === 'unhealthy') {
        console.error('\n❌ Localnet is unhealthy!\n');
        console.log('💡 To fix this:');
        console.log('   1. Start localnet: pnpm localnet:start');
        console.log('   2. Check Docker containers: docker ps');
        console.log('   3. View logs: docker compose logs');
        console.log('');
        process.exit(1);
      }
      
      if (health.overall === 'degraded') {
        console.log('\n⚠️  Localnet is degraded but functional');
        console.log('   Some non-critical services are down\n');
      }
      
    } catch (error) {
      console.error('\n❌ Health check failed:', error instanceof Error ? error.message : String(error));
      console.log('\n💡 Ensure localnet is running: pnpm localnet:start\n');
      process.exit(1);
    }
  } else {
    console.log('⏭️  Step 2: Skipping health check (--skip-health flag set)\n');
  }

  // Step 3: Handle Clean Start
  if (options.cleanStart) {
    console.log('🧹 Step 3: Clean Start\n');
    
    const configPath = 'e2e-test.json';
    if (existsSync(configPath)) {
      const fs = await import('fs');
      fs.unlinkSync(configPath);
      console.log(`   ✓ Deleted ${configPath}`);
    } else {
      console.log(`   ℹ️  No ${configPath} found (already clean)`);
    }
    console.log('');
  }

  // Step 4: Check Process Configuration
  console.log('🔧 Step 4: Process Configuration\n');
  
  const configPath = 'e2e-test.json';
  if (existsSync(configPath)) {
    console.log('   ✓ Found existing process configuration (e2e-test.json)');
    console.log('   ℹ️  Tests will reuse existing processes');
    console.log('   💡 To spawn new processes, run: pnpm test:e2e:clean');
    console.log('');
  } else {
    console.log('   ℹ️  No existing process configuration found');
    console.log('   ℹ️  Tests will spawn new processes automatically');
    console.log('');
  }

  if (options.spawnProcesses) {
    console.log('🚀 Step 5: Spawning Processes\n');
    console.log('   This will be handled by the test suite...\n');
    // Process spawning will be done by getOrSpawnProcesses() in the tests
  }

  // Final Summary
  console.log('╔════════════════════════════════════════════════════════════════╗');
  console.log('║                                                                ║');
  console.log('║                     ✅ Setup Complete!                          ║');
  console.log('║                                                                ║');
  console.log('╚════════════════════════════════════════════════════════════════╝');
  console.log('');
  console.log('🚀 Ready to run tests:\n');
  console.log('   • Run all e2e tests:    pnpm test:e2e');
  console.log('   • Run smoke test only:  npx tsx --test tests/e2e/smoke-test.ts');
  console.log('   • Clean and restart:    pnpm test:e2e:clean');
  console.log('');
  console.log('📊 Test output will be saved to:');
  console.log('   • test-output.log (detailed log)');
  console.log('');
}

main().catch((error) => {
  console.error('\n❌ Setup failed:', error);
  process.exit(1);
});

