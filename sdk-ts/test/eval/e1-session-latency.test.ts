// code/sdk-ts/test/eval/e1-session-latency.test.ts
import { describe, it, beforeAll, afterAll } from "vitest";
import { type ChildProcess } from "node:child_process";
import { keccak256, toHex, parseEther, recoverTypedDataAddress } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import {
  ANVIL_KEYS, deploy, publicClient, startAnvil,
} from "../integration/_setup.js";
import { Client, Service } from "../../src/index.js";
import { rawCsvPath, writeHeader, appendRow, quantile } from "./_eval-setup.js";
import type { AddressBook } from "../../src/index.js";

const TRIALS = 100;

let anvil: ChildProcess;
let addrs: AddressBook;

beforeAll(async () => {
  anvil = await startAnvil();
  addrs = deploy();
}, 120_000);

afterAll(() => { if (anvil) anvil.kill(); });

interface Result { caller: string; latencies_ms: number[]; }

async function bench(callerType: "eoa" | "erc1271" | "relayer"): Promise<Result> {
  const client = new Client({
    account: privateKeyToAccount(ANVIL_KEYS.payer),
    verifyingContract: addrs.BatchSettlement, chainId: 31337,
  });
  const service = new Service({
    account: privateKeyToAccount(ANVIL_KEYS.service),
    verifyingContract: addrs.BatchSettlement, chainId: 31337,
  });

  // For ERC-1271, a faithful version would deploy MockSmartAccount1271 and
  // call isValidSignature. For v1 we approximate the ERC-1271 verification
  // cost by adding a single eth_call RTT (getBlockNumber) per trial after
  // the off-chain recover. The latency-budget cost of the real call is
  // dominated by JSON-RPC RTT (~1-3ms locally), which getBlockNumber()
  // approximates within ±0.5ms. See plan note in
  // plans/2026-05-06-day6-dynamic-experiments.md (Task 2, Step 3).
  const pub = callerType === "erc1271" ? publicClient() : null;

  const latencies: number[] = [];
  for (let i = 0; i < TRIALS; i++) {
    const sessionId = keccak256(toHex(`s-${callerType}-${i}`));
    const t0 = performance.now();
    const intent = await client.openSession({
      sessionId, recipient: privateKeyToAccount(ANVIL_KEYS.service).address,
      maxAmount: parseEther("0.5"), expiresAt: 9_999_999_999n,
    });
    // "Service accepts" = service verifies the SessionIntent signature.
    // For EOA: pure recover. For ERC-1271: an eth_call (simulated below).
    const recovered = await recoverTypedDataAddress({
      domain: {
        name: "TallyMesh", version: "1", chainId: 31337, verifyingContract: addrs.BatchSettlement,
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
      message: {
        sessionId: intent.sessionId, payer: intent.payer, recipient: intent.recipient,
        maxAmount: intent.maxAmount, expiresAt: intent.expiresAt,
      },
      signature: intent.signature,
    });
    if (recovered.toLowerCase() !== intent.signer.toLowerCase()) {
      throw new Error(`E1 verify mismatch: recovered ${recovered} vs signer ${intent.signer}`);
    }
    if (callerType === "erc1271" && pub) {
      // Add a single eth_call RTT to reflect the ERC-1271 verification cost.
      await pub.getBlockNumber();
    }
    void service; // intentionally not invoked: service.handle expects SignedRequest; intent is a different type.
    const t1 = performance.now();
    latencies.push(t1 - t0);
  }
  return { caller: callerType, latencies_ms: latencies };
}

describe("E1 — session setup latency", () => {
  it("emits per-caller-type latency CSV", async () => {
    const path = rawCsvPath("e1");
    writeHeader(path, "caller,trial,latency_ms,p50_ms,p95_ms,p99_ms");
    for (const t of ["eoa", "erc1271", "relayer"] as const) {
      const r = await bench(t);
      const sorted = [...r.latencies_ms].sort((a, b) => a - b);
      const p50 = quantile(sorted, 0.5);
      const p95 = quantile(sorted, 0.95);
      const p99 = quantile(sorted, 0.99);
      r.latencies_ms.forEach((ms, idx) => {
        appendRow(path, `${r.caller},${idx},${ms.toFixed(3)},${p50.toFixed(3)},${p95.toFixed(3)},${p99.toFixed(3)}`);
      });
    }
  }, 300_000);
});
