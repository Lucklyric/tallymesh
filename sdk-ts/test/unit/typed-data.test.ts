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
  it("RECEIPT_TYPEHASH matches the on-chain ReceiptLib value (anchored hex)", () => {
    expect(RECEIPT_TYPEHASH).toBe(
      "0x66da4379a1ea614f118c8a4ab51f21198b95dbd266d707df5f2d16ee8977664c",
    );
  });

  it("hashReceipt matches the on-chain ReceiptLib.leafHash for the canonical Forge fixture", () => {
    // This fixture is taken verbatim from
    // contracts/test/unit/ReceiptLib.t.sol::test_leafHash_isDomainSeparated.
    // The expected hash is computed by Solidity 0.8.26's keccak256(abi.encode(...))
    // and pinned here so any future drift in our TS encoding (wrong field order,
    // wrong abi type, etc.) fails this test instead of going undetected.
    const r: Receipt = {
      sessionId: ("0x" + "00".repeat(31) + "01") as `0x${string}`,
      seq: 1n,
      requestHash: ("0x" + "00".repeat(31) + "02") as `0x${string}`,
      resultHash: ("0x" + "00".repeat(31) + "03") as `0x${string}`,
      chargedAmount: 100n,
      // bytes32("OK") in Solidity = "OK" left-padded with zeros on the RIGHT to 32 bytes.
      statusCode: ("0x4f4b" + "00".repeat(30)) as `0x${string}`,
      serviceTimestamp: 1_700_000_000n,
    };
    expect(hashReceipt(r)).toBe(
      "0x53810fa21a75ad1f3c38e97a2c663ee33cd01aeb70e548c47a3f3b68af23346b",
    );
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
          "SessionIntent(bytes32 sessionId,address payer,address recipient,uint256 amount,uint256 maxAmount,uint64 expiry)",
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
