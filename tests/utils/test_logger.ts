import { writeFileSync } from 'fs';
import { join } from 'path';
import { fileURLToPath } from 'url';

const __dirname = join(fileURLToPath(import.meta.url), '..');

interface MessageLog {
  timestamp: number;
  workflow: string;
  action: string;
  processId: string;
  messageId?: string;
  tags: { name: string; value: string }[];
  data?: string;
  status: 'pending' | 'success' | 'failed';
  result?: any;
  error?: string;
  duration?: number;
}

interface IntentLog {
  intentId: string;
  status: string;
  action: string;
  createdAt: number;
  resolvedAt?: number;
  error?: string;
  relatedMessages: string[];
}

interface TestOutput {
  testRunId: string;
  startTime: number;
  endTime?: number;
  processes: {
    ario: string;
    marketplace: string;
    ant: string;
  };
  workflows: {
    [workflowName: string]: {
      started: number;
      completed?: number;
      status: 'pending' | 'success' | 'failed';
      messages: MessageLog[];
      error?: string;
    };
  };
  intents: {
    [intentId: string]: IntentLog;
  };
  summary: {
    totalMessages: number;
    successfulMessages: number;
    failedMessages: number;
    totalIntents: number;
    resolvedIntents: number;
    failedIntents: number;
  };
}

export class TestLogger {
  private output: TestOutput;
  private currentWorkflow: string | null = null;
  private outputPath: string;

  constructor() {
    this.outputPath = join(__dirname, '../../test-output.json');
    this.output = {
      testRunId: `test-${Date.now()}`,
      startTime: Date.now(),
      processes: {
        ario: '',
        marketplace: '',
        ant: '',
      },
      workflows: {},
      intents: {},
      summary: {
        totalMessages: 0,
        successfulMessages: 0,
        failedMessages: 0,
        totalIntents: 0,
        resolvedIntents: 0,
        failedIntents: 0,
      },
    };
  }

  setProcesses(processes: { ario: string; marketplace: string; ant: string }) {
    this.output.processes = processes;
  }

  startWorkflow(workflowName: string) {
    this.currentWorkflow = workflowName;
    this.output.workflows[workflowName] = {
      started: Date.now(),
      status: 'pending',
      messages: [],
    };
    console.log(`[TestLogger] Starting workflow: ${workflowName}`);
  }

  async logMessage(params: {
    action: string;
    processId: string;
    tags: { name: string; value: string }[];
    data?: string;
    messageFn: () => Promise<string>; // Function that sends the message and returns ID
  }): Promise<string> {
    const { action, processId, tags, data, messageFn } = params;
    const workflow = this.currentWorkflow || 'unknown';

    const messageLog: MessageLog = {
      timestamp: Date.now(),
      workflow,
      action,
      processId,
      tags,
      data: data ? (data.length > 200 ? data.substring(0, 200) + '...' : data) : undefined,
      status: 'pending',
    };

    const startTime = Date.now();

    try {
      console.log(`[TestLogger] Sending ${action} to ${processId.substring(0, 8)}...`);
      const messageId = await messageFn();
      messageLog.messageId = messageId;
      messageLog.status = 'success';
      messageLog.duration = Date.now() - startTime;

      this.output.summary.totalMessages++;
      this.output.summary.successfulMessages++;

      console.log(`[TestLogger] ✓ ${action} successful (${messageLog.duration}ms) - ID: ${messageId.substring(0, 12)}...`);
      
      // Extract intent ID if present
      const intentIdTag = tags.find(t => t.name === 'X-Intent-Id');
      if (intentIdTag) {
        this.trackIntent(intentIdTag.value, messageId);
      }

      if (this.currentWorkflow && this.output.workflows[this.currentWorkflow]) {
        this.output.workflows[this.currentWorkflow].messages.push(messageLog);
      }

      return messageId;
    } catch (error: any) {
      messageLog.status = 'failed';
      messageLog.error = error.message || String(error);
      messageLog.duration = Date.now() - startTime;

      this.output.summary.totalMessages++;
      this.output.summary.failedMessages++;

      console.log(`[TestLogger] ✗ ${action} failed (${messageLog.duration}ms): ${messageLog.error}`);

      if (this.currentWorkflow && this.output.workflows[this.currentWorkflow]) {
        this.output.workflows[this.currentWorkflow].messages.push(messageLog);
        this.output.workflows[this.currentWorkflow].status = 'failed';
        this.output.workflows[this.currentWorkflow].error = messageLog.error;
      }

      throw error;
    }
  }

