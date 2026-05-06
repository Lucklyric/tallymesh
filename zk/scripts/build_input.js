import { writeFileSync, mkdirSync, existsSync } from "node:fs";
import { buildPoseidon } from "circomlibjs";

const N = 1024;
const RECEIPT_COUNT = 4;
const CHARGED_CEILING = "1000000000"; // 1 gwei (fits comfortably in uint64)

const chargedAmounts = new Array(N).fill("0");
const leafTags = new Array(N).fill("0");
chargedAmounts[0] = "300000000";
chargedAmounts[1] = "150000000";
chargedAmounts[2] = "200000000";
chargedAmounts[3] = "450000000";
leafTags[0] = "1";
leafTags[1] = "2";
leafTags[2] = "3";
leafTags[3] = "4";

const poseidon = await buildPoseidon();

function hashPair(a, b) {
  return poseidon.F.toString(poseidon([BigInt(a), BigInt(b)]));
}

function leafEncoding(i) {
  if (i >= RECEIPT_COUNT) return "0";
  return poseidon.F.toString(poseidon([BigInt(chargedAmounts[i]), BigInt(leafTags[i])]));
}

let level = new Array(N);
for (let i = 0; i < N; i++) level[i] = leafEncoding(i);

while (level.length > 1) {
  const next = [];
  for (let i = 0; i < level.length; i += 2) {
    next.push(hashPair(level[i], level[i + 1]));
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
console.log(`Wrote fixtures/input.json (receiptsRoot = ${receiptsRoot}, count = ${RECEIPT_COUNT}, ceiling = ${CHARGED_CEILING})`);
