import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { ArweaveSigner, createAoSigner } from '@ar.io/sdk';
import { createDataItemSigner } from '@permaweb/aoconnect';
import type {
  AoLoaderOptions,
  DefaultHandleOptions,
  MessageTag,
} from './types.js';

/**
 * Custom fetch wrapper that logs all HTTP requests and responses
 * to help debug rate limiting issues
 */
export function createLoggingFetch(originalFetch: typeof fetch) {
  return async (
    url: string | URL | Request,
    init?: RequestInit,
  ): Promise<Response> => {
    const urlString = url instanceof Request ? url.url : url.toString();
    const method = init?.method || 'GET';

    console.log(`[FETCH] ${method} ${urlString}`);

    // Log request body for dry-run requests
    if (urlString.includes('4004/dry-run') && init?.body) {
      const bodyStr =
        typeof init.body === 'string' ? init.body : JSON.stringify(init.body);
      const truncated =
        bodyStr.length > 300 ? bodyStr.substring(0, 300) + '...' : bodyStr;
      console.log(`[FETCH] Request body:`, truncated);
    }

    try {
      const response = await originalFetch(url, init);
      const clonedResponse = response.clone();

      // Try to read the response body
      try {
        const body = await clonedResponse.text();
        const isJson = response.headers
          .get('content-type')
          ?.includes('application/json');

        if (isJson && body) {
          const jsonBody = JSON.parse(body);
          if (jsonBody.error) {
            console.log(`[FETCH] ⚠️  ${response.status} ${urlString}`);
            console.log(
              `[FETCH] Error Response:`,
              JSON.stringify(jsonBody, null, 2),
            );
          } else {
            console.log(
              `[FETCH] ✓ ${response.status} ${urlString} (${body.length} bytes)`,
            );
            // Log CU dry-run responses for debugging
            if (urlString.includes('4004/dry-run')) {
              const truncated =
                body.length > 500 ? body.substring(0, 500) + '...' : body;
              console.log(`[FETCH] CU Response:`, truncated);
            }
          }
        } else {
          console.log(
            `[FETCH] ✓ ${response.status} ${urlString} (${body.length} bytes)`,
          );
        }
      } catch (_e) {
        console.log(
          `[FETCH] ✓ ${response.status} ${urlString} (binary/non-text)`,
        );
      }

      return response;
    } catch (error) {
      console.log(
        `[FETCH] ✗ Failed: ${urlString}`,
        error instanceof Error ? error.message : String(error),
      );
      throw error;
    }
  };
}

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export const AOS_WASM: Buffer = fs.readFileSync(
  path.join(
    __dirname,
    '../fixtures/modules/aos-cbn0KKrBZH7hdNkNokuXLtGryrWM--PjSTBqIzw9Kkk.wasm',
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
  Module: PROCESS_ID, // just a stub
  ['Block-Height']: STUB_BLOCK_HEIGHT,
  // important to set the address to match the FROM address so that that `Authority` check passes. Else the `isTrusted` with throw an error.
  Owner: PROCESS_OWNER,
  From: PROCESS_OWNER,
  Timestamp: STUB_TIMESTAMP,
  'Hash-Chain': STUB_HASH_CHAIN,
  Data: ' ',
  Tags: [] as MessageTag[],
};

// Use the test wallet for integration tests (test_wallet.json from fixtures)
export const TEST_WALLET: any = JSON.parse(
  fs.readFileSync(
    path.join(__dirname, '../fixtures/wallets/test_wallet.json'),
    'utf-8',
  ),
);

// For AR.IO SDK methods (ANT.init, etc.)
export const TEST_SIGNER = createAoSigner(new ArweaveSigner(TEST_WALLET));

// For aoconnect methods (ao.spawn, ao.message)
export const TEST_DATA_ITEM_SIGNER = createDataItemSigner(TEST_WALLET);

// =============================================================================
// Integration Test Constants
// =============================================================================

// Test sender address (matches PROCESS_OWNER)
export const TEST_SENDER = PROCESS_OWNER;

// Non-owner address for authorization tests
export const UNAUTHORIZED_SENDER = 'unauthorized-user-'.padEnd(43, '9');

// Test token/process IDs
export const TEST_ANT_TOKEN = 'test-ant-token-'.padEnd(43, '1');
export const TEST_ANT_PROCESS = 'test-ant-process-'.padEnd(43, '1');
export const TEST_ARIO_PROCESS = 'test-ario-process'.padEnd(43, '1');
export const TEST_ARIO_TOKEN = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA';

// Test ANT module IDs
export const TEST_ANT_MODULE_WHITELISTED =
  'drhsJZSyX8InDsd5EAfQDTgdKnD_wvjddHKY3KDPdf8';
export const TEST_ANT_MODULE_NOT_WHITELISTED =
  '9afQ1PLf2mrshqCTZEzzJTR2gWaC9zHYWyqH3_12345';

// =============================================================================
// Note: ao-localnet exports removed - use local test environment instead
// =============================================================================
