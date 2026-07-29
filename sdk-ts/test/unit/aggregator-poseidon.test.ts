import { describe, it, expect } from "vitest";
import { keccak256, toHex } from "viem";
import { PoseidonAggregator } from "../../src/aggregator-poseidon.js";
import type { Receipt } from "../../src/types.js";

const RECEIPT_LEAF_TAG =
  "5199086442301873898397355965405180149571845035285111109466476274982435227430";

function r(seq: bigint, charged: bigint): Receipt {
  return {
    sessionId: ("0x" + "ab".repeat(32)) as `0x${string}`,
    seq,
    requestHash: keccak256(toHex(`req-${seq}`)),
    resultHash: keccak256(toHex(`res-${seq}`)),
    chargedAmount: charged,
    statusCode: ("0x" + "00".repeat(32)) as `0x${string}`,
    serviceTimestamp: 1_700_000_000n + seq,
  };
}

describe("PoseidonAggregator (offline)", () => {
  it("rejects when chargedAmount > chargedCeiling", async () => {
    const agg = await PoseidonAggregator.create();
    const rs = [r(0n, 100n), r(1n, 200n)];
    expect(() => agg.computeRoot(rs, 150n)).toThrowError(/exceeds ceiling/);
  });

  it("two-receipt root is reproducible", async () => {
    const agg = await PoseidonAggregator.create();
    const rs = [r(0n, 50n), r(1n, 75n)];
    const root1 = agg.computeRoot(rs, 100n);
    const root2 = agg.computeRoot(rs, 100n);
    expect(root1).toBe(root2);
    expect(root1.startsWith("0x")).toBe(true);
  });

  it("buildCircuitInput pads to MAX_RECEIPTS=1024 with zeros", async () => {
    const agg = await PoseidonAggregator.create();
    const rs = [r(0n, 50n), r(1n, 75n)];
    const input = agg.buildCircuitInput(rs, 100n);
    expect(input.chargedAmounts.length).toBe(1024);
    expect(input.leafTags.length).toBe(1024);
    expect(input.receiptCount).toBe("2");
    expect(input.chargedCeiling).toBe("100");
    // First two slots populated, rest zero
    expect(input.chargedAmounts[0]).toBe("50");
    expect(input.chargedAmounts[1]).toBe("75");
    expect(input.leafTags[0]).toBe(RECEIPT_LEAF_TAG);
    expect(input.leafTags[1]).toBe(RECEIPT_LEAF_TAG);
    expect(input.leafTags[2]).toBe("0");
    expect(input.chargedAmounts[2]).toBe("0");
    expect(input.chargedAmounts[1023]).toBe("0");
  });
});
