# TallyMesh Contracts — Toolchain Capture

This file records the exact toolchain used to produce the committed gas snapshot, contract-size report, and test results. Reproducibility per `experimental-design.md §5`.

| Tool | Version |
|---|---|
| forge | 1.6.0-v1.7.0 (commit f83bad912a9dba7bf0371def1e70bb1896048356) |
| anvil | 1.6.0-v1.7.0 (commit f83bad912a9dba7bf0371def1e70bb1896048356) |
| cast | 1.6.0-v1.7.0 (commit f83bad912a9dba7bf0371def1e70bb1896048356) |
| solc | 0.8.26 (pinned in `foundry.toml`) |
| OpenZeppelin Contracts | v5.6.1 |
| forge-std | v1.16.1 |
| OS | Linux 6.1.0-44-cloud-amd64 x86_64 |
| Captured at git commit | c98766a5cfdbf32f41f913c2078ffea5f6c67c4b (manifest landed at this commit; gas snapshot captured against parent 3fe1845b649d138c1e46120cf07f602ba35195ed) |

## ZK pipeline (added Day 4b)

| Tool | Version |
|---|---|
| circom | 2.2.3 |
| snarkjs | ^0.7.5 |
| circomlib | ^2.0.5 |
| circomlibjs | ^0.1.7 |
| node | v24.13.1 |
| Powers-of-Tau | pot22_final (Hermez ceremony, sourced from Polygon zkEVM mirror) |
| Verifier scheme | Groth16 over BN254 |
| Merkle hash (ZK path) | Poseidon (arity 2, depth 10 → MAX_RECEIPTS = 1024) |
| Merkle hash (optimistic path) | Keccak-256 (`ReceiptLib`, unchanged) |
| Circuit constraint count | 1,148,411 |
| Verifier on-chain gas | ~217k (measured via `CircomBatchVerifier.t.sol`) |

## TypeScript SDK (added Day 4c)

| Tool | Version |
|---|---|
| node | v24.13.1 |
| yarn | 1.x |
| typescript | ^5.5 |
| viem | ^2.21 |
| vitest | ^2.1 |
| circomlibjs | ^0.1.7 |

The SDK lives in `code/sdk-ts/`. Tests are split into `test/unit/` (no chain) and `test/integration/` (spins up Anvil + runs `forge script`). Run both with `yarn test`.

## Eval harness (added Day 5)

| Tool | Version |
|---|---|
| Python | 3.10+ via `uv` |
| Forge gas snapshots | `vm.startSnapshotGas` / `vm.stopSnapshotGas` (forge-std v1.16+) |

Eval scripts live in `eval/scripts/` (Forge) and `eval/lib/` (Python). Raw measurement CSVs in `eval/data/raw/`; derived JSON in `eval/data/derived/`. See `eval/README.md` for full reproduction commands.

Files committed:
- `eval/data/raw/e4.csv` (per-function gas)
- `eval/data/raw/e5.csv` (gas/call vs batch size)
- `eval/data/raw/e6.csv` (dispute roundtrip)
- `eval/data/raw/e7.csv` (storage growth)
- `eval/data/derived/e10.json` (gas-price sensitivity)
- `eval/data/derived/e11_sweep.csv` (E11 trilemma sweep, 243 operating points)
- `eval/data/derived/e11_archetypes.csv` (E11 archetype worked examples for the paper)
- `eval/data/derived/security_battery.csv` (E8 §2.3 attack-coverage table, 18 attacks across crypto/core/settlement/escrow/governance/router layers; 15 covered, 3 design-level)
