#!/usr/bin/env tsx

import { readFileSync, writeFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { createAoSigner, getAoWallet } from '../tests/utils/ao_localnet_config.js';
import Arweave from 'arweave';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

async function uploadAntModule() {
  try {
    console.log('📦 Uploading ANT WASM module to localnet...');
    
    // Read the ANT WASM module
    const antModulePath = join(__dirname, '../tests/fixtures/modules/ant-drhsJZSyX8InDsd5EAfQDTgdKnD_wvjddHKY3KDPdf8.wasm');
    const moduleData = readFileSync(antModulePath);
    
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
    console.log('⬆️  Creating transaction...');
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
    console.log('✍️  Signing transaction...');
    await arweave.transactions.sign(tx, wallet);
    
    console.log('⬆️  Uploading to ArLocal...');
    await arweave.transactions.post(tx);
    
    const moduleId = tx.id;
    
    console.log('✅ ANT module uploaded:', moduleId);
    
    // Mine a block to ensure it's available
    console.log('⛏️  Mining block...');
    await fetch('http://localhost:4000/mine', { method: 'POST' });
    console.log('✅ Block mined');
    
    // Save to config file
    const configPath = join(__dirname, '../ant-module-config.json');
    const config = {
      antModuleId: moduleId,
      uploadedAt: new Date().toISOString(),
    };
    
    writeFileSync(configPath, JSON.stringify(config, null, 2));
    console.log('✅ Saved ANT module ID to:', configPath);
    
    console.log('\n📋 To use in tests:');
    console.log(`   const antModuleId = '${moduleId}';`);
    
    return moduleId;
  } catch (error) {
    console.error('❌ Error uploading ANT module:', error);
    throw error;
  }
}

uploadAntModule();

