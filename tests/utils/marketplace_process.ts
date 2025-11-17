import type { AOProcess, AoSigner } from '@ar.io/sdk';
import type {
  CreateIntentParams,
  GetPaginatedIntentsParams,
  GetOrdersParams,
  InfoResponse,
  ReadResponse,
} from './types.js';

export class MarketplaceProcess {
  process: AOProcess;
	signer: AoSigner;

  constructor({ process, signer }: { process: AOProcess, signer: AoSigner }) {
    this.process = process;
    this.signer = signer;
  }

  async info(): Promise<InfoResponse> {
    const response: any = await this.process.read({
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
    const result = await this.process.read({ tags: filteredTags });
    // Wrap the response to include Action field for test expectations
    return {
      Action: 'Get-Paginated-Intents-Notice',
      Data: JSON.stringify(result),
      Tags: {},
    };
  }

  async getIntentById(intentId: string): Promise<ReadResponse> {
    try {
      const result = await this.process.read({
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
    const result = await this.process.read({ tags: filteredTags });
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
      const result = await this.process.read({
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
    return await this.process.read({
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
      const result = await this.process.read({ tags });
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
      const result = await this.process.read({ tags });
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
    return await this.process.read({
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
    return await this.process.read({ tags });
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
}
