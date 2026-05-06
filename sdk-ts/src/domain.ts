import { keccak256, toHex, encodeAbiParameters } from "viem";
import type { Receipt, SessionIntent, SignedRequest, Hex32 } from "./types.js";

export const TALLYMESH_DOMAIN = {
  name: "TallyMesh",
  version: "1",
  chainId: 31337, // Anvil default; overridable per-call
} as const;

export const RECEIPT_TYPEHASH: Hex32 = keccak256(
  toHex(
    "Receipt(bytes32 sessionId,uint64 seq,bytes32 requestHash,bytes32 resultHash,uint256 chargedAmount,bytes32 statusCode,uint64 serviceTimestamp)",
  ),
);

export const SESSION_INTENT_TYPEHASH: Hex32 = keccak256(
  toHex(
    "SessionIntent(bytes32 sessionId,address payer,address recipient,uint256 maxAmount,uint64 expiresAt)",
  ),
);

export const SIGNED_REQUEST_TYPEHASH: Hex32 = keccak256(
  toHex(
    "SignedRequest(bytes32 sessionId,uint64 seq,bytes32 requestHash,bytes32 prevHash)",
  ),
);

export function hashReceipt(r: Receipt): Hex32 {
  return keccak256(
    encodeAbiParameters(
      [
        { type: "bytes32" },
        { type: "bytes32" },
        { type: "uint64" },
        { type: "bytes32" },
        { type: "bytes32" },
        { type: "uint256" },
        { type: "bytes32" },
        { type: "uint64" },
      ],
      [
        RECEIPT_TYPEHASH,
        r.sessionId,
        r.seq,
        r.requestHash,
        r.resultHash,
        r.chargedAmount,
        r.statusCode,
        r.serviceTimestamp,
      ],
    ),
  );
}

export function hashSessionIntent(s: SessionIntent): Hex32 {
  return keccak256(
    encodeAbiParameters(
      [
        { type: "bytes32" },
        { type: "bytes32" },
        { type: "address" },
        { type: "address" },
        { type: "uint256" },
        { type: "uint64" },
      ],
      [
        SESSION_INTENT_TYPEHASH,
        s.sessionId,
        s.payer,
        s.recipient,
        s.maxAmount,
        s.expiresAt,
      ],
    ),
  );
}

export function hashSignedRequest(
  r: Pick<SignedRequest, "sessionId" | "seq" | "requestHash" | "prevHash">,
): Hex32 {
  return keccak256(
    encodeAbiParameters(
      [
        { type: "bytes32" },
        { type: "bytes32" },
        { type: "uint64" },
        { type: "bytes32" },
        { type: "bytes32" },
      ],
      [
        SIGNED_REQUEST_TYPEHASH,
        r.sessionId,
        r.seq,
        r.requestHash,
        r.prevHash,
      ],
    ),
  );
}
