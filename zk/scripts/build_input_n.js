import { writeFileSync, mkdirSync, existsSync } from "node:fs";
import { buildPoseidon } from "circomlibjs";

const ARG_N = parseInt(process.argv[2] ?? "4", 10);
if (isNaN(ARG_N) || ARG_N < 1 || ARG_N > 1024) {
  console.error("Usage: build_input_n.js <RECEIPT_COUNT>  (1..1024)");
  process.exit(1);
}

const MAX = 1024;
const RECEIPT_COUNT = ARG_N;
const CHARGED_CEILING = "1000000000";
const RECEIPT_LEAF_TAG =
  "5199086442301873898397355965405180149571845035285111109466476274982435227430";

const chargedAmounts = new Array(MAX).fill("0");
const leafTags = new Array(MAX).fill("0");
for (let i = 0; i < RECEIPT_COUNT; i++) {
  chargedAmounts[i] = ((i + 1) * 100000).toString();
  leafTags[i] = RECEIPT_LEAF_TAG;
}

const poseidon = await buildPoseidon();

function leafEncoding(i) {
  if (i >= RECEIPT_COUNT) return "0";
  return poseidon.F.toString(poseidon([BigInt(chargedAmounts[i]), BigInt(leafTags[i])]));
}

let level = new Array(MAX);
for (let i = 0; i < MAX; i++) level[i] = leafEncoding(i);
while (level.length > 1) {
  const next = [];
  for (let i = 0; i < level.length; i += 2) {
    next.push(poseidon.F.toString(poseidon([BigInt(level[i]), BigInt(level[i + 1])])));
  }
  level = next;
}
const receiptsRoot = level[0];

const input = {
  chargedAmounts,
  leafTags,
  receiptCount: RECEIPT_COUNT.toString(),
  chargedCeiling: CHARGED_CEILING,
  receiptsRoot
};

if (!existsSync("fixtures")) mkdirSync("fixtures", { recursive: true });
writeFileSync("fixtures/input.json", JSON.stringify(input, null, 2));
console.log(`N=${RECEIPT_COUNT} written; receiptsRoot=${receiptsRoot}`);
