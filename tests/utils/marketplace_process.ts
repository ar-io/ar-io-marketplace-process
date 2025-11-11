import type { AOProcess } from '@ar.io/sdk';
import type {
  CreateIntentParams,
  GetPaginatedIntentsParams,
  ReadResponse,
} from './types.js';

export class MarketplaceProcess {
  process: AOProcess;

  constructor({ process }: { process: AOProcess }) {
    this.process = process;
  }

  async info(): Promise<ReadResponse> {
    return await this.process.read({
      tags: [{ name: 'Action', value: 'Info' }],
    });
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
    return await this.process.read({ tags: filteredTags });
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
    return await this.process.read({ tags: filteredTags });
  }

  async getIntentById(intentId: string): Promise<ReadResponse> {
    return await this.process.read({
      tags: [
        { name: 'Action', value: 'Get-Intent-By-Id' },
        { name: 'Intent-Id', value: intentId },
      ],
    });
  }

  async getIntentStats(): Promise<ReadResponse> {
    return await this.process.read({
      tags: [{ name: 'Action', value: 'Get-Intent-Stats' }],
    });
  }

  // Activity handlers
  async getListedOrders(
    params?: GetPaginatedIntentsParams,
  ): Promise<ReadResponse> {
    const tags: Array<{ name: string; value: string | undefined }> = [
      { name: 'Action', value: 'Get-Listed-Orders' },
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
    return await this.process.read({ tags: filteredTags });
  }

  async getCompletedOrders(
    params?: GetPaginatedIntentsParams,
  ): Promise<ReadResponse> {
    const tags: Array<{ name: string; value: string | undefined }> = [
      { name: 'Action', value: 'Get-Completed-Orders' },
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
    return await this.process.read({ tags: filteredTags });
  }

  async getOrderById(orderId: string): Promise<ReadResponse> {
    return await this.process.read({
      tags: [
        { name: 'Action', value: 'Get-Order-By-Id' },
        { name: 'OrderId', value: orderId },
      ],
    });
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
    return await this.process.read({ tags });
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
    return await this.process.read({ tags });
  }

  async getVolume(): Promise<ReadResponse> {
    return await this.process.read({
      tags: [{ name: 'Action', value: 'Get-Volume' }],
    });
  }

  async getMostTradedTokens(count?: number): Promise<ReadResponse> {
    const tags: Array<{ name: string; value: string }> = [
      { name: 'Action', value: 'Get-Most-Traded-Tokens' },
    ];
    if (count !== undefined) {
      tags.push({ name: 'Count', value: count.toString() });
    }
    return await this.process.read({ tags });
  }

  async getActivityLengths(): Promise<ReadResponse> {
    return await this.process.read({
      tags: [{ name: 'Action', value: 'Get-Activity-Lengths' }],
    });
  }

  // UCM handlers
  async getOrderbookByPair(
    dominantToken: string,
    swapToken: string,
  ): Promise<ReadResponse> {
    return await this.process.read({
      tags: [
        { name: 'Action', value: 'Get-Orderbook-By-Pair' },
        { name: 'DominantToken', value: dominantToken },
        { name: 'SwapToken', value: swapToken },
      ],
    });
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
