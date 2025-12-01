/**
 * AO Localnet Manager
 * 
 * Handles starting, stopping, and seeding ao-localnet services for E2E tests.
 * Uses the ao-localnet package's autoseed functionality.
 * 
 * Based on: node_modules/ao-localnet/tests/README.md
 */

import { exec } from 'child_process';
import { promisify } from 'util';
import { existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const execAsync = promisify(exec);
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Path to ao-localnet package
const AO_LOCALNET_DIR = join(__dirname, '../../node_modules/ao-localnet');

interface LocalnetStatus {
  running: boolean;
  seeded: boolean;
  configured: boolean;
}

/**
 * Check if Docker services are running
 */
export async function checkLocalnetStatus(): Promise<LocalnetStatus> {
  try {
    const { stdout } = await execAsync('docker compose ps --format json', {
      cwd: AO_LOCALNET_DIR,
    });
    
    const services = stdout
      .trim()
      .split('\n')
      .filter(line => line.trim())
      .map(line => JSON.parse(line));
    
    const running = services.length > 0 && services.every((s: any) => s.State === 'running');
    
    // Check if config file exists
    const configPath = join(AO_LOCALNET_DIR, '.ao-localnet.config.json');
    const configured = existsSync(configPath);
    
    // Check if wallets exist (indicates seeding completed)
    const walletPath = join(AO_LOCALNET_DIR, 'wallets/ao-wallet.json');
    const seeded = existsSync(walletPath);
    
    return { running, seeded, configured };
  } catch (error) {
    return { running: false, seeded: false, configured: false };
  }
}

/**
 * Configure ao-localnet (generates wallets and downloads AOS module)
 */
export async function configureLocalnet(): Promise<void> {
  console.log('🔧 Configuring ao-localnet...');
  
  try {
    // Run configure script (generates wallets + downloads AOS module)
    const { stdout, stderr } = await execAsync('npm run configure', {
      cwd: AO_LOCALNET_DIR,
      env: { ...process.env, FORCE_COLOR: '0' },
    });
    
    if (stderr && !stderr.includes('WARN')) {
      console.warn('Configure warnings:', stderr);
    }
    
    console.log('✅ ao-localnet configured');
  } catch (error: any) {
    console.error('❌ Failed to configure ao-localnet:', error.message);
    throw error;
  }
}

/**
 * Start ao-localnet Docker services
 */
export async function startLocalnet(): Promise<void> {
  console.log('🚀 Starting ao-localnet services...');
  
  try {
    const { stdout } = await execAsync('npm run start', {
      cwd: AO_LOCALNET_DIR,
      env: { ...process.env, FORCE_COLOR: '0' },
    });
    
    // Wait for services to be healthy
    await waitForHealthy();
    
    console.log('✅ ao-localnet services started');
  } catch (error: any) {
    console.error('❌ Failed to start ao-localnet:', error.message);
    throw error;
  }
}

/**
 * Seed ao-localnet with initial data (scheduler location, AOS module)
 */
export async function seedLocalnet(): Promise<void> {
  console.log('🌱 Seeding ao-localnet...');
  
  try {
    const { stdout, stderr } = await execAsync('npm run seed', {
      cwd: AO_LOCALNET_DIR,
      env: { ...process.env, FORCE_COLOR: '0' },
    });
    
    // Parse the output to extract the module ID and scheduler location
    const moduleMatch = stdout.match(/aos module:\s*([A-Za-z0-9_-]+)/);
    const schedulerLocationMatch = stdout.match(/tx id\s*:\s*([A-Za-z0-9_-]+)/);
    const schedulerPublisherMatch = stdout.match(/scheduler location publisher address:\s*([A-Za-z0-9_-]+)/);
    
    if (moduleMatch || schedulerLocationMatch || schedulerPublisherMatch) {
      // Update config file with the extracted values
      const { readFileSync, writeFileSync } = await import('fs');
      const configPath = join(AO_LOCALNET_DIR, '.ao-localnet.config.json');
      const config = JSON.parse(readFileSync(configPath, 'utf-8'));
      
      if (moduleMatch) {
        config.bootstrap.transactions.aosModule = moduleMatch[1];
        console.log(`   📦 AOS Module: ${moduleMatch[1]}`);
      }
      
      if (schedulerLocationMatch) {
        config.bootstrap.transactions.schedulerLocation = schedulerLocationMatch[1];
        console.log(`   📍 Scheduler Location: ${schedulerLocationMatch[1]}`);
      }
      
      if (schedulerPublisherMatch) {
        config.bootstrap.transactions.scheduler = schedulerPublisherMatch[1];
        console.log(`   📅 Scheduler: ${schedulerPublisherMatch[1]}`);
      }
      
      writeFileSync(configPath, JSON.stringify(config, null, 2));
    }
    
    console.log('✅ ao-localnet seeded');
  } catch (error: any) {
    console.error('❌ Failed to seed ao-localnet:', error.message);
    throw error;
  }
}

/**
 * Stop ao-localnet Docker services (keeps data)
 */
export async function stopLocalnet(): Promise<void> {
  console.log('🛑 Stopping ao-localnet services...');
  
  try {
    await execAsync('npm run stop', {
      cwd: AO_LOCALNET_DIR,
      env: { ...process.env, FORCE_COLOR: '0' },
    });
    
    console.log('✅ ao-localnet services stopped');
  } catch (error: any) {
    console.error('❌ Failed to stop ao-localnet:', error.message);
    throw error;
  }
}

/**
 * Reset ao-localnet (deletes all data and re-seeds)
 */
export async function resetLocalnet(): Promise<void> {
  console.log('🔄 Resetting ao-localnet...');
  
  try {
    await execAsync('npm run reseed', {
      cwd: AO_LOCALNET_DIR,
      env: { ...process.env, FORCE_COLOR: '0' },
    });
    
    console.log('✅ ao-localnet reset');
  } catch (error: any) {
    console.error('❌ Failed to reset ao-localnet:', error.message);
    throw error;
  }
}

/**
 * Wait for ArLocal gateway to be healthy
 */
async function waitForHealthy(maxRetries = 30, delayMs = 1000): Promise<void> {
  for (let i = 0; i < maxRetries; i++) {
    try {
      const response = await fetch('http://localhost:4000/healthcheck');
      if (response.ok) {
        return;
      }
    } catch (error) {
      // Service not ready yet
    }
    
    await new Promise(resolve => setTimeout(resolve, delayMs));
  }
  
  throw new Error('ao-localnet services did not become healthy in time');
}

/**
 * Full setup: Configure, start, and seed ao-localnet
 */
export async function setupLocalnet(): Promise<void> {
  const status = await checkLocalnetStatus();
  
  console.log('\n📊 ao-localnet status:', status);
  
  // Configure if needed
  if (!status.configured || !status.seeded) {
    await configureLocalnet();
  } else {
    console.log('✓ Already configured');
  }
  
  // Start if not running
  if (!status.running) {
    await startLocalnet();
  } else {
    console.log('✓ Already running');
  }
  
  // Seed if needed (or if we just started)
  if (!status.seeded || !status.running) {
    await seedLocalnet();
  } else {
    console.log('✓ Already seeded');
  }
  
  console.log('\n✅ ao-localnet ready for testing!\n');
}

/**
 * Cleanup: Stop services (optional, for test teardown)
 */
export async function teardownLocalnet(stopServices = false): Promise<void> {
  if (stopServices) {
    await stopLocalnet();
  } else {
    console.log('ℹ️  Keeping ao-localnet running (use stopServices=true to stop)');
  }
}

