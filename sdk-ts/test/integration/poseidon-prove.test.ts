import { describe, it, expect } from "vitest";
import { keccak256, toHex } from "viem";
import { PoseidonAggregator } from "../../src/aggregator-poseidon.js";
import type { Receipt } from "../../src/types.js";

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

describe("Poseidon prover bridge (real Groth16)", () => {
  it("produces a proof whose public signals match the offline-computed root", async () => {
    const agg = await PoseidonAggregator.create();
    const rs = [r(0n, 100n), r(1n, 200n), r(2n, 50n)];
    const ceiling = 250n;
    const offlineRoot = agg.computeRoot(rs, ceiling);
    const result = await agg.prove(rs, ceiling);
    expect(result.receiptsRoot).toBe(offlineRoot);
    expect(result.publicSignals[0]).toBe("3");          // receiptCount
    expect(result.publicSignals[1]).toBe("250");         // chargedCeiling
    expect(BigInt(result.publicSignals[2])).toBe(BigInt(offlineRoot));
    expect(result.proofBytes.length).toBeGreaterThan(2);
  }, 120_000);
});
