import AoLoader from '@permaweb/ao-loader';
import {
  AOS_WASM,
  AO_LOADER_HANDLER_ENV,
  AO_LOADER_OPTIONS,
  DEFAULT_HANDLE_OPTIONS,
} from './constants.js';
import type { CreateAosLoaderParams, CreateAosLoaderResult } from './types.js';

/**
 * Loads the aos wasm binary and returns the handle function with program memory
 *
 * @param params - The parameters for creating the AOS loader
 * @returns Promise resolving to handle function and memory
 */
export async function createAosLoader({
  lua,
  wasm = AOS_WASM,
  options = AO_LOADER_OPTIONS,
  handlerEnv = AO_LOADER_HANDLER_ENV,
}: CreateAosLoaderParams): Promise<CreateAosLoaderResult> {
  console.log('creating aos loader');
  const handle = await AoLoader(wasm, options);
  const evalRes = await handle(
    null,
    {
      ...DEFAULT_HANDLE_OPTIONS,
      Tags: [
        { name: 'Action', value: 'Eval' },
        { name: 'Module', value: ''.padEnd(43, '1') },
      ],
      Data: lua,
    },
    handlerEnv,
  );
  if (evalRes.Error) {
    throw new Error(`Error loading aos: \n\n${evalRes.Error}`);
  }

  return {
    handle,
    memory: evalRes.Memory,
  };
}
