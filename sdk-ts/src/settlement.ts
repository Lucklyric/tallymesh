import {
  type Address, type Hex, type PublicClient, type WalletClient,
} from "viem";
import { batchSettlementAbi, depositEscrowAbi } from "./abis.js";
import type { Hex32, Receipt, SessionIntent } from "./types.js";

export interface SettlementConfig {
  publicClient: PublicClient;
  walletClient: WalletClient;
  batchSettlement: Address;
  depositEscrow: Address;
}

export class Settlement {
  private readonly cfg: SettlementConfig;
  constructor(cfg: SettlementConfig) {
    this.cfg = cfg;
  }

  async deposit(amount: bigint): Promise<Hex> {
    const { request } = await this.cfg.publicClient.simulateContract({
      address: this.cfg.depositEscrow,
      abi: depositEscrowAbi,
      functionName: "deposit",
      account: this.cfg.walletClient.account!,
      value: amount,
    });
    return await this.cfg.walletClient.writeContract(request);
  }

  async bond(amount: bigint): Promise<Hex> {
    const { request } = await this.cfg.publicClient.simulateContract({
      address: this.cfg.batchSettlement,
      abi: batchSettlementAbi,
      functionName: "bond",
      account: this.cfg.walletClient.account!,
      value: amount,
    });
    return await this.cfg.walletClient.writeContract(request);
  }

  async reserveSession(sessionId: Hex32, recipient: Address, amount: bigint): Promise<Hex> {
    const { request } = await this.cfg.publicClient.simulateContract({
      address: this.cfg.batchSettlement,
      abi: batchSettlementAbi,
      functionName: "reserveSession",
      args: [sessionId, recipient, amount],
      account: this.cfg.walletClient.account!,
    });
    return await this.cfg.walletClient.writeContract(request);
  }

  async reserveSessionWithIntent(intent: SessionIntent, signature: Hex): Promise<Hex> {
    const { request } = await this.cfg.publicClient.simulateContract({
      address: this.cfg.batchSettlement,
      abi: batchSettlementAbi,
      functionName: "reserveSessionWithIntent",
      args: [intent, signature],
      account: this.cfg.walletClient.account!,
    });
    return await this.cfg.walletClient.writeContract(request);
  }

  /**
   * Submits an optimistic receipt batch bound to the EIP-4844 blob at index 0.
   * This SDK does not derive KZG commitments; callers should provide the blob's
   * versioned hash externally, for example from the blob transaction/block data.
   */
  async submitOptimisticBatch(args: {
    batchId: Hex32; receiptsRoot: Hex32; deltasRoot: Hex32; receiptCount: bigint; expectedBlobHash: Hex32;
  }): Promise<Hex> {
    const { request } = await this.cfg.publicClient.simulateContract({
      address: this.cfg.batchSettlement,
      abi: batchSettlementAbi,
      functionName: "submitOptimisticBatch",
      args: [args.batchId, args.receiptsRoot, args.deltasRoot, args.receiptCount, args.expectedBlobHash],
      account: this.cfg.walletClient.account!,
    });
    return await this.cfg.walletClient.writeContract(request);
  }

  async submitZkBatch(args: {
    batchId: Hex32; receiptsRoot: Hex32; deltasRoot: Hex32; receiptCount: bigint;
    verifier: Address; proof: Hex;
  }): Promise<Hex> {
    const { request } = await this.cfg.publicClient.simulateContract({
      address: this.cfg.batchSettlement,
      abi: batchSettlementAbi,
      functionName: "submitZkBatch",
      args: [args.batchId, args.receiptsRoot, args.deltasRoot, args.receiptCount, args.verifier, args.proof],
      account: this.cfg.walletClient.account!,
    });
    return await this.cfg.walletClient.writeContract(request);
  }

  async finalizeBatch(batchId: Hex32): Promise<Hex> {
    const { request } = await this.cfg.publicClient.simulateContract({
      address: this.cfg.batchSettlement,
      abi: batchSettlementAbi,
      functionName: "finalizeBatch",
      args: [batchId],
      account: this.cfg.walletClient.account!,
    });
    return await this.cfg.walletClient.writeContract(request);
  }

  async claimPayout(batchId: Hex32, receipt: Receipt, proof: Hex32[]): Promise<Hex> {
    const { request } = await this.cfg.publicClient.simulateContract({
      address: this.cfg.batchSettlement,
      abi: batchSettlementAbi,
      functionName: "claimPayout",
      args: [batchId, receipt, proof],
      account: this.cfg.walletClient.account!,
    });
    return await this.cfg.walletClient.writeContract(request);
  }
}
