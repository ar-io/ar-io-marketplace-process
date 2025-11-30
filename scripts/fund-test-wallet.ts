#!/usr/bin/env tsx
/**
 * Fund the test wallet and bundler wallet with AR tokens on localnet
 */

import Arweave from 'arweave';
import { getAoWallet } from '../tests/utils/ao_localnet_config.js';
import { readFileSync, existsSync, writeFileSync } from 'fs';
import { execSync } from 'child_process';

async function fundWallet(address: string, name: string, amount: string) {
  const LOCALNET_GATEWAY = 'http://localhost:4000';
  
  console.log(`\n💰 Funding ${name}...`);
  console.log(`   Address: ${address}`);
  console.log(`   Amount: ${amount} winstons`);
  
  // Mint tokens
  const response = await fetch(`${LOCALNET_GATEWAY}/mint/${address}/${amount}`);
  const result = await response.text();
  
  if (response.ok) {
    console.log(`   ✓ Minted: ${result} winstons`);
  } else {
    console.log(`   ✗ Failed to mint: ${result}`);
    return false;
  }
  
  // Verify balance
  const balanceResponse = await fetch(`${LOCALNET_GATEWAY}/wallet/${address}/balance`);
  const balance = await balanceResponse.text();
  console.log(`   ✓ Current balance: ${balance} winstons`);
  return true;
}

async function main() {
  const arweave = Arweave.init({});
  
  // 1. Fund test wallet
  const testWallet = getAoWallet();
  const testAddress = await arweave.wallets.jwkToAddress(testWallet);
  await fundWallet(testAddress, 'test wallet', '10000000000000000'); // 10,000 AR
  
  // 2. Fund bundler wallet
  try {
    // Extract bundler wallet from Docker container
    const bundlerWalletPath = '/tmp/bundler-wallet.json';
    execSync(`docker exec ao-localnet-archive-bundler-1 cat /app/bundler-wallet.json > ${bundlerWalletPath}`);
    
    if (existsSync(bundlerWalletPath)) {
      const bundlerWallet = JSON.parse(readFileSync(bundlerWalletPath, 'utf-8'));
      const bundlerAddress = await arweave.wallets.jwkToAddress(bundlerWallet);
      await fundWallet(bundlerAddress, 'bundler wallet', '100000000000000000'); // 100,000 AR
    } else {
      console.log('\n⚠️  Could not extract bundler wallet');
    }
  } catch (error) {
    console.log('\n⚠️  Could not fund bundler wallet:', error instanceof Error ? error.message : String(error));
  }
  
  console.log('\n✅ Wallet funding complete!');
}

main().catch(console.error);

