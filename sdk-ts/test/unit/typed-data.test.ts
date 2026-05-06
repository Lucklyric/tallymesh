// test/unit/typed-data.test.ts
import { describe, it, expect } from "vitest";
import { keccak256, toHex, encodeAbiParameters } from "viem";
import {
  TALLYMESH_DOMAIN,
  RECEIPT_TYPEHASH,
  SESSION_INTENT_TYPEHASH,
  SIGNED_REQUEST_TYPEHASH,
  hashReceipt,
} from "../../src/domain.js";
import type { Receipt } from "../../src/types.js";

describe("typed-data schemas", () => {
  it("RECEIPT_TYPEHASH matches the on-chain ReceiptLib value", () => {
    // Mirrors contracts/src/lib/ReceiptLib.sol
    const expected = keccak256(
      toHex(
        "Receipt(bytes32 sessionId,uint64 seq,bytes32 requestHash,bytes32 resultHash,uint256 chargedAmount,bytes32 statusCode,uint64 serviceTimestamp)",
      ),
    );
    expect(RECEIPT_TYPEHASH).toBe(expected);
  });

  it("hashReceipt matches abi.encode(typehash, fields...) Keccak digest", () => {
    const r: Receipt = {
      sessionId: ("0x" + "11".repeat(32)) as `0x${string}`,
      seq: 7n,
      requestHash: ("0x" + "22".repeat(32)) as `0x${string}`,
      resultHash: ("0x" + "33".repeat(32)) as `0x${string}`,
      chargedAmount: 1_234n,
      statusCode: ("0x" + "44".repeat(32)) as `0x${string}`,
      serviceTimestamp: 9_999n,
    };
    const expected = keccak256(
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
    expect(hashReceipt(r)).toBe(expected);
  });

  it("DOMAIN identifies TallyMesh v1 with chainId 31337 by default", () => {
    expect(TALLYMESH_DOMAIN.name).toBe("TallyMesh");
    expect(TALLYMESH_DOMAIN.version).toBe("1");
    expect(TALLYMESH_DOMAIN.chainId).toBe(31337);
  });

  it("session-intent and signed-request typehashes are stable strings", () => {
    expect(SESSION_INTENT_TYPEHASH).toBe(
      keccak256(
        toHex(
          "SessionIntent(bytes32 sessionId,address payer,address recipient,uint256 maxAmount,uint64 expiresAt)",
        ),
      ),
    );
    expect(SIGNED_REQUEST_TYPEHASH).toBe(
      keccak256(
        toHex(
          "SignedRequest(bytes32 sessionId,uint64 seq,bytes32 requestHash,bytes32 prevHash)",
        ),
      ),
    );
  });
});
