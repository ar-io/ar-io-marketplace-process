import { AOProcess, AoSigner, ANT, ARIO } from '@ar.io/sdk';
import type {
  CreateIntentParams,
  GetPaginatedIntentsParams,
  GetOrdersParams,
  InfoResponse,
  ReadResponse,
  Intent,
} from './types.js';
import { ArioProcess } from './ario_process.js';

export class MarketplaceProcess {
  process: AOProcess;
	signer: AoSigner;
  dataItemSigner: any; // DataItemSigner for aoconnect calls
  cuUrl: string;
  walletAddress: string; // Needed for dry-run Owner field

  constructor({ 
    process, 
    signer, 
    dataItemSigner,
    walletAddress 
  }: { 
    process: AOProcess, 
    signer: AoSigner, 
    dataItemSigner?: any,
    walletAddress: string 
  }) {
    this.process = process;
    this.signer = signer;
    this.dataItemSigner = dataItemSigner || signer; // Fallback for backwards compat
    this.cuUrl = process.ao.CU_URL || 'https://cu.ardrive.io';
    this.walletAddress = walletAddress;
  }

  /**
   * Retry wrapper with exponential backoff for handling "Rate limit exceeded" errors
   * on freshly spawned processes.
   * Automatically includes fromAddress in readParams for CU dry-run Owner field.
   */
  private async readWithRetry(
    readParams: any,
    maxRetries: number = 10,
    baseDelayMs: number = 1000,
    maxDelayMs: number = 30000
  ): Promise<any> {
    let lastError: Error | null = null;

    for (let attempt = 0; attempt < maxRetries; attempt++) {
      try {
        // Always include fromAddress so SDK includes Owner/From in dry-run request
        const paramsWithOwner = { ...readParams, fromAddress: this.walletAddress };
        const result = await this.process.read(paramsWithOwner);
        return result;
      } catch (error: any) {
        lastError = error;
        
        // Check if it's a rate limit error
        const isRateLimit = error?.message?.includes('Rate limit exceeded');
        
        if (!isRateLimit || attempt === maxRetries - 1) {
          // Not a rate limit error, or we're out of retries
          throw error;
        }

        // Exponential backoff with cap: 1s, 2s, 4s, 8s, 16s, 30s (capped), 30s, ...
        const exponentialDelay = baseDelayMs * Math.pow(2, attempt);
        const delayMs = Math.min(exponentialDelay, maxDelayMs);
        console.log(`[Retry ${attempt + 1}/${maxRetries}] Rate limit hit, waiting ${delayMs}ms before retry...`);
        await new Promise(resolve => setTimeout(resolve, delayMs));
      }
    }

    throw lastError || new Error('Max retries exceeded');
  }

  /**
   * Poll the CU for a message result to check if it was processed
   */
  async pollCuForResult(messageId: string, maxAttempts: number = 5): Promise<any> {
    for (let i = 0; i < maxAttempts; i++) {
      try {
        const url = `${this.cuUrl}/result/${messageId}?process-id=${this.process.processId}`;
        const response = await fetch(url);
        const result = await response.json();
        
        if (!result.error) {
          return result;
        }
        
        // Wait before retrying
        if (i < maxAttempts - 1) {
          await new Promise(resolve => setTimeout(resolve, 2000));
        }
      } catch (error) {
        console.log(`[CU Poll] Attempt ${i + 1}/${maxAttempts} failed:`, error);
      }
    }
    return null;
  }

  /**
   * Check the CU results endpoint for recent messages to this process
   * to see if any Credit-Notices with the given Intent-Id were received
   */
  async checkForCreditNoticeProcessing(intentId: string): Promise<boolean> {
    try {
      const url = `${this.cuUrl}/results/${this.process.processId}?limit=20&sort=DESC`;
      const response = await fetch(url);
      const data = await response.json();
      
      if (!data.edges) {
        return false;
      }
      
      // Look for Credit-Notice messages with this Intent-Id
      for (const edge of data.edges) {
        const tags = edge.node?.message?.Tags || [];
        const hasAction = tags.some((t: any) => t.name === 'Action' && t.value === 'Credit-Notice');
        const hasIntentId = tags.some((t: any) => t.name === 'X-Intent-Id' && t.value === intentId);
        
        if (hasAction && hasIntentId) {
          console.log(`✓ Found Credit-Notice with Intent-Id ${intentId} at message ${edge.node.message.Id}`);
          return true;
        }
      }
      
      return false;
    } catch (error) {
      console.log('[CU Check] Failed to check for Credit-Notice:', error);
      return false;
    }
  }

