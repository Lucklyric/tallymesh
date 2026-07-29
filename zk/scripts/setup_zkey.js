import * as snarkjs from "snarkjs";
import { writeFileSync } from "node:fs";

const R1CS = "build/BatchValidity.r1cs";
const PTAU = "build/pot22_final.ptau";
const ZKEY_INITIAL = "build/BatchValidity_0000.zkey";
const ZKEY_FINAL = "build/BatchValidity_final.zkey";
const VKEY = "build/verification_key.json";

console.log("Running snarkjs zKey.newZKey ...");
await snarkjs.zKey.newZKey(R1CS, PTAU, ZKEY_INITIAL);

console.log("Running snarkjs zKey.contribute (single-contributor ceremony) ...");
await snarkjs.zKey.contribute(ZKEY_INITIAL, ZKEY_FINAL, "tallymesh-bcca2026", "tallymesh seed entropy");

console.log("Exporting verification key ...");
const vKey = await snarkjs.zKey.exportVerificationKey(ZKEY_FINAL);
writeFileSync(VKEY, JSON.stringify(vKey, null, 2));

console.log(`Wrote ${ZKEY_FINAL} and ${VKEY}`);
