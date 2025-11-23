import { readFileSync, writeFileSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { connect, createDataItemSigner } from '@permaweb/aoconnect';
import { AOProcess, ANT, ArweaveSigner, createAoSigner as createAoSdkSigner } from '@ar.io/sdk';
import { MarketplaceProcess } from './marketplace_process.js';
import { ArioProcess } from './ario_process.js';
import { 
  getAoInstance,
  getScheduler as getSchedulerId,
  getAosModule as getModuleId,
  getAuthorityAddress,
  createLocalnetSigner,
  uploadAntModuleIfNeeded
} from './constants.js';
import Arweave from 'arweave'

const arweave = Arweave.init({
	host: 'arweave.net',
	port: 443,
	protocol: 'https',
})

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

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
  signer: any;  // DataItemSigner for ao.spawn/message
  aoSigner?: any; // AoSigner for SDK classes
  wallet: any;
  moduleId: string;
  scheduler: string;
  authority: string;
}): Promise<{ processId: string; process: ArioProcess }> {
  const { ao, signer, aoSigner, wallet, moduleId, scheduler } = params;

  // Spawn process using ao.spawn
  const authority = await getAuthorityAddress();
  
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

  // Wait for process to propagate to gateway
  console.log('Waiting 3s for AR.IO process to propagate...');
  await new Promise(resolve => setTimeout(resolve, 3000));

  // Load AR.IO process Lua code
  const lua = readFileSync(
    join(__dirname, '../fixtures/contracts/ario-bundled.lua'),
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
    signer: aoSigner || signer, // Use aoSigner for SDK, fallback to signer
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
  signer: any;  // DataItemSigner for ao.spawn/message
  aoSigner?: any; // AoSigner for SDK classes
  moduleId: string;
  scheduler: string;
  authority: string;
  arioProcessId?: string; // Optional ARIO process ID to set
}): Promise<{ processId: string; process: MarketplaceProcess }> {
  const { ao, signer, aoSigner, moduleId, scheduler, arioProcessId } = params;
  const authority = await getAuthorityAddress();

  console.log('Spawning Marketplace process...');
  
  // Spawn process using ao.spawn (rate limit is now fixed at 2000 tx/min)
  // Authority = MU wallet so it accepts cranked messages from MU
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

  // Wait for process to propagate to gateway
  console.log('Waiting 3s for Marketplace process to propagate...');
  await new Promise(resolve => setTimeout(resolve, 3000));

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
    signer: aoSigner || signer, // Use aoSigner for SDK, fallback to signer
  });

  // Add a delay to ensure marketplace is fully initialized before querying
  console.log('Waiting 3s for marketplace to fully initialize...');
  await new Promise(resolve => setTimeout(resolve, 3000));
  
  // Verify it's working
  try {
    const info = await marketplaceProcess.info();
    console.log('Marketplace info:', info);
  } catch (error) {
    console.warn('Marketplace info check failed, continuing anyway:', error);
  }

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
  // Authority = MU wallet so it can crank messages for this process
  const authority = await getAuthorityAddress();
  const processId = await ao.spawn({
    module: moduleId,
    scheduler,
    signer,
    tags: [
      { name: 'Name', value: 'ANT Test ' + Date.now() },
      { name: 'Authority', value: authority },
    ],
  });

  console.log('ANT spawned:', processId);
  
  // Wait for ANT to propagate to gateway
  console.log('Waiting 3s for ANT to propagate...');
  await new Promise(resolve => setTimeout(resolve, 3000));
  
  // Load ANT Lua code
  const antLua = readFileSync(
    join(__dirname, '../fixtures/contracts/ant-bundled.lua'),
    'utf-8',
  );

  await ao.message({
    process: processId,
    signer,
    tags: [{ name: 'Action', value: 'Eval' }],
    data: antLua,
  });

  console.log('ANT Lua loaded');
  
  // Initialize ANT instance with AOProcess
  const antProcess = ANT.init({
    process: new AOProcess({ ao, processId }),
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
  const authority = await getAuthorityAddress();
  const processId = await ao.spawn({
    module: moduleId,
    scheduler,
    signer,
    tags: [
      { name: 'Name', value: 'ANT Registry Test ' + Date.now() },
      { name: 'Authority', value: authority },
    ],
  });

  console.log('ANT Registry spawned:', processId);

  // Wait for process to propagate to gateway
  console.log('Waiting 3s for ANT Registry to propagate...');
  await new Promise(resolve => setTimeout(resolve, 3000));

  // Load ANT Registry Lua code
  const lua = readFileSync(
    join(__dirname, '../fixtures/contracts/ant-registry-bundled.lua'),
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
    // Get configuration from ao-localnet SDK (no .env needed!)
    const moduleId = getModuleId();
    const scheduler = getSchedulerId();
    const authority = await getAuthorityAddress();
    
    // Upload ANT module if not already done (required for ANT spawning)
    console.log('🔄 Ensuring ANT module is available...');
    await uploadAntModuleIfNeeded();
    
    // Use the same wallet from ao-localnet for EVERYTHING to avoid wallet mismatch
    const { getAoWallet } = await import('ao-localnet');
    const wallet = getAoWallet();
    
    // Use ao-localnet's signer (compatible with their ao instance)
    const dataItemSigner = createLocalnetSigner(new ArweaveSigner(wallet));
    // For AR.IO SDK we need AoSigner type (using the SAME wallet)
    const aoSigner = createAoSdkSigner(new ArweaveSigner(wallet));
    
    // Use pre-configured ao instance from SDK
    const ao = getAoInstance();

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
    signer: dataItemSigner,
    aoSigner,
    wallet,
    moduleId,
    scheduler,
    authority,
  });

  // Spawn ANT Registry next (needed for ANT spawning)
  const { processId: antRegistryProcessId, process: antRegistryProcess } = await spawnAntRegistryProcess({
    ao,
    signer: dataItemSigner,
    moduleId,
    scheduler,
  });

  // Note: We don't spawn an ANT here - each test spawns its own fresh ANT as needed
  // This avoids rate limits and scheduler lookup issues during initial setup
  const antProcessId = 'placeholder-ant-not-used';
  const antProcess = null as any; // Tests spawn their own ANTs

  // Spawn marketplace after ARIO is ready (needs ARIO process ID)
  const { processId: marketplaceProcessId, process: marketplaceProcess } =
    await spawnMarketplaceProcess({
      ao,
      signer: dataItemSigner,
      aoSigner,
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

