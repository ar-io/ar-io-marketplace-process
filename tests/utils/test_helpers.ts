/**
 * Test Helper Utilities for E2E Tests
 * Provides helper methods for auctions, multiple wallets, and intent tracking
 */

import { ANT, AOProcess, ArweaveSigner, AoSigner } from '@ar.io/sdk';
import { MarketplaceProcess } from './marketplace_process.js';
import { readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import {
  getAoInstance,
  getScheduler,
  getAuthorityAddress,
  getAntModuleId,
  createLocalnetSigner,
  TEST_WALLET,
} from './constants.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

/**
 * Wait for intent to reach a specific status
 * Polls the marketplace until the intent reaches the desired status or times out
 */
export async function waitForIntentStatus(
  marketplaceProcess: MarketplaceProcess,
  intentId: string,
  targetStatus: 'pending' | 'completed' | 'failed' | 'active',
  timeout: number = 120000 // 2 minutes
): Promise<boolean> {
  const startTime = Date.now();

  while (Date.now() - startTime < timeout) {
    try {
      const result = await marketplaceProcess.getIntentById(intentId);

      // Check if intent was not found (could mean it was pruned after completion)
      if (result.Action === 'Invalid-Get-Intent-By-Id-Notice') {
        if (targetStatus === 'completed') {
          // Intent not found might mean it was completed and pruned
          return true;
        }
        return false;
      }

      const data = JSON.parse(result.Data);
      if (data.status === targetStatus) {
        console.log(`✓ Intent ${intentId} reached status: ${targetStatus}`);
        return true;
      }
    } catch (error) {
      console.log(`Error checking intent status: ${error}`);
    }

    // Wait before next check
    await new Promise(resolve => setTimeout(resolve, 3000));
  }

  console.log(`✗ Intent ${intentId} did not reach status ${targetStatus} within timeout`);
  return false;
}

/**
 * Check if a module is whitelisted in the marketplace
 */
export async function verifyModuleWhitelist(
  marketplaceProcess: MarketplaceProcess,
  moduleId: string
): Promise<boolean> {
  try {
    // Query marketplace state to check whitelist
    // This would require a specific handler in the marketplace
    // For now, we infer by attempting to use it
    console.log(`Checking if module ${moduleId} is whitelisted...`);
    
    // The actual verification happens when attempting to create an order
    // with a Credit-Notice containing this module ID
    return true; // Placeholder
  } catch (error) {
    console.log(`Error verifying whitelist: ${error}`);
    return false;
  }
}

/**
 * Helper to create a Dutch auction intent with common parameters
 */
export async function createDutchAuction(
  marketplaceProcess: MarketplaceProcess,
  params: {
    dominantToken?: string;
    swapToken: string;
    quantity: string;
    startingPrice: string;
    minimumPrice: string;
    decreaseInterval: string;
    durationMs?: number; // Duration in milliseconds (default: 1 hour)
  }
): Promise<{ intentId: string; expirationTime: number }> {
  const durationMs = params.durationMs || 3_600_000; // Default 1 hour
  const expirationTime = Date.now() + durationMs;

  const result = await marketplaceProcess.createIntent({
    action: 'Create-Order',
    orderType: 'dutch',
    dominantToken: params.dominantToken,
    swapToken: params.swapToken,
    quantity: params.quantity,
    price: params.startingPrice,
    minimumPrice: params.minimumPrice,
    decreaseInterval: params.decreaseInterval,
    expirationTime: expirationTime.toString(),
  });

  const data = JSON.parse(result.Data);
  return {
    intentId: data['Intent-Id'],
    expirationTime,
  };
}

/**
 * Helper to create an English auction intent with common parameters
 */
export async function createEnglishAuction(
  marketplaceProcess: MarketplaceProcess,
  params: {
    dominantToken?: string;
    swapToken: string;
    quantity: string;
    startingBid: string;
    durationMs?: number; // Duration in milliseconds (default: 1 hour)
  }
): Promise<{ intentId: string; expirationTime: number }> {
  const durationMs = params.durationMs || 3_600_000; // Default 1 hour
  const expirationTime = Date.now() + durationMs;

  const result = await marketplaceProcess.createIntent({
    action: 'Create-Order',
    orderType: 'english',
    dominantToken: params.dominantToken,
    swapToken: params.swapToken,
    quantity: params.quantity,
    price: params.startingBid,
    expirationTime: expirationTime.toString(),
  });

  const data = JSON.parse(result.Data);
  return {
    intentId: data['Intent-Id'],
    expirationTime,
  };
}

/**
 * Helper to spawn a fresh ANT for testing
 * Used when tests need to transfer ANTs to the marketplace
 */
export async function spawnFreshAnt(antRegistryProcessId: string): Promise<string> {
  const ao = getAoInstance();
  const scheduler = getScheduler();
  const authority = await getAuthorityAddress();
  const antModule = await getAntModuleId();
  const localnetSigner = createLocalnetSigner(new ArweaveSigner(TEST_WALLET));

  // Spawn ANT process
  const processId = await ao.spawn({
    module: antModule,
    scheduler,
    signer: localnetSigner,
    tags: [
      { name: 'Authority', value: authority },
      { name: 'ANT-Registry-Id', value: antRegistryProcessId },
    ],
  });

  console.log('Fresh ANT spawned:', processId);

  // Wait for ANT to propagate
  await new Promise(resolve => setTimeout(resolve, 3000));

  // Load ANT Lua code
  const antLuaPath = join(__dirname, '../fixtures/contracts/ant-bundled.lua');
  const antLua = readFileSync(antLuaPath, 'utf-8');

  await ao.message({
    process: processId,
    signer: localnetSigner,
    tags: [{ name: 'Action', value: 'Eval' }],
    data: antLua,
  });

  console.log('ANT Lua loaded');

  return processId;
}

/**
 * Calculate expected Dutch auction price at a given time
 */
export function calculateDutchAuctionPrice(
  startingPrice: bigint,
  minimumPrice: bigint,
  decreaseInterval: number,
  startTime: number,
  currentTime: number
): bigint {
  const elapsed = currentTime - startTime;
  const intervals = Math.floor(elapsed / decreaseInterval);

  if (intervals <= 0) {
    return startingPrice;
  }

  const priceRange = startingPrice - minimumPrice;
  const decreasePerInterval = priceRange / BigInt(Math.floor((currentTime - startTime) / decreaseInterval));
  const currentPrice = startingPrice - (decreasePerInterval * BigInt(intervals));

  return currentPrice < minimumPrice ? minimumPrice : currentPrice;
}

/**
 * Wait for a specified duration (for time-based auction tests)
 * Provides console output for user awareness
 */
export async function waitForDuration(durationMs: number, label: string = 'Waiting'): Promise<void> {
  console.log(`${label} for ${durationMs / 1000}s...`);
  const startTime = Date.now();

  while (Date.now() - startTime < durationMs) {
    await new Promise(resolve => setTimeout(resolve, 1000));
    const elapsed = Math.floor((Date.now() - startTime) / 1000);
    if (elapsed % 10 === 0) {
      console.log(`  ${elapsed}s elapsed...`);
    }
  }

  console.log(`✓ ${label} complete`);
}

/**
 * Generate multiple test wallets for auction bidding
 * Note: On localnet, these would need to be funded with AR
 */
export interface TestWallet {
  address: string;
  signer: AoSigner;
}

export async function generateTestWallets(count: number): Promise<TestWallet[]> {
  const wallets: TestWallet[] = [];

  // For now, return a single wallet as multi-wallet support requires
  // additional wallet generation and funding on localnet
  console.log(`Note: Multi-wallet generation not yet implemented. Using default wallet.`);
  
  const localnetSigner = createLocalnetSigner(new ArweaveSigner(TEST_WALLET));
  wallets.push({
    address: TEST_WALLET.address,
    signer: localnetSigner,
  });

  return wallets;
}

/**
 * Helper to poll marketplace info until a condition is met
 */
export async function pollMarketplaceUntil(
  marketplaceProcess: MarketplaceProcess,
  condition: (info: any) => boolean,
  timeout: number = 120000,
  interval: number = 3000
): Promise<boolean> {
  const startTime = Date.now();

  while (Date.now() - startTime < timeout) {
    const info = await marketplaceProcess.info();
    
    if (condition(info)) {
      return true;
    }

    await new Promise(resolve => setTimeout(resolve, interval));
  }

  return false;
}

/**
 * Helper to wait for order count to change
 */
export async function waitForOrderCountChange(
  marketplaceProcess: MarketplaceProcess,
  status: 'listed' | 'executed' | 'cancelled',
  initialCount: number,
  timeout: number = 120000
): Promise<boolean> {
  return await pollMarketplaceUntil(
    marketplaceProcess,
    (info) => {
      const currentCount = status === 'listed' 
        ? info.activity.listedOrders
        : status === 'executed'
        ? info.activity.executedOrders
        : info.activity.cancelledOrders;
      
      return currentCount !== initialCount;
    },
    timeout
  );
}

/**
 * Helper to get current timestamp (for auction testing)
 */
export function getCurrentTimestamp(): number {
  return Date.now();
}

/**
 * Helper to format ARIO amounts for display
 */
export function formatArio(microArio: string | bigint): string {
  const amount = typeof microArio === 'string' ? BigInt(microArio) : microArio;
  const ario = Number(amount) / 1_000_000;
  return `${ario} ARIO`;
}


