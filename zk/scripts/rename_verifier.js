import { readFileSync, writeFileSync } from "node:fs";

const verifierPath = "../contracts/src/zk/BatchValidityGroth16Verifier.sol";
const generatedName = "contract Groth16Verifier {";
const expectedName = "contract BatchValidityGroth16Verifier {";

const source = readFileSync(verifierPath, "utf8");
if (source.includes(expectedName)) {
  console.log("Verifier contract name already normalized");
} else if (source.includes(generatedName)) {
  writeFileSync(verifierPath, source.replace(generatedName, expectedName));
  console.log("Renamed Groth16Verifier to BatchValidityGroth16Verifier");
} else {
  throw new Error("Could not find generated verifier contract declaration");
}
