import * as snarkjs from "snarkjs";
import { readFileSync, writeFileSync } from "node:fs";

const WASM = "build/BatchValidity_js/BatchValidity.wasm";
const ZKEY = "build/BatchValidity_final.zkey";
const INPUT = "fixtures/input.json";
const PROOF = "fixtures/proof.json";
const PUBLIC = "fixtures/public.json";

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
