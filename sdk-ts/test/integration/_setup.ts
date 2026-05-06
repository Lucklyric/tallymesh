// Helpers shared by integration tests: Anvil lifecycle + deploy + viem clients.
import { spawn, spawnSync, type ChildProcess } from "node:child_process";
import { existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import {
  createPublicClient, createWalletClient, http, type Address,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { foundry } from "viem/chains";
import { loadLocalAddresses, type AddressBook } from "../../src/addresses.js";

export const RPC = "http://127.0.0.1:8545";

// Canonical Anvil dev keys.
export const ANVIL_KEYS = {
  deployer: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
  payer:    "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",
  service:  "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a",
  submitter:"0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6",
} as const;

function repoRoot(): string {
  const here = dirname(fileURLToPath(import.meta.url));
  // here = sdk-ts/test/integration → ascend three levels to code/
  return join(here, "..", "..", "..");
}

export async function startAnvil(): Promise<ChildProcess> {
  const proc = spawn("anvil", ["--silent"], { stdio: "ignore" });
  // Wait for the JSON-RPC port.
  const start = Date.now();
  while (Date.now() - start < 10_000) {
    try {
      const r = await fetch(RPC, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "eth_chainId", params: [] }),
      });
      if (r.ok) return proc;
    } catch { /* retry */ }
    await new Promise((res) => setTimeout(res, 100));
  }
  proc.kill();
  throw new Error("anvil did not start within 10s");
}

export function deploy(): AddressBook {
  const contracts = join(repoRoot(), "contracts");
  const res = spawnSync(
    "forge",
    [
      "script", "script/DeployLocal.s.sol",
      "--rpc-url", RPC,
      "--private-key", ANVIL_KEYS.deployer,
      "--broadcast",
      "--ffi",
      "--silent",
    ],
    { cwd: contracts, stdio: "pipe", encoding: "utf8" },
  );
  if (res.status !== 0) {
    throw new Error(`forge script failed:\n${res.stdout}\n${res.stderr}`);
  }
  const addrPath = join(repoRoot(), "sdk-ts", "addresses.local.json");
  if (!existsSync(addrPath)) throw new Error(`addresses.local.json not written at ${addrPath}`);
  return loadLocalAddresses(addrPath);
}

export function publicClient() {
  return createPublicClient({ chain: foundry, transport: http(RPC) });
}

export function walletClientFor(privateKey: `0x${string}`) {
  return createWalletClient({
    chain: foundry,
    transport: http(RPC),
    account: privateKeyToAccount(privateKey),
  });
}

export function accountFor(privateKey: `0x${string}`): { address: Address } {
  return privateKeyToAccount(privateKey);
}
