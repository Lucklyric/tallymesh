// code/sdk-ts/src/relayer.ts
import type { Address, Hex, PublicClient, WalletClient } from "viem";
import { batchSettlementAbi } from "./abis.js";
import type { Hex32 } from "./types.js";

/// Submits BatchSettlement state-changing calls on behalf of a payer using a
/// separately-funded relayer EOA. The payer's typed-data signatures are
/// unchanged; only the tx sender (and gas payer) differs.
///
/// For Day-6 E1/E2 measurements, the on-chain entry points the relayer drives
/// are reserveSession (called BY the payer in the EOA path; called by relayer
/// in the relayer path; the on-chain reserveSession captures msg.sender as the
/// payer, so when called by a relayer the *relayer* would become the payer).
/// To preserve "payer = signer" semantics, the EOA-via-relayer path here
/// represents only request-time signature verification (E2 caller type), NOT
/// reserveSession itself. E1 (session setup) for the relayer caller measures
/// only the off-chain intent → accept handshake.
export class Relayer {
  constructor(
    private readonly publicClient: PublicClient,
    private readonly walletClient: WalletClient,
    private readonly batchSettlement: Address,
  ) {}

  get account(): Address {
    if (!this.walletClient.account) throw new Error("Relayer: walletClient.account is required");
    return this.walletClient.account.address;
  }

  /// Submit a pre-built optimistic batch on behalf of a bonded submitter.
  /// Used in E3 to drive concurrent claims through a relayer.
  /// The caller supplies the EIP-4844 versioned hash for blob 0; this helper
  /// does not compute KZG commitments locally.
  async submitOptimisticBatch(args: {
    batchId: Hex32; receiptsRoot: Hex32; deltasRoot: Hex32; receiptCount: bigint; expectedBlobHash: Hex32;
  }): Promise<Hex> {
    const { request } = await this.publicClient.simulateContract({
      address: this.batchSettlement,
      abi: batchSettlementAbi,
      functionName: "submitOptimisticBatch",
      args: [args.batchId, args.receiptsRoot, args.deltasRoot, args.receiptCount, args.expectedBlobHash],
      account: this.walletClient.account!,
    });
    return await this.walletClient.writeContract(request);
  }
}
