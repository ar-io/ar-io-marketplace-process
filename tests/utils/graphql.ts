import { config } from 'dotenv';

config();

/**
 * GraphQL client configuration
 */
const GRAPHQL_URL = process.env.GRAPHQL_URL || 'https://arweave.net/graphql';
const DEFAULT_TIMEOUT = 30_000; // 30 seconds
const DEFAULT_POLL_INTERVAL = 2000; // 2 seconds

/**
 * Message tag structure
 */
export interface MessageTag {
  name: string;
  value: string;
}

/**
 * GraphQL message structure
 */
export interface GraphQLMessage {
  id: string;
  tags: MessageTag[];
  recipient: string;
  owner: { address: string };
  block?: { height: number; timestamp: number };
  data?: { size: number };
}

/**
 * GraphQL edge structure
 */
export interface GraphQLEdge {
  node: GraphQLMessage;
  cursor: string;
}

/**
 * GraphQL query response
 */
export interface GraphQLResponse {
  data?: {
    transactions: {
      edges: GraphQLEdge[];
      pageInfo: {
        hasNextPage: boolean;
      };
    };
  };
  errors?: Array<{ message: string }>;
}

/**
 * Query filter options
 */
export interface QueryFilters {
  tags?: Array<{ name: string; values: string[] }>;
  recipients?: string[];
  owners?: string[];
  minBlock?: number;
  maxBlock?: number;
}

/**
 * Execute a GraphQL query against Arweave
 */
async function executeGraphQLQuery(query: string): Promise<GraphQLResponse> {
  const response = await fetch(GRAPHQL_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ query }),
  });

  if (!response.ok) {
    throw new Error(`GraphQL request failed: ${response.statusText}`);
  }

  return await response.json();
}

/**
 * Build GraphQL query for messages with tags
 */
function buildTagQuery(tags: Array<{ name: string; values: string[] }>): string {
  return tags
    .map((tag) => {
      const values = tag.values.map((v) => `"${v}"`).join(', ');
      return `{ name: "${tag.name}", values: [${values}] }`;
    })
    .join(', ');
}

/**
 * Query messages by tags
 */
export async function queryMessagesByTags(
  tags: MessageTag[],
  processId?: string,
  filters?: QueryFilters,
): Promise<GraphQLMessage[]> {
  const tagFilters = tags.map((tag) => ({
    name: tag.name,
    values: [tag.value],
  }));

  if (filters?.tags) {
    tagFilters.push(...filters.tags);
  }

  const recipientFilter = processId ? `recipients: ["${processId}"]` : '';
  const tagQuery = buildTagQuery(tagFilters);

  const query = `
    query {
      transactions(
        first: 100
        ${recipientFilter}
        tags: [${tagQuery}]
        sort: HEIGHT_DESC
      ) {
        edges {
          node {
            id
            tags {
              name
              value
            }
            recipient
            owner {
              address
            }
            block {
              height
              timestamp
            }
          }
          cursor
        }
        pageInfo {
          hasNextPage
        }
      }
    }
  `;

  const response = await executeGraphQLQuery(query);

  if (response.errors) {
    throw new Error(
      `GraphQL errors: ${response.errors.map((e) => e.message).join(', ')}`,
    );
  }

  return response.data?.transactions.edges.map((edge) => edge.node) || [];
}

/**
 * Query all messages related to an intent
 */
export async function queryIntentMessages(
  intentId: string,
): Promise<GraphQLMessage[]> {
  return queryMessagesByTags([{ name: 'X-Intent-Id', value: intentId }]);
}

/**
 * Query Credit-Notice messages
 */
export async function queryCreditNotices(
  processId: string,
  filters?: {
    intentId?: string;
    sender?: string;
    minQuantity?: string;
  },
): Promise<GraphQLMessage[]> {
  const tags: MessageTag[] = [{ name: 'Action', value: 'Credit-Notice' }];

  if (filters?.intentId) {
    tags.push({ name: 'X-Intent-Id', value: filters.intentId });
  }

  if (filters?.sender) {
    tags.push({ name: 'Sender', value: filters.sender });
  }

  const messages = await queryMessagesByTags(tags, processId);

  // Additional filtering by quantity if needed
  if (filters?.minQuantity) {
    const minQty = BigInt(filters.minQuantity);
    return messages.filter((msg) => {
      const qtyTag = msg.tags.find((t) => t.name === 'Quantity');
      if (!qtyTag) return false;
      return BigInt(qtyTag.value) >= minQty;
    });
  }

  return messages;
}

/**
 * Query Debit-Notice messages
 */