  async info(): Promise<InfoResponse> {
    const response: any = await this.readWithRetry({
      tags: [{ name: 'Action', value: 'Info' }],
    });
    return response as InfoResponse;
  }

  async createIntent({
    action,
    orderType,
    swapToken,
    quantity,
    price,
    expirationTime,
    minimumPrice,
    decreaseInterval,
    requestedOrderId,
    orderId,
    dominantToken,
  }: CreateIntentParams): Promise<ReadResponse> {
    const tags: Array<{ name: string; value: string | undefined }> = [
      { name: 'Action', value: 'Create-Intent' },
      { name: 'X-Intent-Action', value: action },
      { name: 'X-Intent-Order-Type', value: orderType },
      { name: 'X-Intent-Swap-Token', value: swapToken },
      { name: 'X-Intent-Quantity', value: quantity },
      { name: 'X-Intent-Price', value: price },
      { name: 'X-Intent-Expiration-Time', value: expirationTime },
      { name: 'X-Intent-Minimum-Price', value: minimumPrice },
      { name: 'X-Intent-Decrease-Interval', value: decreaseInterval },
      { name: 'X-Intent-Requested-Order-Id', value: requestedOrderId },
      { name: 'X-Intent-Order-Id', value: orderId },
      { name: 'X-Intent-Dominant-Token', value: dominantToken },
    ];

    const filteredTags = tags.filter(
      (tag): tag is { name: string; value: string } => tag.value !== undefined,
    );
    try {
      // Use send() to actually create the intent (modifies state)
      const { result } = (await this.process.send({
        tags: filteredTags,
				signer: this.signer,
      })) as any;

      // The handler returns data directly as the result object
      // Wrap it in our expected response format
      return {
        Action: 'Create-Intent-Notice',
        Data: JSON.stringify(result),
        Tags: result,
      };
    } catch (error: any) {
      // Handler threw an error, wrap it as Invalid notice
      return {
        Action: 'Invalid-Create-Intent-Notice',
        Data: error.message || String(error),
        Tags: { Error: 'Create-Intent-Error' },
      };
    }
  }

  async getPaginatedIntents({
    cursor,
    limit,
    sortBy,
    sortOrder,
    filters,
  }: GetPaginatedIntentsParams = {}): Promise<ReadResponse> {
    const tags: Array<{ name: string; value: string | undefined }> = [
      { name: 'Action', value: 'Get-Paginated-Intents' },
      { name: 'Cursor', value: cursor },
      { name: 'Limit', value: limit?.toString() },
      { name: 'Sort-By', value: sortBy },
      { name: 'Sort-Order', value: sortOrder },
      { name: 'Filters', value: JSON.stringify(filters) },
    ];
    const filteredTags = tags.filter(
      (tag): tag is { name: string; value: string } => tag.value !== undefined,
    );
    const result = await this.readWithRetry({ tags: filteredTags });
    // Wrap the response to include Action field for test expectations
    return {
      Action: 'Get-Paginated-Intents-Notice',
      Data: JSON.stringify(result),
      Tags: {},
    };
  }

  async getIntentById(intentId: string): Promise<ReadResponse> {
    try {
      const result = await this.readWithRetry({
        tags: [
          { name: 'Action', value: 'Get-Intent-By-Id' },
          { name: 'Intent-Id', value: intentId },
        ],
      });
      // Wrap the response to include Action field for test expectations
      return {
        Action: 'Get-Intent-By-Id-Notice',
        Data: JSON.stringify(result),
        Tags: {},
      };
    } catch (error: any) {
      // Handler threw an error, wrap it as Invalid notice
      return {
        Action: 'Invalid-Get-Intent-By-Id-Notice',
        Data: error.message || String(error),
        Tags: { Error: 'Get-Intent-By-Id-Error' },
      };
    }
  }

