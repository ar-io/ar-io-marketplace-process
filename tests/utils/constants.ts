import { ArweaveSigner, createAoSigner } from '@ar.io/sdk';
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
    '../fixtures/aos-cbn0KKrBZH7hdNkNokuXLtGryrWM--PjSTBqIzw9Kkk.wasm',
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
  Module: 'ANT',
  ['Block-Height']: STUB_BLOCK_HEIGHT,
  // important to set the address to match the FROM address so that that `Authority` check passes. Else the `isTrusted` with throw an error.
  Owner: PROCESS_OWNER,
  From: PROCESS_OWNER,
  Timestamp: STUB_TIMESTAMP,
  'Hash-Chain': STUB_HASH_CHAIN,
  Data: ' ',
  Tags: [] as MessageTag[],
};

export const TEST_WALLET: any = JSON.parse(
  fs.readFileSync(path.join(__dirname, '../fixtures/test_wallet.json'), 'utf8'),
);

export const TEST_SIGNER = createAoSigner(new ArweaveSigner(TEST_WALLET));
