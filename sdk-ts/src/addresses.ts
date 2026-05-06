import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import type { Address } from "viem";

export interface AddressBook {
  ServiceRegistry: Address;
  RolePolicyRegistry: Address;
  RouterRegistry: Address;
  DepositEscrow: Address;
  BatchSettlement: Address;
  DisputeManager: Address;
  BatchValidityGroth16Verifier: Address;
  CircomBatchVerifier: Address;
}

export function loadLocalAddresses(path?: string): AddressBook {
  const target = path ?? defaultPath();
  const raw = readFileSync(target, "utf8");
  return JSON.parse(raw) as AddressBook;
}

function defaultPath(): string {
  const here = dirname(fileURLToPath(import.meta.url));
  return join(here, "..", "addresses.local.json");
}