  completeWorkflow(success: boolean, error?: string) {
    if (this.currentWorkflow && this.output.workflows[this.currentWorkflow]) {
      this.output.workflows[this.currentWorkflow].completed = Date.now();
      this.output.workflows[this.currentWorkflow].status = success ? 'success' : 'failed';
      if (error) {
        this.output.workflows[this.currentWorkflow].error = error;
      }
      console.log(`[TestLogger] ${success ? '✓' : '✗'} Workflow ${this.currentWorkflow} ${success ? 'completed' : 'failed'}`);
    }
    this.currentWorkflow = null;
  }

  private trackIntent(intentId: string, messageId: string) {
    if (!this.output.intents[intentId]) {
      this.output.intents[intentId] = {
        intentId,
        status: 'pending',
        action: 'unknown',
        createdAt: Date.now(),
        relatedMessages: [messageId],
      };
      this.output.summary.totalIntents++;
    } else {
      this.output.intents[intentId].relatedMessages.push(messageId);
    }
  }

  updateIntent(intentId: string, updates: Partial<IntentLog>) {
    if (!this.output.intents[intentId]) {
      this.output.intents[intentId] = {
        intentId,
        status: 'pending',
        action: 'unknown',
        createdAt: Date.now(),
        relatedMessages: [],
      };
      this.output.summary.totalIntents++;
    }

    Object.assign(this.output.intents[intentId], updates);

    if (updates.status === 'resolved' || updates.status === 'completed') {
      this.output.intents[intentId].resolvedAt = Date.now();
      this.output.summary.resolvedIntents++;
    } else if (updates.status === 'failed') {
      this.output.intents[intentId].resolvedAt = Date.now();
      this.output.summary.failedIntents++;
    }

    console.log(`[TestLogger] Intent ${intentId} updated: ${updates.status || 'status unchanged'}`);
  }

  logError(workflow: string, error: string) {
    if (!this.output.workflows[workflow]) {
      this.output.workflows[workflow] = {
        started: Date.now(),
        status: 'failed',
        messages: [],
        error,
      };
    } else {
      this.output.workflows[workflow].status = 'failed';
      this.output.workflows[workflow].error = error;
    }
    console.log(`[TestLogger] Error in ${workflow}: ${error}`);
  }

  async save() {
    this.output.endTime = Date.now();
    const duration = this.output.endTime - this.output.startTime;
    
    console.log('\n[TestLogger] ═══════════════════════════════════════');
    console.log('[TestLogger] Test Run Summary');
    console.log('[TestLogger] ═══════════════════════════════════════');
    console.log(`[TestLogger] Duration: ${Math.round(duration / 1000)}s`);
    console.log(`[TestLogger] Messages: ${this.output.summary.successfulMessages}/${this.output.summary.totalMessages} successful`);
    console.log(`[TestLogger] Intents: ${this.output.summary.resolvedIntents}/${this.output.summary.totalIntents} resolved`);
    console.log('[TestLogger] ═══════════════════════════════════════\n');

    try {
      writeFileSync(this.outputPath, JSON.stringify(this.output, null, 2), 'utf-8');
      console.log(`[TestLogger] Test output saved to: ${this.outputPath}`);
    } catch (error) {
      console.error('[TestLogger] Failed to save test output:', error);
    }
  }

  getOutput(): TestOutput {
    return this.output;
  }
}

// Singleton instance
let loggerInstance: TestLogger | null = null;

export function getTestLogger(): TestLogger {
  if (!loggerInstance) {
    loggerInstance = new TestLogger();
  }
  return loggerInstance;
}

export function resetTestLogger(): TestLogger {
  loggerInstance = new TestLogger();
  return loggerInstance;
}

