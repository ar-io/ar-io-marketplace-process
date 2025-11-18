#!/usr/bin/env tsx
/**
 * Bootstrap the AO localnet for marketplace development
 * - Runs standard AO seeding (scheduler, module)
 * - Mints AR to test wallets
 * - Tracks all transaction IDs in .ao-localnet.config.json
 * - Optionally spawns marketplace and ARIO processes
 */

import { execSync } from 'child_process';
import { readFileSync, writeFileSync, existsSync } from 'fs';
import { resolve } from 'path';
import Arweave from 'arweave';

// Look for .ao-localnet.config.json in project root first,
// then try the old location for backward compatibility
function getConfigPath(): string {
  const paths = [
    resolve(process.cwd(), '.ao-localnet.config.json'),
    resolve(process.cwd(), '../ao-localnet-archive/.ao-localnet.config.json'),
  ];
  
  for (const path of paths) {
    if (existsSync(path)) {
      return path;
    }
  }
  
  // Default to project root
  return paths[0];
}

const CONFIG_PATH = getConfigPath();
const TEST_WALLET_PATH = resolve(process.cwd(), 'tests/fixtures/test_wallet.json');
const LOCALNET_GATEWAY = 'http://localhost:4000';

interface BootstrapConfig {
  transactions: {
    scheduler?: string;
    module?: string;
    testWalletMint?: string[];
    marketplace?: string;
    ario?: string;
  };
  wallets: {
    testWallet?: string;
  };
  lastBootstrap: string;
}

async function getAddressFromJWK(jwkPath: string): Promise<string> {
  const arweave = new Arweave({
    protocol: 'http',
    host: 'localhost',
    port: 4000,
  });
  
  const jwk = JSON.parse(readFileSync(jwkPath, 'utf8'));
  return await arweave.wallets.getAddress(jwk);
}

async function mintToAddress(address: string, amount: string = '1000000000000'): Promise<void> {
  console.log(`  Minting ${amount} winstons to ${address.slice(0, 12)}...`);
  
  const response = await fetch(`${LOCALNET_GATEWAY}/mint/${address}/${amount}`);
  const result = await response.text();
  
  if (response.ok) {
    console.log(`  ✓ Minted: ${result} winstons`);
  } else {
    console.log(`  ✗ Failed to mint: ${result}`);
  }
}

async function queryTransaction(txId: string): Promise<any> {
  const query = `
    query {
      transaction(id: "${txId}") {
        id
        tags {
          name
          value
        }
        owner {
          address
        }
      }
    }
  `;

  const response = await fetch(`${LOCALNET_GATEWAY}/graphql`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  });

  const result = await response.json();
  return result.data?.transaction;
}

async function getAllTransactions(): Promise<any[]> {
  const query = `
    query {
      transactions(first: 100, sort: HEIGHT_DESC) {
        edges {
          node {
            id
            tags {
              name
              value
            }
          }
        }
      }
    }
  `;

  const response = await fetch(`${LOCALNET_GATEWAY}/graphql`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  });

  const result = await response.json();
  return result.data?.transactions?.edges?.map((e: any) => e.node) || [];
}

function updateConfig(bootstrapData: BootstrapConfig): void {
  const config = JSON.parse(readFileSync(CONFIG_PATH, 'utf8'));
  
  // Add bootstrap section
  config.bootstrap = bootstrapData;
  
  writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2), 'utf8');
  console.log('\n✓ Updated .ao-localnet.config.json with bootstrap data');
}

async function main() {
  console.log('=== Bootstrapping AO Localnet for Marketplace ===\n');

  // Step 1: Run standard AO localnet seeding
  console.log('Step 1: Running standard AO localnet seed...\n');
  try {
    execSync('npx ao-localnet seed', {
      stdio: 'inherit',
      cwd: process.cwd(),
    });
  } catch (error) {
    console.error('✗ Failed to run standard seed');
    process.exit(1);
  }

  console.log('\nStep 2: Querying seeded transactions...\n');
  
  // Wait a bit for transactions to be indexed
  await new Promise(resolve => setTimeout(resolve, 2000));
  
  const allTransactions = await getAllTransactions();
  console.log(`Found ${allTransactions.length} transactions`);

  // Find scheduler and module
  const schedulerTx = allTransactions.find((tx: any) =>
    tx.tags.some((t: any) => t.name === 'Type' && t.value === 'Scheduler-Location')
  );
  const moduleTx = allTransactions.find((tx: any) =>
    tx.tags.some((t: any) => t.name === 'Type' && t.value === 'Module')
  );

  console.log('✓ Scheduler:', schedulerTx?.id || 'NOT FOUND');
  console.log('✓ Module:', moduleTx?.id || 'NOT FOUND');

  // Step 3: Mint to test wallet
  console.log('\nStep 3: Minting AR to test wallet...\n');
  
  if (!existsSync(TEST_WALLET_PATH)) {
    console.log('⚠️  Test wallet not found at:', TEST_WALLET_PATH);
    console.log('   Skipping test wallet minting');
  }

  const testWalletAddress = existsSync(TEST_WALLET_PATH)
    ? await getAddressFromJWK(TEST_WALLET_PATH)
    : null;

  if (testWalletAddress) {
    console.log(`Test wallet address: ${testWalletAddress}`);
    await mintToAddress(testWalletAddress, '100000000000000'); // 100 AR
    
    // Mine a block to confirm
    console.log('\n  Mining block...');
    await fetch(`${LOCALNET_GATEWAY}/mine/1`);
    console.log('  ✓ Block mined');
  }

  // Step 4: Update config with bootstrap data
  console.log('\nStep 4: Saving bootstrap data to config...\n');

  const bootstrapData: BootstrapConfig = {
    transactions: {
      scheduler: schedulerTx?.id,
      module: moduleTx?.id,
      testWalletMint: testWalletAddress ? [testWalletAddress] : [],
    },
    wallets: {
      testWallet: testWalletAddress || undefined,
    },
    lastBootstrap: new Date().toISOString(),
  };

  updateConfig(bootstrapData);

  // Step 5: Display configuration
  console.log('\n=== Bootstrap Complete! ===\n');
  console.log('Configuration:');
  console.log('  MU:        http://localhost:4002');
  console.log('  CU:        http://localhost:4004');
  console.log('  SU:        http://localhost:4003');
  console.log(`  Scheduler: ${schedulerTx?.id || 'NOT FOUND'}`);
  console.log(`  Module:    ${moduleTx?.id || 'NOT FOUND'}`);
  if (testWalletAddress) {
    console.log(`  Test Wallet: ${testWalletAddress}`);
  }

  console.log('\n📝 Next steps:');
  console.log('   1. Run: pnpm localnet:config');
  console.log('   2. Copy the output to your .env file');
  console.log('   3. Run your e2e tests!');
  console.log('');
}

main().catch(error => {
  console.error('Bootstrap failed:', error);
  process.exit(1);
});

