import type { Account, Address } from "viem";
import type { Hex32, Receipt, SessionIntent, SignedRequest } from "./types.js";
import { hashReceipt } from "./domain.js";

export interface ClientConfig {
  account: Account;
  verifyingContract: Address;
  chainId: number;
}

interface OpenSessionArgs {
  sessionId: Hex32;
  recipient: Address;
  maxAmount: bigint;
  expiresAt: bigint;
}

interface SignRequestArgs {
  sessionId: Hex32;
  seq: bigint;
  requestHash: Hex32;
  prevReceipt: Receipt | null;
}

const ZERO_HASH = ("0x" + "00".repeat(32)) as Hex32;

export class Client {
  private readonly account: Account;
  private readonly verifyingContract: Address;
  private readonly chainId: number;

  constructor(cfg: ClientConfig) {
    this.account = cfg.account;
    this.verifyingContract = cfg.verifyingContract;
    this.chainId = cfg.chainId;
  }

  get address(): Address {
    return this.account.address;
  }

  async openSession(
    args: OpenSessionArgs,
  ): Promise<SessionIntent & { signature: `0x${string}`; signer: Address }> {
    if (typeof this.account.signTypedData !== "function") {
      throw new Error("Client account does not support signTypedData");
    }
    const intent: SessionIntent = {
      sessionId: args.sessionId,
      payer: this.account.address,
      recipient: args.recipient,
      maxAmount: args.maxAmount,
      expiresAt: args.expiresAt,
    };
    const signature = await this.account.signTypedData({
      domain: {
        name: "TallyMesh",
        version: "1",
        chainId: this.chainId,
        verifyingContract: this.verifyingContract,
      },
      types: {
        SessionIntent: [
          { name: "sessionId", type: "bytes32" },
          { name: "payer", type: "address" },
          { name: "recipient", type: "address" },
          { name: "maxAmount", type: "uint256" },
          { name: "expiresAt", type: "uint64" },
        ],
      },
      primaryType: "SessionIntent",
      message: intent,
    });
    return { ...intent, signature, signer: this.account.address };
  }

  async signRequest(args: SignRequestArgs): Promise<SignedRequest> {
    if (typeof this.account.signTypedData !== "function") {
      throw new Error("Client account does not support signTypedData");
    }
    const prevHash = args.prevReceipt ? hashReceipt(args.prevReceipt) : ZERO_HASH;
    const message = {
      sessionId: args.sessionId,
      seq: args.seq,
      requestHash: args.requestHash,
      prevHash,
    };
    const signature = await this.account.signTypedData({
      domain: {
        name: "TallyMesh",
        version: "1",
        chainId: this.chainId,
        verifyingContract: this.verifyingContract,
      },
      types: {
        SignedRequest: [
          { name: "sessionId", type: "bytes32" },
          { name: "seq", type: "uint64" },
          { name: "requestHash", type: "bytes32" },
          { name: "prevHash", type: "bytes32" },
        ],
      },
      primaryType: "SignedRequest",
      message,
    });
    return {
      ...message,
      signature,
      signer: this.account.address,
    };
  }
}
