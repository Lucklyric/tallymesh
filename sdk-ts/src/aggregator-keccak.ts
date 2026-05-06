import { keccak256, encodePacked } from "viem";
import type { Hex32, Receipt } from "./types.js";
import { hashReceipt } from "./domain.js";

function pairHash(a: Hex32, b: Hex32): Hex32 {
  return BigInt(a) < BigInt(b)
    ? keccak256(encodePacked(["bytes32", "bytes32"], [a, b]))
    : keccak256(encodePacked(["bytes32", "bytes32"], [b, a]));
}

export class KeccakAggregator {
  readonly leaves: Hex32[];
  readonly root: Hex32;
  // Each level is bottom-up: levels[0] = leaves, levels[k] = parents of levels[k-1].
  private readonly levels: Hex32[][];

  constructor(receipts: Receipt[]) {
    if (receipts.length === 0) throw new Error("KeccakAggregator: empty receipt list");
    this.leaves = receipts.map(hashReceipt);
    this.levels = [this.leaves.slice()];
    let cur = this.leaves.slice();
    while (cur.length > 1) {
      const next: Hex32[] = [];
      for (let i = 0; i < cur.length; i += 2) {
        const a = cur[i]!;
        const b = i + 1 < cur.length ? cur[i + 1]! : a;
        next.push(pairHash(a, b));
      }
      this.levels.push(next);
      cur = next;
    }
    this.root = cur[0]!;
  }

  proofFor(index: number): Hex32[] {
    if (index < 0 || index >= this.leaves.length) throw new Error(`index ${index} out of range`);
    const proof: Hex32[] = [];
    let i = index;
    for (let lvl = 0; lvl < this.levels.length - 1; lvl++) {
      const layer = this.levels[lvl]!;
      const sibling = i % 2 === 0
        ? (i + 1 < layer.length ? layer[i + 1]! : layer[i]!)
        : layer[i - 1]!;
      proof.push(sibling);
      i = i >> 1;
    }
    return proof;
  }

  verifyProof(proof: Hex32[], leaf: Hex32): boolean {
    let computed = leaf;
    for (const p of proof) computed = pairHash(computed, p);
    return computed === this.root;
  }
}
