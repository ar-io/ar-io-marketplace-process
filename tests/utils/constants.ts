import { ArweaveSigner, createAoSigner } from '@ar.io/sdk';
import { createDataItemSigner } from '@permaweb/aoconnect';
import { 
  getUrls, 
  getScheduler, 
  getAosModule, 
  getAuthority, 
  getAoInstance,
  createAoSigner as createLocalnetSigner,
  loadConfig,
  getAoWallet
} from 'ao-localnet';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import type {
  AoLoaderOptions,
  DefaultHandleOptions,
  MessageTag,
} from './types.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export const AOS_WASM: Buffer = fs.readFileSync(
  path.join(
    __dirname,
    '../fixtures/modules/aos-cbn0KKrBZH7hdNkNokuXLtGryrWM--PjSTBqIzw9Kkk.wasm',
  ),
);
export const BUNDLED_MARKETPLACE_SOURCE_CODE: string = fs.readFileSync(
  path.join(__dirname, '../../dist/aos-bundled.lua'),
  'utf-8',
);

export const PROCESS_ID: string = ''.padEnd(43, '0');
export const PROCESS_OWNER: string = ''.padEnd(43, '1');
export const STUB_ADDRESS: string = ''.padEnd(43, '2');
export const STUB_OPERATOR_ADDRESS: string = ''.padEnd(43, 'E');
export const STUB_TIMESTAMP: number = 21600000; // 01-01-1970 00:00:00
export const STUB_BLOCK_HEIGHT: number = 1;
export const STUB_PROCESS_ID: string = 'process-id-stub-'.padEnd(43, '0');
export const STUB_MESSAGE_ID: string = ''.padEnd(43, 'm');
export const STUB_HASH_CHAIN: string =
  'NGU1fq_ssL9m6kRbRU1bqiIDBht79ckvAwRMGElkSOg';

/* ao READ-ONLY Env Variables */
export const AO_LOADER_HANDLER_ENV = {
  Process: {
    Id: PROCESS_ID,
    Owner: PROCESS_OWNER,
    Tags: [{ name: 'Authority', value: 'XXXXXX' }] as MessageTag[],
  },
  Module: {
    Id: PROCESS_ID,
    Tags: [{ name: 'Authority', value: 'YYYYYY' }] as MessageTag[],
  },
} as const;

export const AO_LOADER_OPTIONS: AoLoaderOptions = {
  format: 'wasm64-unknown-emscripten-draft_2024_02_15',
  inputEncoding: 'JSON-1',
  outputEncoding: 'JSON-1',
  memoryLimit: '1073741824', // in bytes (1GiB)
  computeLimit: (9e12).toString(),
  extensions: [],
};

export const DEFAULT_HANDLE_OPTIONS: DefaultHandleOptions = {
  Id: STUB_MESSAGE_ID,
  Target: PROCESS_ID,
  // Module: 'ANT',
  ['Block-Height']: STUB_BLOCK_HEIGHT,
  // important to set the address to match the FROM address so that that `Authority` check passes. Else the `isTrusted` with throw an error.
  Owner: PROCESS_OWNER,
  From: PROCESS_OWNER,
  Timestamp: STUB_TIMESTAMP,
  'Hash-Chain': STUB_HASH_CHAIN,
  Data: ' ',
  Tags: [] as MessageTag[],
};

// Use the localnet wallet for tests (ao-wallet.json from ao-localnet package)
// This ensures wallet consistency between spawning and operations
export const TEST_WALLET: any = getAoWallet();

// For AR.IO SDK methods (ANT.init, etc.)
export const TEST_SIGNER = createAoSigner(new ArweaveSigner(TEST_WALLET));

// For aoconnect methods (ao.spawn, ao.message) - but this doesn't work with ao-localnet's ao instance!
// Use createLocalnetSigner() from ao-localnet for ao.spawn/message operations instead
export const TEST_DATA_ITEM_SIGNER = createDataItemSigner(TEST_WALLET);

// =============================================================================
// AO Localnet SDK Exports (replaces .env configuration)
// =============================================================================

// Export SDK functions directly (lazy loading to avoid module-level async calls)
export {
  getUrls,
  getScheduler,
  getAosModule,
  getAuthority as getAuthorityAddress,
  createAoSigner as createLocalnetSigner,
  getAoInstance,
  loadConfig
} from 'ao-localnet';

// Convenience getters that call SDK functions
export function getLocalnetUrls() {
  const urls = getUrls();
  return {
    ARLOCAL_URL: urls.gateway,
    MU_URL: urls.mu,
    CU_URL: urls.cu,
    GATEWAY_URL: urls.gateway,
    GRAPHQL_URL: urls.graphql,
  };
}

export function getModuleId() {
  return getAosModule();
}

export function getSchedulerId() {
  return getScheduler();
}

// In-memory cache for ANT module ID (uploaded during test initialization)
let cachedAntModuleId: string | null = null;

// Upload ANT module to localnet and cache the ID
export async function uploadAntModuleIfNeeded(): Promise<string> {
  if (cachedAntModuleId) {
    return cachedAntModuleId;
  }

  console.log('📦 Uploading ANT WASM module to localnet...');
  
  // Import dynamically to avoid issues
  const Arweave = (await import('arweave')).default;
  const { getAoWallet } = await import('ao-localnet');
  
  // Read the ANT WASM module
  const antModulePath = path.join(__dirname, '../fixtures/modules/ant-drhsJZSyX8InDsd5EAfQDTgdKnD_wvjddHKY3KDPdf8.wasm');
  const moduleData = fs.readFileSync(antModulePath);
  
  console.log(`✅ Read ANT module (${moduleData.length} bytes)`);
  
  // Initialize Arweave for localnet
  const arweave = Arweave.init({
    host: 'localhost',
    port: 4000,
    protocol: 'http',
  });
  
  // Get wallet
  const wallet = getAoWallet();
  
  // Create transaction
  const tx = await arweave.createTransaction({
    data: moduleData,
  }, wallet);
  
  // Add tags (required for AO modules)
  // ANT uses wasm32 metering format, not wasm64
  tx.addTag('Data-Protocol', 'ao');
  tx.addTag('Type', 'Module');
  tx.addTag('Module-Format', 'wasm32-unknown-emscripten-metering');
  tx.addTag('Input-Encoding', 'JSON-1');
  tx.addTag('Output-Encoding', 'JSON-1');
  tx.addTag('Variant', 'ao.LN.1');
  tx.addTag('Content-Type', 'application/wasm');
  tx.addTag('Name', 'ANT');
  tx.addTag('Memory-Limit', '1-gb');
  tx.addTag('Compute-Limit', '9000000000000');
  
  // Sign and upload
  await arweave.transactions.sign(tx, wallet);
  await arweave.transactions.post(tx);
  
  // Mine a block to ensure it's available
  await fetch('http://localhost:4000/mine', { method: 'POST' });
  
  cachedAntModuleId = tx.id;
  console.log('✅ ANT module uploaded:', cachedAntModuleId);
  
  return cachedAntModuleId;
}

// Get ANT module ID (ensures module is uploaded first)
export async function getAntModuleId(): Promise<string> {
  if (!cachedAntModuleId) {
    return await uploadAntModuleIfNeeded();
  }
  return cachedAntModuleId;
}
