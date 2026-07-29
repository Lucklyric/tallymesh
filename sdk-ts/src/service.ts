import type { Account, Address } from "viem";
import { recoverTypedDataAddress } from "viem";
import type { Hex32, Receipt, SignedReceipt, SignedRequest } from "./types.js";
import { hashReceipt } from "./domain.js";

export type ServiceErrorKind =
  | "BadSignature"
  | "SeqOutOfOrder"
  | "PrevHashMismatch"
  | "UnknownSession";

export class ServiceError extends Error {
  readonly kind: ServiceErrorKind;
  constructor(kind: ServiceErrorKind, message: string) {
    super(message);
    this.name = "ServiceError";
    this.kind = kind;
  }
}

export interface ServiceConfig {
  account: Account;
  verifyingContract: Address;
  chainId: number;
}

interface ResultArgs {
  chargedAmount: bigint;
  resultHash: Hex32;
  statusCode?: Hex32;
  serviceTimestamp?: bigint;
}

const ZERO_HASH = ("0x" + "00".repeat(32)) as Hex32;

interface SessionState {
  nextSeq: bigint;
  lastReceiptHash: Hex32; // ZERO_HASH if no receipt issued yet
}

export class Service {
  private readonly account: Account;
  private readonly verifyingContract: Address;
  private readonly chainId: number;
  private readonly sessions = new Map<Hex32, SessionState>();

  constructor(cfg: ServiceConfig) {
    this.account = cfg.account;
    this.verifyingContract = cfg.verifyingContract;
    this.chainId = cfg.chainId;
  }

  get address(): Address {
    return this.account.address;
  }

  async handle(req: SignedRequest, result: ResultArgs): Promise<SignedReceipt> {
    const recovered = await recoverTypedDataAddress({
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
      message: {
        sessionId: req.sessionId,
        seq: req.seq,
        requestHash: req.requestHash,
        prevHash: req.prevHash,
      },
      signature: req.signature,
    });
    if (recovered.toLowerCase() !== req.signer.toLowerCase()) {
      throw new ServiceError("BadSignature", `recovered ${recovered} != declared ${req.signer}`);
    }

    const state = this.sessions.get(req.sessionId) ?? {
      nextSeq: 0n,
      lastReceiptHash: ZERO_HASH,
    };

    if (req.seq !== state.nextSeq) {
      throw new ServiceError(
        "SeqOutOfOrder",
        `expected seq=${state.nextSeq} for session ${req.sessionId}, got ${req.seq}`,
      );
    }
    if (req.prevHash !== state.lastReceiptHash) {
      throw new ServiceError(
        "PrevHashMismatch",
        `expected prevHash=${state.lastReceiptHash}, got ${req.prevHash}`,
      );
    }

    const ts = result.serviceTimestamp ?? BigInt(Math.floor(Date.now() / 1000));
    const receipt: Receipt = {
      sessionId: req.sessionId,
      seq: req.seq,
      requestHash: req.requestHash,
      resultHash: result.resultHash,
      chargedAmount: result.chargedAmount,
      statusCode: result.statusCode ?? ZERO_HASH,
      serviceTimestamp: ts,
    };

    if (typeof this.account.signTypedData !== "function") {
      throw new Error("Service account does not support signTypedData");
    }
    const signature = await this.account.signTypedData({
      domain: {
        name: "TallyMesh",
        version: "1",
        chainId: this.chainId,
        verifyingContract: this.verifyingContract,
      },
      types: {
        Receipt: [
          { name: "sessionId", type: "bytes32" },
          { name: "seq", type: "uint64" },
          { name: "requestHash", type: "bytes32" },
          { name: "resultHash", type: "bytes32" },
          { name: "chargedAmount", type: "uint256" },
          { name: "statusCode", type: "bytes32" },
          { name: "serviceTimestamp", type: "uint64" },
        ],
      },
      primaryType: "Receipt",
      message: receipt,
    });

    state.nextSeq = req.seq + 1n;
    state.lastReceiptHash = hashReceipt(receipt);
    this.sessions.set(req.sessionId, state);

    return { receipt, signature, signer: this.account.address };
  }
}
