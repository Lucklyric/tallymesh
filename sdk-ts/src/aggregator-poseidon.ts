import { keccak256, encodePacked, encodeAbiParameters } from "viem";
import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
// circomlibjs has no types; bring it in dynamically.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const circomlibjs = (await import("circomlibjs")) as any;

import type { Hex32, Receipt } from "./types.js";

const BN254_PRIME =
  21888242871839275222246405745257275088548364400416034343698204186575808495617n;
const MAX_RECEIPTS = 1024;
const DEPTH = 10;

export interface CircuitInput {
  chargedAmounts: string[]; // length MAX_RECEIPTS, decimal strings
  leafTags: string[];       // length MAX_RECEIPTS, decimal strings
  receiptCount: string;
  chargedCeiling: string;
  receiptsRoot: string;
}

export interface ZkProveResult {
  proofBytes: `0x${string}`;          // abi.encoded ((uint[2], uint[2][2], uint[2]))
  publicSignals: [string, string, string]; // [receiptCount, chargedCeiling, receiptsRoot]
  receiptsRoot: Hex32;
}

export class PoseidonAggregator {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  private constructor(private readonly poseidon: any, private readonly F: any) {}

  static async create(): Promise<PoseidonAggregator> {
    const poseidon = await circomlibjs.buildPoseidon();
    return new PoseidonAggregator(poseidon, poseidon.F);
  }

  /// Compute the Poseidon Merkle root over receipts; throws if any chargedAmount > ceiling.
  computeRoot(receipts: Receipt[], chargedCeiling: bigint): Hex32 {
    const { receiptsRoot } = this.buildCircuitInput(receipts, chargedCeiling);
    return ("0x" + BigInt(receiptsRoot).toString(16).padStart(64, "0")) as Hex32;
  }

  /// Build the canonical snarkjs input. Throws on overflow.
  buildCircuitInput(receipts: Receipt[], chargedCeiling: bigint): CircuitInput {
    if (receipts.length > MAX_RECEIPTS) {
      throw new Error(`too many receipts: ${receipts.length} > ${MAX_RECEIPTS}`);
    }
    if (chargedCeiling < 0n || chargedCeiling >= 1n << 64n) {
      throw new Error(`chargedCeiling out of uint64 range: ${chargedCeiling}`);
    }

    const chargedAmounts: bigint[] = new Array(MAX_RECEIPTS).fill(0n);
    const leafTags: bigint[] = new Array(MAX_RECEIPTS).fill(0n);

    for (let i = 0; i < receipts.length; i++) {
      const r = receipts[i]!;
      if (r.chargedAmount < 0n || r.chargedAmount >= 1n << 64n) {
        throw new Error(`receipt[${i}].chargedAmount out of uint64 range`);
      }
      if (r.chargedAmount > chargedCeiling) {
        throw new Error(`receipt[${i}].chargedAmount=${r.chargedAmount} exceeds ceiling ${chargedCeiling}`);
      }
      chargedAmounts[i] = r.chargedAmount;
      leafTags[i] = this.computeLeafTag(r);
    }

    // Compute Poseidon Merkle root over leafEncodings.
    const leaves = chargedAmounts.map((amt, i) =>
      i < receipts.length ? this.poseidonField([amt, leafTags[i]!]) : 0n,
    );
    const root = this.poseidonRoot(leaves);

    return {
      chargedAmounts: chargedAmounts.map((x) => x.toString()),
      leafTags: leafTags.map((x) => x.toString()),
      receiptCount: receipts.length.toString(),
      chargedCeiling: chargedCeiling.toString(),
      receiptsRoot: root.toString(),
    };
  }

