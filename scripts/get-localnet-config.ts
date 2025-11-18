#!/usr/bin/env tsx
/**
 * Extract configuration from the AO localnet after seeding
 * This gets the scheduler ID and module ID that were published to the localnet
 * and saves all transaction IDs to .localnet-state.json
 */

import Arweave from 'arweave';
import { readFileSync, writeFileSync, existsSync } from 'fs';
import { resolve } from 'path';

const LOCALNET_GATEWAY = 'http://localhost:4000';
const LOCALNET_GRAPHQL = 'http://localhost:4000/graphql';

interface GraphQLResponse {
  data: {
    transactions: {
      edges: Array<{
        node: {
          id: string;
          tags: Array<{
            name: string;
            value: string;
          }>;
          owner: {
            address: string;
          };
        };
      }>;
    };
  };
}

async function queryGraphQL(query: string): Promise<GraphQLResponse> {
  const response = await fetch(LOCALNET_GRAPHQL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ query }),
  });

  if (!response.ok) {
    throw new Error(`GraphQL query failed: ${response.statusText}`);
  }

  return await response.json();
}

async function getSchedulerId(): Promise<string | null> {
  // Query for scheduler location transactions
  const query = `
    query {
      transactions(
        tags: [
          { name: "Data-Protocol", values: ["ao"] }
          { name: "Type", values: ["Scheduler-Location"] }
        ]
        sort: HEIGHT_DESC
        first: 1
      ) {
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

  const result = await queryGraphQL(query);
  const edges = result.data.transactions.edges;

  if (edges.length === 0) {
    console.log('⚠️  No scheduler found. Run: pnpm localnet:seed');
    return null;
  }

  const schedulerTx = edges[0].node;
  const urlTag = schedulerTx.tags.find(t => t.name === 'Url');
  
  console.log('✓ Found Scheduler Location transaction:', schedulerTx.id);
  if (urlTag) {
    console.log('  Scheduler URL:', urlTag.value);
  }

  return schedulerTx.id;
}

async function getModuleId(): Promise<string | null> {
  // Query for AOS module transactions
  const query = `
    query {
      transactions(
        tags: [
          { name: "Data-Protocol", values: ["ao"] }
          { name: "Type", values: ["Module"] }
          { name: "Module-Format", values: ["wasm64-unknown-emscripten-draft_2024_02_15"] }
        ]
        sort: HEIGHT_DESC
        first: 1
      ) {
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

  const result = await queryGraphQL(query);
  const edges = result.data.transactions.edges;

  if (edges.length === 0) {
    console.log('⚠️  No AOS module found. Run: pnpm localnet:seed');
    return null;
  }

  const moduleTx = edges[0].node;
  
  console.log('✓ Found AOS Module transaction:', moduleTx.id);
  
  return moduleTx.id;
}

async function checkServices() {
  console.log('\n=== Checking Localnet Services ===\n');

  const services = [
    { name: 'ArLocal Gateway', url: 'http://localhost:4000' },
    { name: 'GraphQL', url: 'http://localhost:4000/graphql' },
    { name: 'MU (Messenger Unit)', url: 'http://localhost:4002' },
    { name: 'SU (Scheduler Unit)', url: 'http://localhost:4003' },
    { name: 'CU (Compute Unit)', url: 'http://localhost:4004' },
  ];

  for (const service of services) {
    try {
      const response = await fetch(service.url, { 
        method: 'GET',
        signal: AbortSignal.timeout(2000),
      });
      console.log(`✓ ${service.name}: ${service.url} (${response.status})`);
    } catch (error) {
      console.log(`✗ ${service.name}: ${service.url} - NOT RUNNING`);
    }
  }
}

async function getAllTransactions(): Promise<any[]> {
  const query = `
    query {
      transactions(
        first: 100
        sort: HEIGHT_DESC
      ) {
        edges {
          node {
            id
            tags {
              name
              value
            }
            owner {
              address
            }
            block {
              height
              timestamp
            }
          }
        }
      }
    }
  `;

  const result = await queryGraphQL(query);
  return result.data.transactions.edges.map(edge => edge.node);
}

interface LocalnetState {
  timestamp: string;
  blockHeight: number;
  configuration: {
    graphqlUrl: string;
    gatewayUrl: string;
    cuUrl: string;
    muUrl: string;
    suUrl: string;
    scheduler: string | null;
    moduleId: string | null;
  };
  transactions: {
    scheduler: string | null;
    module: string | null;
    arMinting: string[];
    other: Array<{
      id: string;
      tags: Array<{ name: string; value: string }>;
      owner: string;
    }>;
  };
}

async function saveLocalnetState(
  schedulerId: string | null,
  moduleId: string | null,
  allTransactions: any[]
): Promise<void> {
  // Categorize transactions
  const arMintingTxs: string[] = [];
  const otherTxs: Array<{
    id: string;
    tags: Array<{ name: string; value: string }>;
    owner: string;
  }> = [];

  for (const tx of allTransactions) {
    // Skip the ones we already identified
    if (tx.id === schedulerId || tx.id === moduleId) {
      continue;
    }

    // Check if it's an AR minting transaction (has Quantity tag)
    const hasQuantity = tx.tags.some((t: any) => t.name === 'Quantity');
    if (hasQuantity) {
      arMintingTxs.push(tx.id);
    } else {
      otherTxs.push({
        id: tx.id,
        tags: tx.tags,
        owner: tx.owner.address,
      });
    }
  }

  // Get current block info
  const infoResponse = await fetch(`${LOCALNET_GATEWAY}/info`);
  const info = await infoResponse.json();

  const state: LocalnetState = {
    timestamp: new Date().toISOString(),
    blockHeight: info.height || 0,
    configuration: {
      graphqlUrl: 'http://localhost:4000/graphql',
      gatewayUrl: 'http://localhost:4000',
      cuUrl: 'http://localhost:4004',
      muUrl: 'http://localhost:4002',
      suUrl: 'http://localhost:4003',
      scheduler: schedulerId,
      moduleId: moduleId,
    },
    transactions: {
      scheduler: schedulerId,
      module: moduleId,
      arMinting: arMintingTxs,
      other: otherTxs,
    },
  };

  const statePath = resolve(process.cwd(), '.localnet-state.json');
  writeFileSync(statePath, JSON.stringify(state, null, 2), 'utf8');
  
  console.log(`\n💾 Saved localnet state to: .localnet-state.json`);
  console.log(`   Transactions tracked: ${allTransactions.length} total`);
  console.log(`   - Scheduler: ${schedulerId ? '1' : '0'}`);
  console.log(`   - Module: ${moduleId ? '1' : '0'}`);
  console.log(`   - AR Minting: ${arMintingTxs.length}`);
  console.log(`   - Other: ${otherTxs.length}`);
}

function loadBootstrapConfig(): any {
  // Look for .ao-localnet.config.json in project root first, 
  // then try the old location for backward compatibility
  const paths = [
    resolve(process.cwd(), '.ao-localnet.config.json'),
    resolve(process.cwd(), '../ao-localnet-archive/.ao-localnet.config.json'),
  ];
  
  for (const configPath of paths) {
    if (existsSync(configPath)) {
      try {
        const config = JSON.parse(readFileSync(configPath, 'utf8'));
        return config.bootstrap || null;
      } catch {
        continue;
      }
    }
  }
  
  return null;
}

async function main() {
  console.log('=== AO Localnet Configuration ===\n');

  // Check if services are running
  await checkServices();

  // Check for bootstrap config
  const bootstrapConfig = loadBootstrapConfig();
  if (bootstrapConfig) {
    console.log('\n=== Bootstrap Info ===\n');
    console.log('Last bootstrap:', bootstrapConfig.lastBootstrap);
    if (bootstrapConfig.wallets?.testWallet) {
      console.log('Test wallet:', bootstrapConfig.wallets.testWallet);
    }
    if (bootstrapConfig.transactions?.testWalletMint?.length > 0) {
      console.log('Minted to:', bootstrapConfig.transactions.testWalletMint.length, 'addresses');
    }
  }

  console.log('\n=== Querying Localnet for Configuration ===\n');

  try {
    const schedulerId = await getSchedulerId();
    const moduleId = await getModuleId();
    
    // Get all transactions for tracking
    const allTransactions = await getAllTransactions();
    console.log(`\n📊 Found ${allTransactions.length} transactions on localnet`);

    console.log('\n=== Configuration for .env ===\n');
    console.log('# AO Localnet URLs');
    console.log('GRAPHQL_URL=http://localhost:4000/graphql');
    console.log('GATEWAY_URL=http://localhost:4000');
    console.log('CU_URL=http://localhost:4004');
    console.log('MU_URL=http://localhost:4002');
    console.log('SU_URL=http://localhost:4003');
    console.log('');
    
    if (schedulerId) {
      console.log(`# Scheduler (from localnet)`);
      console.log(`SCHEDULER=${schedulerId}`);
    } else {
      console.log('# SCHEDULER=<run pnpm localnet:seed first>');
    }
    
    console.log('');
    
    if (moduleId) {
      console.log(`# AOS Module (from localnet)`);
      console.log(`MODULE_ID=${moduleId}`);
    } else {
      console.log('# MODULE_ID=<run pnpm localnet:seed first>');
    }

    console.log('');
    console.log('# Optional: Use a specific wallet');
    console.log('# WALLET_PATH=tests/fixtures/test_wallet.json');
    console.log('');

    if (!schedulerId || !moduleId) {
      console.log('\n⚠️  Some configuration is missing.');
      console.log('   Run: pnpm localnet:seed');
      process.exit(1);
    }

    // Save state file
    await saveLocalnetState(schedulerId, moduleId, allTransactions);

    console.log('\n✓ Localnet is configured and ready!');
    console.log('\n📝 Copy the configuration above to your .env file');
    console.log('   Or run: pnpm localnet:config > .env.local');

  } catch (error) {
    console.error('\n✗ Error querying localnet:', error);
    console.log('\nMake sure the localnet is running:');
    console.log('  pnpm localnet:start');
    console.log('  pnpm localnet:seed');
    process.exit(1);
  }
}

main();

