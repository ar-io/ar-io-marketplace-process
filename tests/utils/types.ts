import type AoLoader from '@permaweb/ao-loader';
import type { connect } from '@permaweb/aoconnect';
import type { AO_LOADER_HANDLER_ENV } from './constants.js';

/**
 * AO Client type from @permaweb/aoconnect
 */
export type AoClient = Awaited<ReturnType<typeof connect>>;

/**
 * Handle function returned by AoLoader
 */
export type HandleFunction = Awaited<ReturnType<typeof AoLoader>>;

/**
 * Handler environment configuration for AO Loader
 */
export type HandlerEnv = typeof AO_LOADER_HANDLER_ENV;

/**
 * Message tag structure used throughout AO
 */
export interface MessageTag {
  name: string;
  value: string;
}

/**
 * Result from AO handle execution
 */
export interface HandleResult {
  Messages: Message[];
  Spawns: any[];
  Output: any;
  Error?: string;
  Memory?: ArrayBufferLike;
  [key: string]: any;
}

/**
 * Result from process.send operation
 */
export interface SendResult {
  id: string;
  result: {
    Messages: Message[];
    Spawns: any[];
    Output: any;
    Error?: string;
    [key: string]: any;
  };
}

/**
 * AO Message structure
 */
export interface Message {
  Target: string;
  Data: string;
  Tags: MessageTag[];
  Anchor?: string;
  [key: string]: any;
}

/**
 * Parameters for creating an intent (Create-Order action is assumed)
 */
export interface CreateIntentParams {
  antId: string; // Required: ANT process ID for this intent
  orderType?: string;
  quantity?: string;
  price?: string;
  expirationTime: string; // Required: Unix timestamp (min 1h, max 30 days, fee rounded up to nearest hour)
  minimumPrice?: string;
  decreaseInterval?: string;
}

/**
 * Parameters for paginated intent queries
 */
export interface GetPaginatedIntentsParams {
  cursor?: string;
  limit?: number;
  sortBy?: string;
  sortOrder?: 'asc' | 'desc';
  filters?: Record<string, string>;
}

/**
 * Parameters for getting orders with flexible selectors
 */
export interface GetOrdersParams extends GetPaginatedIntentsParams {
  status?:
    | 'all'
    | 'listed'
    | 'completed'
    | 'active'
    | 'ready-for-settlement'
    | 'executed'
    | 'cancelled'
    | 'expired';
  ids?: string[]; // Array of order IDs to fetch specific orders
  dominantToken?: string; // Filter by dominant token in trading pair
  swapToken?: string; // Filter by swap token in trading pair
}

/**
 * Response from a read operation
 */
export interface ReadResponse {
  Action: string;
  Data: string;
  Tags: Record<string, string>;
  [key: string]: any;
}

/**
 * Paginated response structure
 */
export interface PaginatedResponse<T> {
  items: T[];
  limit: number;
  totalItems: number;
  hasMore: boolean;
  nextCursor?: string;
  sortBy: string;
  sortOrder: string;
}

/**
 * Intent structure
 */
export interface Intent {
  IntentId: string;
  Type: 'parent' | 'child';
  Status: 'pending' | 'active' | 'settling' | 'completed' | 'failed';
  Action: string;
  Initiator: string;
  CreatedAt: number;
  ResolvedAt?: number;
  ForwardedTags: Record<string, string>;
  ParentId?: string;
  Children?: Record<string, boolean>;
  ExpectedFrom?: string;
  FailureReason?: string;
}

/**
 * Intent statistics structure
 */
export interface IntentStats {
  total: number;
  byStatus: Record<string, number>;
  byType: Record<string, number>;
  byAction: Record<string, number>;
}

/**
 * Activity information structure
 */
export interface ActivityInfo {
  totalOrders: number;
  activeOrders: number;
  readyForSettlement: number;
  executedOrders: number;
  cancelledOrders: number;
  expiredOrders: number;
  listedOrders: number;
}

/**
 * UCM marketplace information structure
 */
export interface UCMInfo {
  totalPairs: number;
  accruedFees: string;
  arioTokenProcess: string;
}

/**
 * Info response structure from the marketplace
 */
export interface InfoResponse {
  name: string;
  processId: string;
  activity: ActivityInfo;
  intents: IntentStats;
  ucm: UCMInfo;
  whitelistedModules: string[];
}

/**
 * AO Loader options configuration
 */
export interface AoLoaderOptions {
  format: string;
  inputEncoding: string;
  outputEncoding: string;
  memoryLimit: string;
  computeLimit: string;
  extensions: any[];
}

/**
 * Default handle options for message processing
 */
export interface DefaultHandleOptions {
  Id: string;
  Target: string;
  Module: string;
  'Block-Height': number;
  Owner: string;
  From: string;
  Timestamp: number;
  'Hash-Chain': string;
  Data: string;
  Tags: MessageTag[];
}

/**
 * Parameters for initializing LocalAO
 */
export interface LocalAOInitParams {
  lua: string;
  wasmModule: Buffer | ArrayBuffer;
  aoLoaderOptions: AoLoaderOptions;
  handlerEnv?: HandlerEnv;
  memory?: ArrayBufferLike | null;
}

/**
 * Parameters for creating a local AO process
 */
export interface CreateLocalProcessParams {
  processId?: string;
  lua?: string;
  wasmModule?: Buffer | ArrayBuffer;
  aoLoaderOptions?: AoLoaderOptions;
  handlerEnv?: HandlerEnv;
}

/**
 * Parameters for AO dryrun
 */
export interface DryrunParams {
  data?: string;
  tags?: MessageTag[];
  [key: string]: any;
}

/**
 * Parameters for AO message
 */
export interface MessageParams {
  data?: string;
  tags?: MessageTag[];
  [key: string]: any;
}

/**
 * Parameters for AO result query
 */
export interface ResultParams {
  message: string;
  process: string;
}

/**
 * AOS loader creation parameters
 */
export interface CreateAosLoaderParams {
  lua: string;
  wasm?: Buffer | ArrayBuffer;
  options?: AoLoaderOptions;
  handlerEnv?: HandlerEnv;
}

/**
 * Result from creating AOS loader
 */
export interface CreateAosLoaderResult {
  handle: HandleFunction;
  memory: ArrayBufferLike;
}
