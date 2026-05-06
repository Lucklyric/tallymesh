// code/sdk-ts/test/eval/_eval-setup.ts
import { appendFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
// test/eval/ → ../../../code/contracts/eval/data/raw
const RAW_DIR = resolve(here, "..", "..", "..", "contracts", "eval", "data", "raw");

export function rawCsvPath(name: string): string {
  mkdirSync(RAW_DIR, { recursive: true });
  return join(RAW_DIR, `${name}.csv`);
}

export function writeHeader(path: string, header: string): void {
  writeFileSync(path, `${header}\n`, "utf8");
}

export function appendRow(path: string, row: string): void {
  appendFileSync(path, `${row}\n`, "utf8");
}

export function quantile(sorted: number[], q: number): number {
  if (sorted.length === 0) return 0;
  const i = Math.min(Math.floor(q * sorted.length), sorted.length - 1);
  return sorted[i]!;
}
