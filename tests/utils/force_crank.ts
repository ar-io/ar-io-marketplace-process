import { config } from 'dotenv';

config();

/**
 * Force crank (push) all output messages from a given message
 * This manually delivers Credit-Notices and other messages to their targets
 * 
 * WARNING: This is for testing only! In production, messages are delivered automatically.
 * Use this to work around slow/unreliable message delivery in test environments.
 */

const MU_URL = process.env.MU_URL || 'https://mu201.ao-testnet.xyz';
const CU_URL = process.env.CU_URL || 'https://cu.ardrive.io';

interface MessageResult {
  Output?: {
    data?: any;
  };
  Messages?: Array<{
    Target?: string;
    Tags?: Array<{ name: string; value: string }>;
    Data?: string;
    [key: string]: any;
  }>;
  Spawns?: any[];
  Error?: string;
}

/**
 * Get the result of a message from the CU
 */
async function getMessageResult(
  messageId: string,
  processId: string,
): Promise<MessageResult> {
  const url = `${CU_URL}/result/${messageId}?process-id=${processId}`;
  
  const response = await fetch(url, {
    method: 'GET',
    headers: {
      Accept: 'application/json',
    },
  });

  if (!response.ok) {
    throw new Error(`Failed to get message result: ${response.status} ${response.statusText}`);
  }

  return await response.json();
}

/**
 * Force push a specific output message to its target
 * Retries every 10s until successful or timeout
 */
async function pushMessage(
  messageId: string,
  messageIndex: number,
  processId: string,
  timeoutMs: number = 240_000, // 4 minute timeout (messages need to get into a block)
): Promise<boolean> {
  const url = `${MU_URL}/push/${messageId}/${messageIndex}?process-id=${processId}`;
  
  console.log(`  Pushing message ${messageIndex} from ${messageId.slice(0, 12)}... to process ${processId.slice(0, 12)}...`);
  
  const startTime = Date.now();
  let attempt = 0;
  
  while (Date.now() - startTime < timeoutMs) {
    attempt++;
    
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/octet-stream',
        Accept: 'application/json',
      },
    });

    const text = await response.text();
    
    // Check if message is not ready yet (not on gateway or not in block)
    if (response.status === 500 && 
        (text.includes('Message id not found on the gateway') || 
         text.includes('Message does not yet have a block'))) {
      const elapsed = ((Date.now() - startTime) / 1000).toFixed(0);
      console.log(`  [${elapsed}s] Message not ready yet, waiting 10s... (attempt ${attempt})`);
      await new Promise(resolve => setTimeout(resolve, 10_000));
      continue;
    }
    
    if (!response.ok) {
      console.error(`  ✗ Push failed: ${response.status} ${response.statusText}`);
      console.error(`  Response: ${text}`);
      return false;
    }
    
    const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
    console.log(`  ✓ Pushed successfully after ${elapsed}s (${attempt} attempts)`);
    if (text) {
      try {
        const json = JSON.parse(text);
        console.log(`  Response:`, json);
      } catch {
        console.log(`  Response: ${text}`);
      }
    }
    return true;
  }
  
  console.error(`  ✗ Timeout: Message not ready after ${timeoutMs/1000}s`);
  return false;
}

/**
 * Force crank all output messages from a given message
 * 
 * @param messageId - The message ID to get results from
 * @param processId - The process ID that processed the message
 * @returns Number of messages cranked
 */
export async function forceCrankMessage({
  messageId,
  processId,
  initialWaitMs = 5000, // Wait 5s for message to propagate
}: {
  messageId: string;
  processId: string;
  initialWaitMs?: number;
}): Promise<number> {
  console.log(`\n=== Force Cranking Message ${messageId.slice(0, 12)}... ===`);
  console.log(`Process: ${processId.slice(0, 12)}...`);
  
  // Wait for message to propagate to gateway
  if (initialWaitMs > 0) {
    console.log(`Waiting ${initialWaitMs/1000}s for message to propagate to gateway...`);
    await new Promise(resolve => setTimeout(resolve, initialWaitMs));
  }
  
  // Get the message result
  console.log(`Fetching message result...`);
  const result = await getMessageResult(messageId, processId);
  
  if (result.Error) {
    console.error(`Message resulted in error: ${result.Error}`);
    return 0;
  }

  const messages = result.Messages || [];
  console.log(`Found ${messages.length} output messages`);

  // Filter out hyperbeam messages (those without a Target)
  const deliverableMessages = messages.filter((msg, index) => {
    if (!msg.Target) {
      console.log(`  [${index}] Skipping hyperbeam message (no Target)`);
      return false;
    }
    return true;
  });

  console.log(`${deliverableMessages.length} messages to crank`);

  // Push each deliverable message
  let crankedCount = 0;
  for (let i = 0; i < messages.length; i++) {
    const msg = messages[i];
    if (!msg.Target) {
      continue; // Skip hyperbeam
    }

    const action = msg.Tags?.find(t => t.name === 'Action')?.value || 'Unknown';
    console.log(`\n  [${i}] Cranking ${action} to ${msg.Target.slice(0, 12)}...`);
    
    // Log relevant tags for debugging
    const relevantTags = msg.Tags?.filter(t => 
      ['Action', 'Sender', 'Quantity', 'X-Intent-Id', 'X-Order-Action'].includes(t.name)
    ) || [];
    if (relevantTags.length > 0) {
      console.log(`      Tags:`, relevantTags.map(t => `${t.name}=${t.value}`).join(', '));
    }

    try {
      const success = await pushMessage(messageId, i, processId);
      if (success) {
        crankedCount++;
      }
      
      // Small delay between pushes to avoid overwhelming the MU
      await new Promise(resolve => setTimeout(resolve, 500));
    } catch (error: any) {
      console.error(`  ✗ Failed to push message ${i}:`, error.message);
    }
  }

  console.log(`\n✓ Cranked ${crankedCount}/${deliverableMessages.length} messages\n`);
  return crankedCount;
}

/**
 * Wait for a message to be processed and then force crank it
 * Useful when you want to ensure a message is cranked immediately after sending
 */
export async function sendAndCrank({
  messageId,
  processId,
  maxWaitTime = 30000, // 30 seconds
}: {
  messageId: string;
  processId: string;
  maxWaitTime?: number;
}): Promise<number> {
  console.log(`Waiting for message to be processed...`);
  
  const startTime = Date.now();
  const pollInterval = 2000; // 2 seconds
  
  while (Date.now() - startTime < maxWaitTime) {
    try {
      const result = await getMessageResult(messageId, processId);
      
      if (result.Messages || result.Error) {
        // Message has been processed
        console.log(`✓ Message processed after ${((Date.now() - startTime) / 1000).toFixed(1)}s`);
        return await forceCrankMessage({ messageId, processId });
      }
    } catch (error) {
      // Message not ready yet, continue polling
    }
    
    await new Promise(resolve => setTimeout(resolve, pollInterval));
  }
  
  throw new Error(`Message not processed after ${maxWaitTime}ms`);
}

