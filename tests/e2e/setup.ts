/**
 * Global E2E Test Setup
 * 
 * Runs once before all E2E tests to ensure ao-localnet is ready.
 * 
 * This setup:
 * 1. Checks if ao-localnet is configured, started, and seeded
 * 2. Automatically configures/starts/seeds if needed
 * 3. Ensures all services are healthy before tests run
 */

import { setupLocalnet } from '../utils/ao_localnet_manager.js';

// Run setup before all tests
console.log('\n' + '='.repeat(60));
console.log('E2E Test Suite - Global Setup');
console.log('='.repeat(60) + '\n');

try {
  await setupLocalnet();
} catch (error) {
  console.error('\n❌ Failed to setup ao-localnet:', error);
  console.error('\nPlease ensure Docker is running and try again.\n');
  process.exit(1);
}

console.log('='.repeat(60));
console.log('Setup complete - ready to run tests');
console.log('='.repeat(60) + '\n');

