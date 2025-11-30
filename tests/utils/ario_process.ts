import { AOProcess, AoSigner, ARIO } from '@ar.io/sdk';
import type { MessageTag } from './types.js';

/**
 * Wrapper class for AR.IO token process interactions
 */
export class ArioProcess {
  private ario: ARIO;
  private ao: any;
  private processId: string;
  private aoSigner: AoSigner;
  private dataItemSigner: any; // DataItemSigner for aoconnect

  constructor({
    process,
    signer,
    dataItemSigner,
  }: {
    process: AOProcess;
    signer: AoSigner;
    dataItemSigner?: any; // Optional, will use signer if not provided
  }) {
    this.ario = ARIO.init({ process, signer });
    this.ao = process.ao;
    this.processId = process.processId;
    this.aoSigner = signer;
    this.dataItemSigner = dataItemSigner || signer; // Fallback to signer for backwards compat
  }

  /**
   * Mint ARIO tokens via Eval (for testing purposes)
   */
  async mintBalance(address: string, amount: string): Promise<any> {
    const mintCode = `
      local bint = require('.bint')(256)
      Balances = Balances or {}
      Balances["${address}"] = tostring(bint(Balances["${address}"] or "0") + bint("${amount}"))
      return Balances["${address}"]
    `;

    // Use dataItemSigner for aoconnect's message() call
    const result = await this.ao.message({
      process: this.processId,
      signer: this.dataItemSigner,
      tags: [{ name: 'Action', value: 'Eval' }],
      data: mintCode,
    });

    return result;
  }

  /**
   * Get ARIO balance for an address
   */
  async getBalance(address: string): Promise<string> {
    try {
      const balance = await this.ario.getBalance({ address });
      return balance.toString();
    } catch (error) {
      console.error('Error getting balance:', error);
      return '0';
    }
  }

  /**
   * Transfer ARIO tokens to marketplace with order tags
   */
  async transferToMarketplace(
    marketplaceId: string,
    amount: string,
    additionalTags: MessageTag[] = [],
  ): Promise<{
    txId: string;
    result: any;
  }> {
    const tags: MessageTag[] = [
      { name: 'Action', value: 'Transfer' },
      { name: 'Recipient', value: marketplaceId },
      { name: 'Quantity', value: amount },
      ...additionalTags,
    ];

    // Use dataItemSigner for aoconnect's message() call
    const txId = await this.ao.message({
      process: this.processId,
      signer: this.dataItemSigner,
      tags,
    });

    // Get the result
    const result = await this.ao.result({
      process: this.processId,
      message: txId,
    });

    return { txId, result };
  }

  /**
   * Get the AR.IO process ID
   */
  getProcessId(): string {
    return this.processId;
  }

  /**
   * Get info about the AR.IO process
   */
  async getInfo(): Promise<any> {
    return await this.ario.getInfo();
  }

  /**
   * Transfer ARIO tokens (generic transfer)
   */
  async transfer(params: {
    target: string;
    quantity: string;
  }): Promise<any> {
    return await this.ario.transfer(params);
  }
}