  // Activity handlers
  /**
   * Get orders with flexible selectors
   * @param params - Parameters for filtering and pagination
   * @returns Orders matching the criteria
   */
  async getOrders(params?: GetOrdersParams): Promise<ReadResponse> {
    const tags: Array<{ name: string; value: string | undefined }> = [
      { name: 'Action', value: 'Get-Orders' },
      { name: 'Status', value: params?.status },
      { name: 'Ids', value: params?.ids?.join(',') },
      { name: 'DominantToken', value: params?.dominantToken },
      { name: 'SwapToken', value: params?.swapToken },
      { name: 'Cursor', value: params?.cursor },
      { name: 'Limit', value: params?.limit?.toString() },
      { name: 'Sort-By', value: params?.sortBy },
      { name: 'Sort-Order', value: params?.sortOrder },
      {
        name: 'Filters',
        value: params?.filters ? JSON.stringify(params.filters) : undefined,
      },
    ];
    const filteredTags = tags.filter(
      (tag): tag is { name: string; value: string } => tag.value !== undefined,
    );
    const result = await this.readWithRetry({ tags: filteredTags });
    // Wrap the response to include Action field for test expectations
    return {
      Action: 'Get-Orders-Notice',
      Data: JSON.stringify(result),
      Tags: {},
    };
  }

  /**
   * Get a single order by ID
   * @param orderId - The order ID to fetch
   * @returns The order if found
   */
  async getOrder(orderId: string): Promise<ReadResponse> {
    try {
      const result = await this.readWithRetry({
        tags: [
          { name: 'Action', value: 'Get-Order' },
          { name: 'Order-Id', value: orderId },
        ],
      });
      // Wrap the response to include Action field for test expectations
      return {
        Action: 'Get-Order-Notice',
        Data: JSON.stringify(result),
        Tags: {},
      };
    } catch (error: any) {
      // Handler threw an error, wrap it as Invalid notice
      return {
        Action: 'Invalid-Get-Order-Notice',
        Data: error.message || String(error),
        Tags: { Error: 'Get-Order-Error' },
      };
    }
  }

  async getOrderCountsByAddress(address: string): Promise<ReadResponse> {
    return await this.readWithRetry({
      tags: [
        { name: 'Action', value: 'Get-Order-Counts-By-Address' },
        { name: 'Address', value: address },
      ],
    });
  }

  async cancelOrder(orderId: string, groupId?: string): Promise<ReadResponse> {
    const tags: Array<{ name: string; value: string }> = [
      { name: 'Action', value: 'Cancel-Order' },
      { name: 'Order-Id', value: orderId },
    ];
    if (groupId) {
      tags.push({ name: 'X-Group-ID', value: groupId });
    }
    try {
      const result = await this.readWithRetry({ tags });
      return {
        Action: 'Cancel-Order-Notice',
        Data: JSON.stringify(result),
        Tags: {},
      };
    } catch (error: any) {
      return {
        Action: 'Invalid-Cancel-Order-Notice',
        Data: error.message || String(error),
        Tags: { Error: 'Cancel-Order-Error' },
      };
    }
  }

  async settleAuction(params: {
    orderId: string;
    dominantToken?: string;
    swapToken?: string;
  }): Promise<ReadResponse> {
    const tags: Array<{ name: string; value: string }> = [
      { name: 'Action', value: 'Settle-Auction' },
      { name: 'Order-Id', value: params.orderId },
    ];
    if (params.dominantToken) {
      tags.push({ name: 'Dominant-Token', value: params.dominantToken });
    }
    if (params.swapToken) {
      tags.push({ name: 'Swap-Token', value: params.swapToken });
    }
    try {
      const result = await this.readWithRetry({ tags });
      return {
        Action: 'Settle-Auction-Notice',
        Data: JSON.stringify(result),
        Tags: {},
      };
    } catch (error: any) {
      return {
        Action: 'Invalid-Settle-Auction-Notice',
        Data: error.message || String(error),
        Tags: { Error: 'Settle-Auction-Error' },
      };
    }
  }

  /**
   * Get volume using the unified activity handler
   * @returns Volume information
   */
  async getVolume(): Promise<ReadResponse> {
    return await this.readWithRetry({
      tags: [
        { name: 'Action', value: 'Get-Activity' },
        { name: 'Query-Type', value: 'volume' },
      ],
    });
  }