export async function queryDebitNotices(
  processId: string,
  filters?: {
    intentId?: string;
    recipient?: string;
    minQuantity?: string;
  },
): Promise<GraphQLMessage[]> {
  const tags: MessageTag[] = [{ name: 'Action', value: 'Debit-Notice' }];

  if (filters?.intentId) {
    tags.push({ name: 'X-Intent-Id', value: filters.intentId });
  }

  if (filters?.recipient) {
    tags.push({ name: 'Recipient', value: filters.recipient });
  }

  const messages = await queryMessagesByTags(tags, processId);

  // Additional filtering by quantity if needed
  if (filters?.minQuantity) {
    const minQty = BigInt(filters.minQuantity);
    return messages.filter((msg) => {
      const qtyTag = msg.tags.find((t) => t.name === 'Quantity');
      if (!qtyTag) return false;
      return BigInt(qtyTag.value) >= minQty;
    });
  }

  return messages;
}

/**
 * Generic polling utility that repeatedly executes a query function
 */
export async function pollForMessage<T>(
  queryFn: () => Promise<T | null>,
  options: {
    timeout?: number;
    interval?: number;
    description?: string;
  } = {},
): Promise<T> {
  const timeout = options.timeout || DEFAULT_TIMEOUT;
  const interval = options.interval || DEFAULT_POLL_INTERVAL;
  const description = options.description || 'message';

  const startTime = Date.now();
  let lastError: Error | null = null;

  while (Date.now() - startTime < timeout) {
    try {
      const result = await queryFn();
      if (result !== null) {
        return result;
      }
    } catch (error) {
      lastError = error as Error;
      console.warn(
        `Poll attempt failed for ${description}: ${lastError.message}`,
      );
    }

    // Wait before next poll
    await new Promise((resolve) => setTimeout(resolve, interval));
  }

  throw new Error(
    `Timeout waiting for ${description} after ${timeout}ms${lastError ? `: ${lastError.message}` : ''}`,
  );
}

/**
 * Wait for an intent to be resolved (completed or failed)
 */
export async function waitForIntentResolution(
  intentId: string,
  timeout: number = DEFAULT_TIMEOUT,
): Promise<{
  intentId: string;
  status: string;
  messages: GraphQLMessage[];
}> {
  return pollForMessage(
    async () => {
      const messages = await queryIntentMessages(intentId);

      if (messages.length === 0) {
        return null; // No messages yet, keep polling
      }

      // Look for resolution indicators in messages
      const hasCompletion = messages.some((msg) => {
        const actionTag = msg.tags.find((t) => t.name === 'Action');
        return (
          actionTag?.value === 'Order-Success' ||
          actionTag?.value === 'Order-Confirmation' ||
          actionTag?.value === 'Order-Error' ||
          actionTag?.value === 'Intent-Resolved'
        );
      });

      if (hasCompletion) {
        // Determine final status
        const errorMsg = messages.find((msg) =>
          msg.tags.some(
            (t) => t.name === 'Action' && t.value === 'Order-Error',
          ),
        );
        const status = errorMsg ? 'failed' : 'completed';

        return { intentId, status, messages };
      }

      return null; // Not resolved yet
    },
    {
      timeout,
      description: `intent ${intentId} resolution`,
    },
  );
}

/**
 * Wait for a specific Credit-Notice to appear
 */
export async function waitForCreditNotice(
  processId: string,
  filters: {
    intentId?: string;
    sender?: string;
    minQuantity?: string;
  },
  timeout: number = DEFAULT_TIMEOUT,
): Promise<GraphQLMessage> {
  return pollForMessage(
    async () => {
      const notices = await queryCreditNotices(processId, filters);
      return notices.length > 0 ? notices[0] : null;
    },
    {
      timeout,
      description: `Credit-Notice for process ${processId}`,
    },
  );
}

/**
 * Wait for a specific Debit-Notice to appear
 */
export async function waitForDebitNotice(
  processId: string,
  filters: {
    intentId?: string;
    recipient?: string;
    minQuantity?: string;
  },
  timeout: number = DEFAULT_TIMEOUT,
): Promise<GraphQLMessage> {
  return pollForMessage(
    async () => {
      const notices = await queryDebitNotices(processId, filters);
      return notices.length > 0 ? notices[0] : null;
    },
    {
      timeout,
      description: `Debit-Notice for process ${processId}`,
    },
  );
}

/**
 * Helper to extract tag value from a message
 */
export function getTagValue(
  message: GraphQLMessage,
  tagName: string,
): string | undefined {
  return message.tags.find((t) => t.name === tagName)?.value;
}

/**
 * Helper to check if a message has a specific tag value
 */
export function hasTagValue(
  message: GraphQLMessage,
  tagName: string,
  value: string,
): boolean {
  return message.tags.some((t) => t.name === tagName && t.value === value);
}

