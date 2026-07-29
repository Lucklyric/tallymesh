import { readFileSync } from "node:fs";

const proof = JSON.parse(readFileSync("fixtures/proof.json", "utf8"));
const pub = JSON.parse(readFileSync("fixtures/public.json", "utf8"));

// snarkjs Groth16 Solidity verifier expects b coordinates swapped per pair.
const a = [proof.pi_a[0], proof.pi_a[1]];
const b = [
  [proof.pi_b[0][1], proof.pi_b[0][0]],
  [proof.pi_b[1][1], proof.pi_b[1][0]]
];
const c = [proof.pi_c[0], proof.pi_c[1]];

function toHex32(x) {
  return "0x" + BigInt(x).toString(16).padStart(64, "0");
}

console.log("// Public inputs:");
console.log(`uint256 RECEIPT_COUNT = ${pub[0]};`);
console.log(`uint256 CHARGED_CEILING = ${pub[1]};`);
console.log(`bytes32 RECEIPTS_ROOT = ${toHex32(pub[2])};`);
console.log("");
console.log("// Groth16 proof tuples (pasteable into Solidity test):");
console.log(`uint256[2] memory a = [uint256(${a[0]}), uint256(${a[1]})];`);
console.log(`uint256[2][2] memory b = [`);
console.log(`    [uint256(${b[0][0]}), uint256(${b[0][1]})],`);
console.log(`    [uint256(${b[1][0]}), uint256(${b[1][1]})]`);
console.log(`];`);
console.log(`uint256[2] memory c = [uint256(${c[0]}), uint256(${c[1]})];`);
console.log("");
console.log("// abi.encode(a, b, c) in test:");
console.log(`bytes memory proof = abi.encode(a, b, c);`);