  /**
   * Get most traded tokens using the unified activity handler
   * @param count - Number of tokens to return (optional)
   * @returns Most traded tokens
   */
  async getMostTradedTokens(count?: number): Promise<ReadResponse> {
    const tags: Array<{ name: string; value: string }> = [
      { name: 'Action', value: 'Get-Activity' },
      { name: 'Query-Type', value: 'most-traded-tokens' },
    ];
    if (count !== undefined) {
      tags.push({ name: 'Count', value: count.toString() });
    }
    return await this.readWithRetry({ tags });
  }

  // UCM handlers

  /**
   * Get orders for a specific trading pair
   * @param dominantToken - Dominant token address
   * @param swapToken - Swap token address
   * @returns Orders for the trading pair
   */
  async getOrdersByPair(
    dominantToken: string,
    swapToken: string,
  ): Promise<ReadResponse> {
    return this.getOrders({ dominantToken, swapToken });
  }

  /**
   * @deprecated Use getOrdersByPair or getOrders instead
   */
  async getOrderbookByPair(
    dominantToken: string,
    swapToken: string,
  ): Promise<ReadResponse> {
    return this.getOrdersByPair(dominantToken, swapToken);
  }

  // Simulated Credit-Notice for testing
  async simulateCreditNotice(params: {
    sender: string;
    quantity: string;
    dominantToken: string;
    swapToken?: string;
    orderType?: 'fixed' | 'dutch' | 'english';
    price?: string;
    expirationTime?: string;
    minimumPrice?: string;
    decreaseInterval?: string;
    requestedOrderId?: string;
    intentId?: string;
  }): Promise<any> {
    const tags: Array<{ name: string; value: string }> = [
      { name: 'Action', value: 'Credit-Notice' },
      { name: 'Sender', value: params.sender },
      { name: 'Quantity', value: params.quantity },
      { name: 'X-Dominant-Token', value: params.dominantToken },
    ];

    if (params.swapToken)
      tags.push({ name: 'X-Swap-Token', value: params.swapToken });
    if (params.orderType)
      tags.push({ name: 'X-Order-Type', value: params.orderType });
    if (params.price) tags.push({ name: 'X-Price', value: params.price });
    if (params.expirationTime)
      tags.push({ name: 'X-Expiration-Time', value: params.expirationTime });
    if (params.minimumPrice)
      tags.push({ name: 'X-Minimum-Price', value: params.minimumPrice });
    if (params.decreaseInterval)
      tags.push({
        name: 'X-Decrease-Interval',
        value: params.decreaseInterval,
      });
    if (params.requestedOrderId)
      tags.push({
        name: 'X-Requested-Order-Id',
        value: params.requestedOrderId,
      });
    if (params.intentId)
      tags.push({ name: 'X-Intent-Id', value: params.intentId });

    return await this.process.ao.message({ tags });
  }

  // High-level helper methods for E2E testing

  /**
   * Get orders filtered by status
   */
  async getOrdersByStatus(
    status: GetOrdersParams['status'],
  ): Promise<ReadResponse> {
    return this.getOrders({ status });
  }

  /**
   * Get intents filtered by status
   */
  async getIntentsByStatus(status: string): Promise<ReadResponse> {
    const result = await this.getPaginatedIntents({
      filters: { status },
    });

    return result;
  }

  /**
   * Poll until an order reaches a specific status
   */
  async waitForOrderStatus(
    orderId: string,
    expectedStatus: string,
    timeout: number = 450_000,
  ): Promise<any> {
    const startTime = Date.now();
    const interval = 2000;

    while (Date.now() - startTime < timeout) {
      try {
        const result = await this.getOrder(orderId);
        const data = JSON.parse(result.Data);

        if (data.status === expectedStatus) {
          return data;
        }
      } catch (error) {
        // Order might not exist yet
      }

      await new Promise((resolve) => setTimeout(resolve, interval));
    }

    throw new Error(
      `Timeout waiting for order ${orderId} to reach status ${expectedStatus}`,
    );
  }

