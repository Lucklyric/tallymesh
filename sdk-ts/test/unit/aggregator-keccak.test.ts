import { describe, it, expect } from "vitest";
import { keccak256, toHex, encodePacked } from "viem";
import { KeccakAggregator } from "../../src/aggregator-keccak.js";
import { hashReceipt } from "../../src/domain.js";
import type { Receipt } from "../../src/types.js";

function r(seq: bigint): Receipt {
  return {
    sessionId: ("0x" + "ab".repeat(32)) as `0x${string}`,
    seq,
    requestHash: keccak256(toHex(`req-${seq}`)),
    resultHash: keccak256(toHex(`res-${seq}`)),
    chargedAmount: 1n,
    statusCode: ("0x" + "00".repeat(32)) as `0x${string}`,
    serviceTimestamp: 1n,
  };
}

function pair(a: `0x${string}`, b: `0x${string}`): `0x${string}` {
  return BigInt(a) < BigInt(b)
    ? keccak256(encodePacked(["bytes32", "bytes32"], [a, b]))
    : keccak256(encodePacked(["bytes32", "bytes32"], [b, a]));
}

describe("KeccakAggregator", () => {
  it("single-leaf root equals leaf hash", () => {
    const agg = new KeccakAggregator([r(0n)]);
    expect(agg.root).toBe(hashReceipt(r(0n)));
    expect(agg.proofFor(0)).toEqual([]);
  });

  it("two-leaf root and proofs verify against pair hash", () => {
    const r0 = r(0n);
    const r1 = r(1n);
    const agg = new KeccakAggregator([r0, r1]);
    const l0 = hashReceipt(r0);
    const l1 = hashReceipt(r1);
    expect(agg.root).toBe(pair(l0, l1));
    const p0 = agg.proofFor(0);
    expect(p0).toEqual([l1]);
    expect(agg.verifyProof(p0, l0)).toBe(true);
    const p1 = agg.proofFor(1);
    expect(p1).toEqual([l0]);
    expect(agg.verifyProof(p1, l1)).toBe(true);
  });

  it("three-leaf tree promotes the lonely leaf with itself (OZ v5 convention)", () => {
    const r0 = r(0n), r1 = r(1n), r2 = r(2n);
    const agg = new KeccakAggregator([r0, r1, r2]);
    const l0 = hashReceipt(r0), l1 = hashReceipt(r1), l2 = hashReceipt(r2);
    const lvl1a = pair(l0, l1);
    const lvl1b = pair(l2, l2);
    const expected = pair(lvl1a, lvl1b);
    expect(agg.root).toBe(expected);
    expect(agg.verifyProof(agg.proofFor(2), l2)).toBe(true);
  });

  it("eight-leaf tree: every proof verifies against the root", () => {
    const rs = [0n, 1n, 2n, 3n, 4n, 5n, 6n, 7n].map(r);
    const agg = new KeccakAggregator(rs);
    for (let i = 0; i < rs.length; i++) {
      const leaf = hashReceipt(rs[i]!);
      const proof = agg.proofFor(i);
      expect(agg.verifyProof(proof, leaf)).toBe(true);
    }
  });
});