  /// Shell out to snarkjs to produce a proof. The zk subdirectory must already
  /// have run `yarn install` and `yarn setup:zkey`.
  async prove(receipts: Receipt[], chargedCeiling: bigint, opts?: { zkDir?: string }): Promise<ZkProveResult> {
    const zkDir = opts?.zkDir ?? defaultZkDir();
    const inputObj = this.buildCircuitInput(receipts, chargedCeiling);
    const tmp = mkdtempSync(join(tmpdir(), "tallymesh-zk-"));
    const inputPath = join(tmp, "input.json");
    const proofPath = join(tmp, "proof.json");
    const publicPath = join(tmp, "public.json");
    writeFileSync(inputPath, JSON.stringify(inputObj), "utf8");

    const res = spawnSync(
      "node",
      [
        "scripts/prove_fixture.js",
        "--input", inputPath,
        "--proof", proofPath,
        "--public", publicPath,
      ],
      { cwd: zkDir, stdio: "pipe", encoding: "utf8" },
    );
    if (res.status !== 0) {
      const stdout = res.stdout ?? "";
      const stderr = res.stderr ?? "";
      rmSync(tmp, { recursive: true, force: true });
      throw new Error(`prove_fixture failed (status ${res.status}):\n${stdout}\n${stderr}`);
    }

    const proof = JSON.parse(readFileSync(proofPath, "utf8")) as {
      pi_a: string[]; pi_b: string[][]; pi_c: string[];
    };
    const pub = JSON.parse(readFileSync(publicPath, "utf8")) as string[];
    rmSync(tmp, { recursive: true, force: true });

    if (pub.length !== 3) throw new Error(`unexpected public-input length ${pub.length}`);

    const a: [bigint, bigint] = [BigInt(proof.pi_a[0]!), BigInt(proof.pi_a[1]!)];
    // pi_b is in the snarkjs Solidity-friendly order: [[b00,b01],[b10,b11]]
    const b: [[bigint, bigint], [bigint, bigint]] = [
      [BigInt(proof.pi_b[0]![0]!), BigInt(proof.pi_b[0]![1]!)],
      [BigInt(proof.pi_b[1]![0]!), BigInt(proof.pi_b[1]![1]!)],
    ];
    const c: [bigint, bigint] = [BigInt(proof.pi_c[0]!), BigInt(proof.pi_c[1]!)];

    const proofBytes = encodeAbiParameters(
      [
        {
          type: "tuple",
          components: [
            { name: "a", type: "uint256[2]" },
            { name: "b", type: "uint256[2][2]" },
            { name: "c", type: "uint256[2]" },
          ],
        },
      ],
      [{ a, b, c }],
    );

    const root = ("0x" + BigInt(inputObj.receiptsRoot).toString(16).padStart(64, "0")) as Hex32;
    return { proofBytes, publicSignals: [pub[0]!, pub[1]!, pub[2]!], receiptsRoot: root };
  }

  // ---- internals ----

  private computeLeafTag(r: Receipt): bigint {
    const tagDigest = keccak256(
      encodePacked(
        ["bytes32", "uint64", "bytes32", "bytes32", "bytes32", "uint64"],
        [r.sessionId, r.seq, r.requestHash, r.resultHash, r.statusCode, r.serviceTimestamp],
      ),
    );
    return BigInt(tagDigest) % BN254_PRIME;
  }

  private poseidonField(inputs: bigint[]): bigint {
    const out = this.poseidon(inputs);
    return BigInt(this.F.toString(out));
  }

  private poseidonRoot(leaves: bigint[]): bigint {
    if (leaves.length !== 1 << DEPTH) throw new Error(`expected ${1 << DEPTH} leaves, got ${leaves.length}`);
    let level = leaves;
    for (let d = 0; d < DEPTH; d++) {
      const next: bigint[] = [];
      for (let i = 0; i < level.length; i += 2) {
        next.push(this.poseidonField([level[i]!, level[i + 1]!]));
      }
      level = next;
    }
    return level[0]!;
  }
}

function defaultZkDir(): string {
  // sdk-ts/src/aggregator-poseidon.ts → sdk-ts/src → sdk-ts → code → zk
  const here = fileURLToPath(import.meta.url);
  // here = .../code/sdk-ts/src/aggregator-poseidon.ts (or compiled .js)
  return join(here, "..", "..", "..", "zk");
}
