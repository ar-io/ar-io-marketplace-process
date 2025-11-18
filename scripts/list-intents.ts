import { config } from 'dotenv';
import { connect, createDataItemSigner } from '@permaweb/aoconnect';
import { readFileSync } from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { AOProcess } from '@ar.io/sdk';
import { MarketplaceProcess } from '../tests/utils/marketplace_process.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Load environment variables from .env file
config();

async function listIntents() {
  try {
    // Validate required environment variables
    const walletPath = process.env.WALLET_PATH;
    const marketplaceProcessId = process.env.MARKETPLACE_PROCESS;
    const cuUrl = process.env.CU_URL;

    if (!walletPath) {
      throw new Error('WALLET_PATH is required in .env file');
    }

    if (!marketplaceProcessId) {
      throw new Error('MARKETPLACE_PROCESS is required in .env file');
    }

    if (!cuUrl) {
      throw new Error('CU_URL is required in .env file');
    }

    // Load wallet
    console.log('Loading wallet from:', walletPath);
    const wallet = JSON.parse(
      readFileSync(path.join(__dirname, '../', walletPath), 'utf-8')
    );
    const signer = createDataItemSigner(wallet);

    const ao = connect({ CU_URL: cuUrl });

    console.log('Connecting to marketplace:', marketplaceProcessId);
    const marketplaceProcess = new MarketplaceProcess({
      process: new AOProcess({ ao, processId: marketplaceProcessId }),
      signer: signer as any,
    });

    // Get marketplace info
    console.log('\n=== Marketplace Info ===');
    const info = await marketplaceProcess.info();
    console.log('Total intents:', info.intents.total);
    console.log('Total orders:', info.activity.totalOrders);
    console.log('Listed orders:', info.activity.listedOrders);
    console.log('ARIO token:', info.ucm.arioTokenProcess);

    // Get all intents
    console.log('\n=== All Intents ===');
    const intentsResponse = await marketplaceProcess.getPaginatedIntents({
      limit: 100,
    });
    const intentsData = JSON.parse(intentsResponse.Data);

    if (intentsData.items && intentsData.items.length > 0) {
      console.log(`Found ${intentsData.items.length} intents:\n`);
      for (const intent of intentsData.items) {
        console.log(`Intent ID: ${intent.intentId}`);
        console.log(`  Status: ${intent.status}`);
        console.log(`  Action: ${intent.action}`);
        console.log(`  Type: ${intent.type}`);
        console.log(`  Initiator: ${intent.initiator}`);
        console.log(`  Created: ${new Date(intent.createdAt).toISOString()}`);
        if (intent.forwardedTags) {
          console.log('  Tags:', JSON.stringify(intent.forwardedTags, null, 4));
        }
        if (intent.children && intent.children.length > 0) {
          console.log(`  Children: ${intent.children.length} child intents`);
        }
        console.log('');
      }
    } else {
      console.log('No intents found');
    }

    // Get intents by status
    console.log('\n=== Intents by Status ===');
    for (const status of ['pending', 'active', 'completed', 'failed']) {
      const statusIntents = await marketplaceProcess.getPaginatedIntents({
        limit: 100,
        filters: { status },
      });
      const statusData = JSON.parse(statusIntents.Data);
      console.log(`${status}: ${statusData.totalItems || 0}`);
    }

  } catch (error) {
    console.error('Error:', error);
    throw error;
  }
}

listIntents();

export default listIntents;