  /**
   * Poll until an intent reaches a specific status
   */
  async waitForIntentStatus(
    intentId: string,
    expectedStatus: string,
    timeout: number = 450_000,
  ): Promise<Intent> {
    const startTime = Date.now();
    const interval = 2000;

    while (Date.now() - startTime < timeout) {
      try {
        const result = await this.getIntentById(intentId);
        const data = JSON.parse(result.Data);

        if (data.status === expectedStatus) {
          return data as Intent;
        }
      } catch (error) {
        // Intent might not exist yet or error occurred
      }

      await new Promise((resolve) => setTimeout(resolve, interval));
    }

    throw new Error(
      `Timeout waiting for intent ${intentId} to reach status ${expectedStatus}`,
    );
  }

  /**
   * List an ANT at a fixed price
   * @param antProcessId - The ANT process ID
   * @param price - The price in swap token units
   * @param swapToken - The swap token process ID (e.g., ARIO)
   * @param logger - Optional test logger
   * @returns Object with intentId, orderId, and txId
   */
  async listAntForFixedPrice(
    antProcessId: string,
    price: string,
    swapToken: string,
    logger?: any,
  ): Promise<{ intentId: string; orderId?: string; txId: string }> {
    // Step 1: Create intent first (required by marketplace)
    const intentResult = await this.createIntent({
      action: 'Create-Order',
      orderType: 'fixed',
      swapToken,
      quantity: '1',
      price,
      dominantToken: antProcessId,
    });

    const intentData = JSON.parse(intentResult.Data);
    const intentId = intentData['Intent-Id'];

    if (!intentId) {
      throw new Error('Failed to create intent: No Intent-Id returned');
    }

    // Log intent creation
    if (logger) {
      logger.updateIntent(intentId, {
        status: 'pending',
        action: 'Create-Order',
        relatedMessages: [],
      });
    }

        // Step 2: Transfer ANT to marketplace with intent ID
        const tags = [
          { name: 'Action', value: 'Transfer' },
          { name: 'Recipient', value: this.process.processId },
          { name: 'Target', value: this.process.processId }, // Explicit Target for Credit-Notice
          { name: 'Quantity', value: '1' },
          { name: 'X-Intent-Id', value: intentId }, // Required!
          { name: 'X-Order-Action', value: 'Create-Order' }, // Required!
          { name: 'X-Dominant-Token', value: antProcessId }, // Required! Must match From
          { name: 'X-Order-Type', value: 'fixed' },
          { name: 'X-Price', value: price },
          { name: 'X-Swap-Token', value: swapToken },
        ];

    let txId: string;
    
    if (logger) {
      txId = await logger.logMessage({
        action: 'Transfer ANT (List Fixed Price)',
        processId: antProcessId,
        tags,
        messageFn: async () => {
          return await this.process.ao.message({
            process: antProcessId,
            signer: this.signer,
            tags,
          });
        },
      });
    } else {
      txId = await this.process.ao.message({
        process: antProcessId,
        signer: this.signer,
        tags,
      });
    }

    return {
      intentId,
      txId,
    };
  }

  /**
   * List an ANT for a Dutch auction
   */
  async listAntForDutchAuction(
    antProcessId: string,
    params: {
      startPrice: string;
      minimumPrice: string;
      decreaseInterval: string;
      expirationTime: string;
      swapToken: string;
    },
  ): Promise<{ intentId: string; orderId?: string; txId: string }> {
    // Create intent
    const intentResult = await this.createIntent({
      action: 'Create-Order',
      orderType: 'dutch',
      swapToken: params.swapToken,
      quantity: '1',
      price: params.startPrice,
      minimumPrice: params.minimumPrice,
      decreaseInterval: params.decreaseInterval,
      expirationTime: params.expirationTime,
    });

    const intentData = JSON.parse(intentResult.Data);
    const intentId = intentData['Intent-Id'];

    // Instantiate ANT process
    const ant = ANT.init({
      process: new AOProcess({
        ao: this.process.ao,
        processId: antProcessId,
      }),
      signer: this.signer,
    });

    // Transfer ANT to marketplace
    const transferResult = await ant.transfer({
      target: this.process.processId,
      quantity: 1,
    });

    return {
      intentId,
      txId: transferResult.id,
    };
  }

