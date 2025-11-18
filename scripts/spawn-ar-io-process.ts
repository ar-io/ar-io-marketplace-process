import { config } from 'dotenv';
import { connect, createDataItemSigner } from '@permaweb/aoconnect';
import { readFileSync } from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { AOProcess, ARIO } from '@ar.io/sdk';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Load environment variables from .env file
config();

async function spawnArioProcess() {
  try {
    // Validate required environment variables
    const walletPath = process.env.WALLET_PATH;
    if (!walletPath) {
      throw new Error('WALLET_PATH is required in .env file');
    }

    // Load wallet
    console.log('Loading wallet from:', walletPath);
    const wallet = JSON.parse(readFileSync(path.join(__dirname,'../', walletPath), 'utf-8'));
    const signer = createDataItemSigner(wallet);
    

      
      const moduleId = process.env.AOS_MODULE;
      const scheduler = process.env.SCHEDULER;
	  const authority = process.env.AUTHORITY;
	  const cuUrl = process.env.CU_URL;

	  if (!moduleId || !scheduler || !authority || !cuUrl) {
		throw new Error('MODULE_ID, SCHEDULER, AUTHORITY, and CU_URL are required in .env file');
	  }

	  const lua = readFileSync(path.join(__dirname, '../tests/fixtures/ar-io-network-process.lua'), 'utf-8');

	  const ao = connect({CU_URL: cuUrl});
      
      const processId = await ao.spawn({
        module: moduleId,
        scheduler: scheduler,
        signer,
        tags: [
          { name: 'Name', value: 'AR-IO Network Test ' + Date.now() },
		  { name: 'Authority', value: authority },
        ],
      });

	  console.log('Process spawned successfully with ID:', processId);
	  console.log('Loading Lua...');
	  const luaLoadId = await ao.message({
		process: processId,
		signer,
		tags: [
			{ name: 'Action', value: 'Eval' },
		],
		data: lua,
	  });

	  console.log('Lua loaded successfully with ID:', luaLoadId);

	  const arioProcess = ARIO.init({process: new AOProcess({ ao, processId }), signer: signer as any});

	  return {processId, arioProcess};
    
  } catch (error) {
    console.error('Error:', error);
	throw error;
  }
}

spawnArioProcess()

export default spawnArioProcess;