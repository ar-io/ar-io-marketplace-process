import { existsSync, readFileSync } from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { connect, createDataItemSigner } from '@permaweb/aoconnect';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const TX_ID_REGEX = /^[a-zA-Z0-9\-_]{43}$/;

/*
Example usage:

pnpm propose-eval --dry-run

Required environment variables:
- MARKETPLACE_PROCESS_ID: The marketplace process ID
- VAOT_ID: The VAOT process ID for proposal voting
- WALLET: JSON wallet key (or WALLET_PATH for file path)

Optional environment variables:
- CU_URL: Custom CU URL (default: https://cu.ardrive.io)
*/

async function main() {
  const dryRun =
    process.argv.includes('--dry-run') || process.env.DRY_RUN === 'true';

  const marketplaceProcessId =
    process.env.MARKETPLACE_PROCESS_ID ??
    process.argv[process.argv.indexOf('--marketplace-id') + 1];

  const vaotId =
    process.env.VAOT_ID ?? process.argv[process.argv.indexOf('--vaot-id') + 1];

  // Validate required parameters
  const requiredIds = [marketplaceProcessId, vaotId];
  if (!requiredIds.every((id) => TX_ID_REGEX.test(id))) {
    console.error('Missing or invalid required parameters!');
    console.log(
      JSON.stringify(
        {
          marketplaceProcessId,
          vaotId,
        },
        null,
        2,
      ),
    );
    process.exit(1);
  }

  // Read the bundled Lua code
  const bundledLuaPath = path.join(__dirname, '../dist/aos-bundled.lua');
  if (!existsSync(bundledLuaPath)) {
    console.error(`Bundled Lua file not found at: ${bundledLuaPath}`);
    console.error('Run the build first: pnpm build');
    process.exit(1);
  }

  const evalString = readFileSync(bundledLuaPath, 'utf-8');

  if (dryRun) {
    console.log('=== DRY RUN ===\n');
    console.log('Would propose Eval to VAOT:', vaotId);
    console.log('Target Process-Id:', marketplaceProcessId);
    console.log('Eval string length:', evalString.length, 'characters');
    console.log('\nFirst 500 characters of eval string:\n');
    console.log(evalString.substring(0, 500) + '...');
    process.exit(0);
  }

  // Load wallet (only needed for actual submission)
  const walletPath = process.argv.includes('--wallet-file')
    ? process.argv[process.argv.indexOf('--wallet-file') + 1]
    : process.env.WALLET_PATH || path.join(__dirname, 'key.json');

  const jwk = process.env.WALLET
    ? JSON.parse(process.env.WALLET)
    : JSON.parse(readFileSync(walletPath, 'utf-8'));

  const signer = createDataItemSigner(jwk);
  const cuUrl = process.env.CU_URL || 'https://cu.ardrive.io';
  const ao = connect({
    CU_URL: cuUrl,
    MODE: 'legacy',
  });

  console.log('Submitting proposal to VAOT...');
  console.log('VAOT ID:', vaotId);
  console.log('Marketplace Process ID:', marketplaceProcessId);

  const proposalResult = await ao.message({
    process: vaotId,
    tags: [
      { name: 'Action', value: 'Propose' },
      { name: 'Proposal-Type', value: 'Eval' },
      { name: 'Vote', value: 'yay' },
      { name: 'Process-Id', value: marketplaceProcessId },
    ],
    data: evalString,
    signer,
  });

  if (!proposalResult || typeof proposalResult !== 'string') {
    throw new Error('Failed to create proposal');
  }

  console.log(`Proposal submitted successfully!`);
  console.log(`Proposal message ID: ${proposalResult}`);
  console.log(
    `View on scan.ar.io: https://scan.ar.io/#/message/${proposalResult}`,
  );
}

main().catch((err) => {
  console.error('Error:', err);
  process.exit(1);
});
