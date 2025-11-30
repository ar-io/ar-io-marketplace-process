#!/usr/bin/env tsx
/**
 * Background block mining for arlocal
 * Calls /mine endpoint every 3 seconds to help with transaction propagation
 */

const ARLOCAL_URL = 'http://localhost:4000';
const MINE_INTERVAL_MS = 3000; // 3 seconds

async function mineBlock() {
  try {
    const response = await fetch(`${ARLOCAL_URL}/mine`);
    if (response.ok) {
      const result = await response.text();
      console.log(`⛏️  Block mined: ${result}`);
    } else {
      console.log(`⚠️  Mining failed: ${response.status} ${response.statusText}`);
    }
  } catch (error) {
    console.error(`❌ Mining error:`, error instanceof Error ? error.message : String(error));
  }
}

async function main() {
  console.log(`⛏️  Starting automatic block mining every ${MINE_INTERVAL_MS}ms...`);
  console.log(`   Press Ctrl+C to stop\n`);
  
  // Mine immediately on start
  await mineBlock();
  
  // Then mine every interval
  setInterval(mineBlock, MINE_INTERVAL_MS);
}

main().catch(console.error);


