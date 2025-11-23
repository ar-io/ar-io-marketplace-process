import Arweave from 'arweave';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

async function uploadModule() {
  const arweave = Arweave.init({
    host: 'localhost',
    port: 4000,
    protocol: 'http',
  });

  const wallet = JSON.parse(
    fs.readFileSync(path.join(__dirname, '../tests/fixtures/wallets/localnet_wallet.json'), 'utf8'),
  );

  const wasm = fs.readFileSync(
    path.join(__dirname, '../tests/fixtures/modules/aos-cbn0KKrBZH7hdNkNokuXLtGryrWM--PjSTBqIzw9Kkk.wasm'),
  );

  const tx = await arweave.createTransaction({ data: wasm }, wallet);
  
  tx.addTag('Data-Protocol', 'ao');
  tx.addTag('Type', 'Module');
  tx.addTag('Module-Format', 'wasm64-unknown-emscripten-draft_2024_02_15');
  tx.addTag('Input-Encoding', 'JSON-1');
  tx.addTag('Output-Encoding', 'JSON-1');
  tx.addTag('Memory-Limit', '1-gb');
  tx.addTag('Compute-Limit', '9000000000000');
  tx.addTag('Content-Type', 'application/wasm');

  await arweave.transactions.sign(tx, wallet);
  await arweave.transactions.post(tx);

  console.log('Module uploaded:', tx.id);

  // Mine a block
  await fetch('http://localhost:4000/mine/1');
  console.log('Block mined');
  
  return tx.id;
}

uploadModule().catch(console.error);