  /**
   * List an ANT for an English auction
   */
  async listAntForEnglishAuction(
    antProcessId: string,
    params: {
      startingBid: string;
      expirationTime: string;
      swapToken: string;
    },
  ): Promise<{ intentId: string; orderId?: string; txId: string }> {
    // Create intent
    const intentResult = await this.createIntent({
      action: 'Create-Order',
      orderType: 'english',
      swapToken: params.swapToken,
      quantity: '1',
      price: params.startingBid,
      expirationTime: params.expirationTime,
    });

    const intentData = JSON.parse(intentResult.Data);
    const intentId = intentData['Intent-Id'];

    // Instantiate ANT process
    const ant = ANT.init({
      process: new AOProcess({
        ao: this.process.ao,
        processId: antProcessId,
      }),
      signer: this.signer,
    });

    // Transfer ANT to marketplace
    const transferResult = await ant.transfer({
      target: this.process.processId,
      quantity: 1,
    });

    return {
      intentId,
      txId: transferResult.id,
    };
  }

  /**
   * Buy a fixed price listing
   * @param arioProcessId - The ARIO token process ID
   * @param orderId - The order ID to buy
   * @param amount - The amount of ARIO to send
   * @param logger - Optional test logger
   * @returns Object with intentId and txId
   */
  async buyFixedPriceListing(
    arioProcessId: string,
    orderId: string,
    amount: string,
    logger?: any,
  ): Promise<{ intentId: string; txId: string }> {
    // Step 0: Get the order to find the ANT process ID (swap token)
    const orderResult = await this.getOrder(orderId);
    if (orderResult.Action === 'Invalid-Get-Order-Notice') {
      throw new Error(`Failed to get order: ${orderResult.Data}`);
    }
    const orderData = JSON.parse(orderResult.Data);
    const antProcessId = orderData.dominantToken; // The ANT being sold

    // Step 1: Create intent first (required by marketplace)
    const intentResult = await this.createIntent({
      action: 'Create-Order',
      requestedOrderId: orderId,
      swapToken: arioProcessId, // Required for buy intents!
      quantity: amount, // Required for buy intents!
    });

    // Handle both success and error cases
    if (intentResult.Action === 'Invalid-Create-Intent-Notice') {
      throw new Error(`Failed to create buy intent: ${intentResult.Data}`);
    }

    const intentData = JSON.parse(intentResult.Data);
    const intentId = intentData['Intent-Id'];

    if (!intentId) {
      throw new Error('Failed to create buy intent: No Intent-Id returned');
    }

    // Step 2: Send ARIO transfer with intent ID
    const tags = [
      { name: 'Action', value: 'Transfer' },
      { name: 'Recipient', value: this.process.processId },
      { name: 'Quantity', value: amount },
      { name: 'X-Intent-Id', value: intentId }, // Required!
      { name: 'X-Order-Action', value: 'Create-Order' }, // Required!
      { name: 'X-Dominant-Token', value: arioProcessId }, // Required! Must match From
      { name: 'X-Swap-Token', value: antProcessId }, // Required! The ANT being purchased
      { name: 'X-Requested-Order-Id', value: orderId },
    ];

    let txId: string;

    if (logger) {
      txId = await logger.logMessage({
        action: 'Transfer ARIO (Buy Fixed Price)',
        processId: arioProcessId,
        tags,
        messageFn: async () => {
          return await this.process.ao.message({
            process: arioProcessId,
            signer: this.signer,
            tags,
          });
        },
      });
    } else {
      txId = await this.process.ao.message({
        process: arioProcessId,
        signer: this.signer,
        tags,
      });
    }

    return {
      intentId,
      txId,
    };
  }

  /**
   * Place a bid on an English auction
   * @param arioProcessId - The ARIO token process ID
   * @param orderId - The auction order ID
   * @param bidAmount - The bid amount in ARIO
   * @returns Object with intentId and txId
   */
  async bidOnEnglishAuction(
    arioProcessId: string,
    orderId: string,
    bidAmount: string,
  ): Promise<{ intentId: string; txId: string }> {
    // Create intent
    const intentResult = await this.createIntent({
      action: 'Create-Order',
      requestedOrderId: orderId,
    });

    const intentData = JSON.parse(intentResult.Data);
    const intentId = intentData['Intent-Id'];

    // Instantiate ARIO process
    const arioProcess = new ArioProcess({
      process: new AOProcess({
        ao: this.process.ao,
        processId: arioProcessId,
      }),
      signer: this.signer,
      dataItemSigner: this.dataItemSigner,
    });

    // Transfer ARIO to marketplace as bid
    const { txId } = await arioProcess.transferToMarketplace(
      this.process.processId,
      bidAmount,
      [
        { name: 'X-Requested-Order-Id', value: orderId },
        { name: 'X-Intent-Id', value: intentId },
        { name: 'X-Action', value: 'Bid' },
      ],
    );

    return {
      intentId,
      txId,
    };
  }

