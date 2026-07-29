import { createWriteStream, existsSync, mkdirSync } from "node:fs";
import { pipeline } from "node:stream/promises";

const URL = "https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_22.ptau";
const OUT = "build/pot22_final.ptau";

if (!existsSync("build")) mkdirSync("build", { recursive: true });

if (existsSync(OUT)) {
  console.log(`Already present: ${OUT}`);
  process.exit(0);
}

console.log(`Downloading ${URL} -> ${OUT} (this is ~700MB; may take 5-15 minutes)...`);
const res = await fetch(URL);
if (!res.ok) {
  console.error(`Download failed: ${res.status} ${res.statusText}`);
  process.exit(1);
}
await pipeline(res.body, createWriteStream(OUT));
console.log(`Saved ${OUT}`);
