import * as snarkjs from "snarkjs";
import { readFileSync, writeFileSync } from "node:fs";

const WASM = "build/BatchValidity_js/BatchValidity.wasm";
const ZKEY = "build/BatchValidity_final.zkey";
const DEFAULT_INPUT = "fixtures/input.json";
const DEFAULT_PROOF = "fixtures/proof.json";
const DEFAULT_PUBLIC = "fixtures/public.json";

function parseFlags(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const k = argv[i];
    if (k === "--input" || k === "--proof" || k === "--public") {
      const v = argv[i + 1];
      if (!v) throw new Error(`missing value for ${k}`);
      out[k.slice(2)] = v;
      i++;
    }
  }
  return out;
}

const flags = parseFlags(process.argv.slice(2));
const usingFlags = flags.input && flags.proof && flags.public;
const INPUT = usingFlags ? flags.input : DEFAULT_INPUT;
const PROOF = usingFlags ? flags.proof : DEFAULT_PROOF;
const PUBLIC = usingFlags ? flags.public : DEFAULT_PUBLIC;

const input = JSON.parse(readFileSync(INPUT, "utf8"));
console.log("Generating proof (this may take 30s-2min for 1.15M constraints) ...");
const { proof, publicSignals } = await snarkjs.groth16.fullProve(input, WASM, ZKEY);

writeFileSync(PROOF, JSON.stringify(proof, null, 2));
writeFileSync(PUBLIC, JSON.stringify(publicSignals, null, 2));
console.log(`Wrote ${PROOF} and ${PUBLIC}`);

const vKey = JSON.parse(readFileSync("build/verification_key.json", "utf8"));
const ok = await snarkjs.groth16.verify(vKey, publicSignals, proof);
console.log(`Local verification: ${ok ? "OK" : "FAIL"}`);
if (!ok) process.exit(1);
// snarkjs keeps a worker pool alive after groth16; force-exit to release the parent.
process.exit(0);