  /**
   * Wait for an intent to complete (reached completed or failed status)
   */
  async waitForIntentCompletion(
    intentId: string,
    timeout: number = 450_000,
  ): Promise<Intent> {
    const startTime = Date.now();
    const interval = 2000;

    while (Date.now() - startTime < timeout) {
      try {
        const result = await this.getIntentById(intentId);
        const intent = JSON.parse(result.Data) as Intent;

        if (intent.Status === 'completed' || intent.Status === 'failed') {
          return intent;
        }
      } catch (error) {
        // Intent might not exist yet
      }

      await new Promise((resolve) => setTimeout(resolve, interval));
    }

    throw new Error(`Timeout waiting for intent ${intentId} to complete`);
  }

  /**
   * Wait for any new orders to appear (polling)
   * Useful after sending a transfer message
   */
  async waitForNewOrders(
    previousCount: number = 0,
    timeout: number = 450_000,
    intentId?: string,
  ): Promise<any> {
    const startTime = Date.now();
    const interval = 5000; // Check every 5 seconds
    let checkCount = 0;

    if (intentId) {
      console.log(`Waiting for order from Intent ${intentId} (count to increase from ${previousCount})...`);
    } else {
      console.log(`Waiting for order count to increase from ${previousCount}...`);
    }

    while (Date.now() - startTime < timeout) {
      try {
        const info = await this.info();
        const currentCount = info.activity.totalOrders;
        const currentIntents = info.intents.total;
        checkCount++;

        console.log(`[Check #${checkCount}] Orders: ${currentCount} (need > ${previousCount}), Intents: ${currentIntents}, ${Math.round((Date.now() - startTime) / 1000)}s elapsed`);

        if (currentCount > previousCount) {
          // New order appeared, fetch orders
          const orders = await this.getOrders({ status: 'listed' });
          console.log('✓ New order detected!');
          return JSON.parse(orders.Data);
        }
      } catch (error) {
        console.warn('Error checking for new orders:', error);
      }

      await new Promise((resolve) => setTimeout(resolve, interval));
    }

    console.error(`Timeout: Order count did not increase after ${timeout}ms (${checkCount} checks)`);
    throw new Error(`Timeout waiting for new orders after ${timeout}ms`);
  }

  /**
   * Wait for order count to change (useful for verifying execution/cancellation)
   */
  async waitForOrderCountChange(
    status: string,
    previousCount: number,
    timeout: number = 450_000,
  ): Promise<any> {
    const startTime = Date.now();
    const interval = 3000;

    while (Date.now() - startTime < timeout) {
      try {
        const info = await this.info();
        const statusField = status + 'Orders' as keyof typeof info.activity;
        const currentCount = info.activity[statusField];

        if (currentCount !== previousCount) {
          return info;
        }
      } catch (error) {
        console.warn('Error checking order count:', error);
      }

      await new Promise((resolve) => setTimeout(resolve, interval));
    }

    throw new Error(`Timeout waiting for ${status} order count to change`);
  }

  /**
   * Deposit ARIO to the marketplace (simulates Credit-Notice from ARIO token process)
   * Returns the message ID for verification
   */
  async depositArio(amount: string, arioProcessId: string, address?: string): Promise<{ messageId: string }> {
    // If no address is provided, use empty string to deposit to msg.From
    // The Sender tag will be set from the message's From field
    const depositAddress = address || '';
    
    const tags: MessageTag[] = [
      { name: 'Action', value: 'Credit-Notice' },
      { name: 'Sender', value: depositAddress },
      { name: 'Quantity', value: amount },
      { name: 'X-Action', value: 'Deposit' },
    ];

    // Use ao.message directly to set From field
    const messageId = await this.process.ao.message({
      process: this.process.processId,
      tags,
      signer: this.signer,
      From: arioProcessId, // Credit-Notice must come FROM the ARIO token process
    } as any);

    return { messageId };
  }

