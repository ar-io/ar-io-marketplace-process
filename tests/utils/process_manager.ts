import { readFileSync, writeFileSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { config } from 'dotenv';
import { connect, createDataItemSigner } from '@permaweb/aoconnect';
import { AOProcess, ANT } from '@ar.io/sdk';
import { MarketplaceProcess } from './marketplace_process.js';
import { ArioProcess } from './ario_process.js';
import Arweave from 'arweave'

const arweave = Arweave.init({
	host: 'arweave.net',
	port: 443,
	protocol: 'https',
})

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

config();

/**
 * Convert JWK to Arweave address
 */
async function jwkToAddress(jwk: any): Promise<string> {
  return arweave.wallets.jwkToAddress(jwk);
}


/**
 * Process configuration stored in e2e-test.json
 */
export interface ProcessConfig {
  arioProcessId: string;
  marketplaceProcessId: string;
  antProcessId: string;
  antRegistryProcessId: string;
  timestamp: number;
}

/**
 * Spawned process instances
 */
export interface SpawnedProcesses {
  arioProcessId: string;
  arioProcess: ArioProcess;
  marketplaceProcessId: string;
  marketplaceProcess: MarketplaceProcess;
  antProcessId: string;
  antProcess: ANT;
  antRegistryProcessId: string;
  antRegistryProcess: AOProcess;
  config: ProcessConfig;
}

const E2E_CONFIG_PATH = join(__dirname, '../../e2e-test.json');

/**
 * Load existing process configuration from e2e-test.json
 */
export function loadProcessConfig(): ProcessConfig | null {
  try {
    if (existsSync(E2E_CONFIG_PATH)) {
      const content = readFileSync(E2E_CONFIG_PATH, 'utf-8');
      return JSON.parse(content);
    }
  } catch (error) {
    console.warn('Failed to load process config:', error);
  }
  return null;
}

/**
 * Save process configuration to e2e-test.json
 */
export function saveProcessConfig(config: ProcessConfig): void {
  writeFileSync(E2E_CONFIG_PATH, JSON.stringify(config, null, 2), 'utf-8');
}

/**
 * Validate that a process is still healthy and accessible
 */
async function validateProcess(
  processId: string,
  ao: any,
): Promise<boolean> {
  try {
    const process = new AOProcess({ ao, processId });
    const result = await process.read({
      tags: [{ name: 'Action', value: 'Info' }],
    });
    return !!result;
  } catch (error) {
    console.warn(`Process ${processId} validation failed:`, error);
    return false;
  }
}

/**
 * Spawn a new AR.IO process
 */
async function spawnArioProcess(params: {
  ao: any;
  signer: any;
  wallet: any;
  moduleId: string;
  scheduler: string;
  authority: string;
}): Promise<{ processId: string; process: ArioProcess }> {
  const { ao, signer, wallet, moduleId, scheduler, authority } = params;

  // Spawn process using ao.spawn (rate limit is now fixed at 2000 tx/min)
  const processId = await ao.spawn({
    module: moduleId,
    scheduler,
    signer,
    tags: [
      { name: 'Name', value: 'AR-IO Test Process ' + Date.now() },
      { name: 'Authority', value: authority },
    ],
  });

  console.log('AR.IO process spawned:', processId);

  // Load AR.IO process Lua code
  const lua = readFileSync(
    join(__dirname, '../fixtures/ar-io-network-process.lua'),
    'utf-8',
  );

  await ao.message({
    process: processId,
    signer,
    tags: [{ name: 'Action', value: 'Eval' }],
    data: lua,
  });

  console.log('AR.IO process Lua loaded');

  // Create process wrapper
  const aoProcess = new AOProcess({ ao, processId });
  const arioProcess = new ArioProcess({
    process: aoProcess,
    signer,
  });

  // Mint initial balance for testing - derive address from wallet JWK
  const testAddress = await jwkToAddress(wallet);
  await arioProcess.mintBalance(testAddress, '100000000000'); // 100k ARIO
  console.log('Minted test balance for wallet:', testAddress);

  return { processId, process: arioProcess };
}

/**
 * Spawn a new marketplace process
 */
async function spawnMarketplaceProcess(params: {
  ao: any;
  signer: any;
  moduleId: string;
  scheduler: string;
  authority: string;
  arioProcessId?: string; // Optional ARIO process ID to set
}): Promise<{ processId: string; process: MarketplaceProcess }> {
  const { ao, signer, moduleId, scheduler, authority, arioProcessId } = params;

  // Spawn process using ao.spawn (rate limit is now fixed at 2000 tx/min)
  const processId = await ao.spawn({
    module: moduleId,
    scheduler,
    signer,
    tags: [
      { name: 'Name', value: 'AR-IO Marketplace Test ' + Date.now() },
      { name: 'Authority', value: authority },
    ],
  });

  console.log('Marketplace process spawned:', processId);

  // Load marketplace Lua code
  const lua = readFileSync(
    join(__dirname, '../../dist/aos-bundled.lua'),
    'utf-8',
  );

  await ao.message({
    process: processId,
    signer,
    tags: [{ name: 'Action', value: 'Eval' }],
    data: lua,
  });

  console.log('Marketplace Lua loaded');

  // Set ARIO token process if provided
  if (arioProcessId) {
    console.log('Setting ARIO_TOKEN_PROCESS_ID to:', arioProcessId);
    await ao.message({
      process: processId,
      signer,
      tags: [{ name: 'Action', value: 'Eval' }],
      data: `ARIO_TOKEN_PROCESS_ID = "${arioProcessId}"`,
    });
    console.log('ARIO token process ID configured');
  }

  // Create process wrapper
  const aoProcess = new AOProcess({ ao, processId });
  const marketplaceProcess = new MarketplaceProcess({
    process: aoProcess,
    signer,
  });

  // Verify it's working
  const info = await marketplaceProcess.info();
  console.log('Marketplace info:', info);

  // Add a small delay to ensure marketplace is fully initialized
  console.log('Waiting 5s for marketplace to fully initialize...');
  await new Promise(resolve => setTimeout(resolve, 5000));

  return { processId, process: marketplaceProcess };
}

/**
 * Spawn a new ANT process manually to avoid scheduler-utils issues on localnet
 */
async function spawnAntProcess(params: {
  ao: any;
  signer: any;
  moduleId: string;
  scheduler: string;
}): Promise<{ processId: string; process: ANT }> {
  const { ao, signer, moduleId, scheduler } = params;

  console.log('Spawning ANT via ao.spawn()...');
  
  // Use ao.spawn() directly (ANT SDK has scheduler lookup issues on localnet)
  const processId = await ao.spawn({
    module: moduleId,
    scheduler,
    signer,
    tags: [
      { name: 'Name', value: 'ANT Test ' + Date.now() },
    ],
  });

  console.log('ANT spawned:', processId);
  
  // Initialize ANT instance
  const antProcess = ANT.init({
    processId,
    signer,
  });

  // Verify ANT is responsive with a short timeout
  try {
    await antProcess.getInfo();
    console.log('ANT is responsive');
  } catch (error) {
    console.warn('ANT getInfo() failed, continuing anyway:', error);
  }

  return { processId, process: antProcess };
}

/**
 * Spawn ANT Registry process
 */
async function spawnAntRegistryProcess(params: {
  ao: any;
  signer: any;
  moduleId: string;
  scheduler: string;
}): Promise<{ processId: string; process: AOProcess }> {
  const { ao, signer, moduleId, scheduler } = params;

  console.log('Spawning ANT Registry...');
  
  // Spawn ANT Registry process using ao.spawn (rate limit is now fixed at 2000 tx/min)
  const processId = await ao.spawn({
    module: moduleId,
    scheduler,
    signer,
    tags: [
      { name: 'Name', value: 'ANT Registry Test ' + Date.now() },
    ],
  });

  console.log('ANT Registry spawned:', processId);

  // Load ANT Registry Lua code
  const lua = readFileSync(
    join(__dirname, '../fixtures/ant-registry-bundled.lua'),
    'utf-8',
  );

  await ao.message({
    process: processId,
    signer,
    tags: [{ name: 'Action', value: 'Eval' }],
    data: lua,
  });

  console.log('ANT Registry Lua loaded');

  // Create process wrapper
  const antRegistryProcess = new AOProcess({ ao, processId });

  return { processId, process: antRegistryProcess };
}

/**
 * Get or spawn processes for e2e tests
 */
export async function getOrSpawnProcesses(): Promise<SpawnedProcesses> {
  try {
    // Load environment variables
    const walletPath = process.env.WALLET_PATH;
    const moduleId = process.env.MODULE_ID || process.env.AOS_MODULE; // Support both names
    const scheduler = process.env.SCHEDULER;
    const authority = process.env.AUTHORITY;
    const cuUrl = process.env.CU_URL;
    const muUrl = process.env.MU_URL;
    const graphqlUrl = process.env.GRAPHQL_URL;

    if (!walletPath || !moduleId || !scheduler || !authority || !cuUrl || !muUrl || !graphqlUrl) {
      throw new Error(
        'Missing required environment variables. Check .env file.',
      );
    }

    // Load wallet and create signer
    const wallet = JSON.parse(
      readFileSync(join(__dirname, '../../', walletPath), 'utf-8'),
    );
    const signer = createDataItemSigner(wallet);

    // Connect to AO with localnet configuration using legacy mode
    const ao = connect({
      MODE: 'legacy',
      MU_URL: muUrl,
      CU_URL: cuUrl,
      GATEWAY_URL: process.env.GATEWAY_URL,
      GRAPHQL_URL: graphqlUrl,
    });

  // Try to load existing config
  const existingConfig = loadProcessConfig();

  if (existingConfig) {
    console.log('Found existing process config, validating...');

    // Validate all processes
    const arioValid = await validateProcess(existingConfig.arioProcessId, ao);
    const marketplaceValid = await validateProcess(
      existingConfig.marketplaceProcessId,
      ao,
    );
    const antRegistryValid = existingConfig.antRegistryProcessId 
      ? await validateProcess(existingConfig.antRegistryProcessId, ao)
      : false;
    
    // Always spawn a fresh ANT to ensure clean state for testing
    console.log('Note: Will spawn fresh ANT for clean test state');
    const antValid = false;

    if (arioValid && marketplaceValid && antRegistryValid && antValid) {
      console.log('All processes valid, reusing...');

      // Create process instances
      const arioProcess = new ArioProcess({
        process: new AOProcess({ ao, processId: existingConfig.arioProcessId }),
        signer,
      });

      const marketplaceProcess = new MarketplaceProcess({
        process: new AOProcess({
          ao,
          processId: existingConfig.marketplaceProcessId,
        }),
        signer,
      });

      const antProcess = ANT.init({
        process: new AOProcess({ ao, processId: existingConfig.antProcessId }),
        signer,
      });

      const antRegistryProcess = new AOProcess({ 
        ao, 
        processId: existingConfig.antRegistryProcessId 
      });

      return {
        arioProcessId: existingConfig.arioProcessId,
        arioProcess,
        marketplaceProcessId: existingConfig.marketplaceProcessId,
        marketplaceProcess,
        antProcessId: existingConfig.antProcessId,
        antProcess: antProcess,
        antRegistryProcessId: existingConfig.antRegistryProcessId,
        antRegistryProcess,
        config: existingConfig,
      };
    }

    console.log('Some processes invalid, spawning new ones...');
  }

  // Spawn new processes
  console.log('Spawning new processes...');

  // Spawn ARIO first (needed for marketplace)
  const { processId: arioProcessId, process: arioProcess } = await spawnArioProcess({
    ao,
    signer,
    wallet,
    moduleId,
    scheduler,
    authority,
  });

  // Spawn ANT Registry next (needed for ANT spawning)
  const { processId: antRegistryProcessId, process: antRegistryProcess } = await spawnAntRegistryProcess({
    ao,
    signer,
    moduleId,
    scheduler,
  });

  // Spawn ANT after registry is ready
  const { processId: antProcessId, process: antProcess } = await spawnAntProcess({
    ao,
    signer,
    moduleId,
    scheduler,
  });

  // Spawn marketplace after ARIO is ready (needs ARIO process ID)
  const { processId: marketplaceProcessId, process: marketplaceProcess } =
    await spawnMarketplaceProcess({
      ao,
      signer,
      moduleId,
      scheduler,
      authority,
      arioProcessId, // Pass the ARIO process ID
    });

  // Save configuration
  const config: ProcessConfig = {
    arioProcessId,
    marketplaceProcessId,
    antProcessId,
    antRegistryProcessId,
    timestamp: Date.now(),
  };

  saveProcessConfig(config);
  console.log('Process configuration saved to e2e-test.json');

  return {
    arioProcessId,
    arioProcess,
    marketplaceProcessId,
    marketplaceProcess,
    antProcessId,
    antProcess: antProcess,
    antRegistryProcessId,
    antRegistryProcess,
    config,
  };
  } catch (error) {
    console.error('Error in getOrSpawnProcesses:', error);
    throw error;
  }
}