  /**
   * Verify a Credit-Notice was processed by checking its result
   * Uses GraphQL to find the message and CU to get the result
   */
  async verifyCreditNoticeProcessed(messageId: string, maxAttempts: number = 10): Promise<any> {
    const graphqlUrl = this.process.ao.GRAPHQL_URL || 'http://localhost:4000/graphql';
    
    for (let attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        // Query GraphQL for the message by ID
        const gqlQuery = {
          query: `
            query GetMessage($messageId: ID!) {
              transaction(id: $messageId) {
                id
                tags {
                  name
                  value
                }
              }
            }
          `,
          variables: { messageId }
        };

        const gqlResponse = await fetch(graphqlUrl, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(gqlQuery),
        });

        if (!gqlResponse.ok) {
          console.log(`[Attempt ${attempt + 1}/${maxAttempts}] GraphQL query failed, waiting 2s...`);
          await new Promise(resolve => setTimeout(resolve, 2000));
          continue;
        }

        const gqlData = await gqlResponse.json();
        if (!gqlData.data?.transaction) {
          console.log(`[Attempt ${attempt + 1}/${maxAttempts}] Message not yet in GraphQL, waiting 2s...`);
          await new Promise(resolve => setTimeout(resolve, 2000));
          continue;
        }

        // Get the result from CU
        const resultUrl = `${this.cuUrl}/result/${messageId}?process-id=${this.process.processId}`;
        const resultResponse = await fetch(resultUrl);
        
        if (!resultResponse.ok) {
          console.log(`[Attempt ${attempt + 1}/${maxAttempts}] CU result not ready, waiting 2s...`);
          await new Promise(resolve => setTimeout(resolve, 2000));
          continue;
        }

        const result = await resultResponse.json();
        
        // Check if the Credit-Notice was processed
        if (result.Messages && result.Messages.length > 0) {
          const creditNoticeMessage = result.Messages.find((m: any) => 
            m.Tags?.some((t: any) => t.name === 'Action' && t.value === 'Credit-Notice-Processed')
          );
          
          if (creditNoticeMessage) {
            console.log(`✓ Credit-Notice processed successfully`);
            return creditNoticeMessage;
          }
        }

        console.log(`[Attempt ${attempt + 1}/${maxAttempts}] Credit-Notice not yet processed, waiting 2s...`);
        await new Promise(resolve => setTimeout(resolve, 2000));
        
      } catch (error) {
        console.log(`[Attempt ${attempt + 1}/${maxAttempts}] Error checking Credit-Notice:`, error instanceof Error ? error.message : String(error));
        await new Promise(resolve => setTimeout(resolve, 2000));
      }
    }

    throw new Error(`Credit-Notice ${messageId} was not processed after ${maxAttempts} attempts`);
  }

  /**
   * Withdraw ARIO from the marketplace back to user
   */
  async withdrawArio(quantity: string): Promise<ReadResponse> {
    const tags: MessageTag[] = [
      { name: 'Action', value: 'Withdraw-Ario' },
      { name: 'Quantity', value: quantity },
    ];

    try {
      const { result } = (await this.process.send({
        tags,
        signer: this.signer,
      })) as any;

      return {
        Action: 'Withdraw-Ario-Notice',
        Data: JSON.stringify(result || {}),
        Tags: {},
      };
    } catch (error: any) {
      return {
        Action: 'Invalid-Withdraw-Notice',
        Data: error.message || String(error),
        Tags: { Error: 'Withdraw-Error' },
      };
    }
  }

  /**
   * Get ARIO balance for an address in the marketplace
   */
  async getMarketplaceBalance(address?: string): Promise<string> {
    const targetAddress = address || this.signer.address;
    
    try {
      const result = await this.readWithRetry({
        tags: [
          { name: 'Action', value: 'Get-Balance' },
          { name: 'Address', value: targetAddress },
        ],
      });

      // Result should be JSON with balance field
      if (typeof result === 'object' && 'balance' in result) {
        return (result as any).balance || '0';
      }
      
      return '0';
    } catch (error) {
      console.error('Error getting marketplace balance:', error);
      return '0';
    }
  }
}
