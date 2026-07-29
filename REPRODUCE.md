# REPRODUCE.md

Step-by-step recipe for every numeric claim and figure in the BCCA 2026 paper *TallyMesh: Per-Batch Optimistic Settlement and Zero-Knowledge Admission for Auditable Open Service Markets*. Anvil-only; no live testnet required.

## Prerequisites

- Foundry 1.6+ (`forge`, `anvil`)
- Node 20+ with `yarn`
- Python 3.10+ with `numpy`, `matplotlib` (project-local venv recommended: `uv venv .venv && uv pip install --python .venv/bin/python matplotlib numpy`)
- Circom 2.1.8+ and snarkjs 0.7+ (for ZK proving bench only)

The paper's reported gas figures were measured with:
- Foundry 1.7.0 (`forge` opcode-only gas at Cancun EVM target via Anvil; the binary reports 1.6.0-v1.7.0 at commit f83bad91, the v1.7.0 release tag)
- snarkjs 0.7.6 + Circom 2.1.8
- matplotlib 3.10 + numpy 2.0

Gas measurements are EVM-version sensitive; reproducing on a different Anvil EVM target (e.g., Prague schedule for BLOBHASH/calldata) may shift values by single digits per opcode.

## 1. Contract gas measurements (Tab. I, Tab. III, Tab. IV)

```bash
cd contracts
forge build
forge script eval/scripts/E4_PerFunctionGas.s.sol --tc E4_PerFunctionGas    # -> eval/data/raw/e4.csv (6 rows)
forge script eval/scripts/E5_BatchSizeSweep.s.sol --tc E5_BatchSizeSweep    # -> eval/data/raw/e5.csv (35 rows)
forge script eval/scripts/E6_DisputeCost.s.sol --tc E6_DisputeCost          # -> eval/data/raw/e6.csv (3 rows)
```

These produce the optimistic-mode commitment and claim costs and the four baseline rows. The `e5.csv` sweep covers `N ∈ {1, 10, 100, 1000, 5000}` for the per-function path, with extra direct-aggregate probes at `N ∈ {50, 100, 200, 500}`. **Provenance note**: the `SignedVoucherAggregate` rows at `N ∈ {1000, 5000}` are linear extrapolations from the `N=1` and `N=10` direct measurements (block-gas exceeded for a single redemption); all other rows are direct Foundry measurements.

## 2. ZK verifier gas (paper §VI ZK-mode empirical costs)

```bash
cd contracts
forge test --match-contract "BatchSettlementZkTest|CircomBatchVerifierTest" --gas-report
```

Extract `verifyProof`, `verifyBatch`, `submitZkBatch` rows from the gas report. These match the numbers in the paper (202,218 / 209,784 / 263,207 median gas). The committed `zk/build/verification_key.json` and `zk/fixtures/proof.json` make the test deterministic.

The raw extraction is also available at `contracts/eval/data/raw/zk_verifier_gas.csv`.

## 3. Aggregate-claim gas sweep (claimPayoutBatch)

```bash
cd contracts
forge test --match-test test_gas_sweep_amortized -vv --gas-limit 9223372036854775807
```

Emits one `CLAIM_BATCH_GAS_N` console line per `N ∈ {1, 4, 16, 64, 256, 512}` with per-leaf gas. Matches `contracts/eval/data/raw/aggregate_claim_gas.csv`.

## 4. Off-chain Groth16 prover bench (paper §VI ZK-mode empirical costs)

Heaviest step. Needs the 530 MB `BatchValidity_final.zkey`. Two options:

**Option A** — regenerate the proving key locally (~10 min one-time):

```bash
cd zk
yarn install
yarn compile          # -> build/BatchValidity.{r1cs,wasm,sym}
yarn setup:ptau       # downloads pot22_final.ptau (~4.6 GB, one-time)
yarn setup:zkey       # produces build/BatchValidity_final.zkey (~530 MB)
yarn export:verifier  # writes contracts/src/zk/BatchValidityGroth16Verifier.sol
```

**Option B** — download the published `.zkey` artifact (when released as a paper supplement).

Then bench:

```bash
cd zk
bash scripts/bench_prover.sh zk_prover_bench.csv
```

Sweeps `N ∈ {1, 16, 64, 256, 512, 1024}` × 3 trials. Each trial measures wall-clock, user CPU time, system CPU time, %CPU, and peak RSS via `/usr/bin/time -v`. Matches `contracts/eval/data/raw/zk_prover_bench.csv` (median wall-clock 76.7 s at N=1024 on c3-highmem-4 Sapphire Rapids).

## 5. Operating-point sweep (Tab. V archetypes)

```bash
cd contracts
.venv/bin/python eval/lib/run_e11_sweep.py        # -> eval/data/derived/e11_sweep.csv (729 rows)
.venv/bin/python eval/lib/run_e11_archetypes.py   # -> eval/data/derived/e11_archetypes.csv (3 rows)
```

## 6. Cost-crossover Fig. 4

```bash
cd contracts
.venv/bin/python eval/lib/plot_e12_crossover.py
```

Reads measured `G_verify`, `c_prover`, `e10.json` gas-price snapshots; emits `paper-draft/figures/fig4_crossover.pdf` and `eval/data/derived/e12_crossover.csv`. Crossover V_N: Base/OP ≈ $0.97, Arbitrum ≈ $4.78 under archetype τ=900 s.

## 7. Storage growth + USD cost model + security battery

```bash
cd contracts
.venv/bin/python eval/lib/run_e7.py                       # -> eval/data/raw/e7.csv
.venv/bin/python eval/lib/run_e10.py                      # -> eval/data/derived/e10.json
.venv/bin/python eval/lib/run_security_battery_table.py   # -> eval/data/derived/security_battery.csv (19 rows)
```

## 8. SDK integration tests (attacks 1 and 3 closure)

```bash
cd sdk-ts
yarn install
yarn test:integration   # spins up Anvil, deploys contracts, asserts replay + out-of-order revert
```

`test/integration/attacks-1-3.test.ts` is the canonical evidence for Tab. II rows 1 and 3 (replay rejection at SDK + on-chain backstop via `ReceiptAlreadyClaimed`).

## Expected output fingerprints

After a full run, these files exist with the listed row counts (line-counted excluding header):

| File | Rows |
|---|---|
| `contracts/eval/data/raw/e4.csv` | 6 |
| `contracts/eval/data/raw/e5.csv` | 35 |
| `contracts/eval/data/raw/e6.csv` | 3 |
| `contracts/eval/data/raw/e7.csv` | 6 |
| `contracts/eval/data/raw/zk_verifier_gas.csv` | 4 |
| `contracts/eval/data/raw/zk_prover_bench.csv` | 18 |
| `contracts/eval/data/raw/aggregate_claim_gas.csv` | 6 |
| `contracts/eval/data/derived/e10.json` | 369 entries |
| `contracts/eval/data/derived/e11_sweep.csv` | 729 |
| `contracts/eval/data/derived/e11_archetypes.csv` | 3 |
| `contracts/eval/data/derived/e12_crossover.csv` | 1500 |
| `contracts/eval/data/derived/security_battery.csv` | 19 |

`forge test` expects 165 passing tests (160 Solidity + 5 SDK integration) including the `ClaimPayoutBatchTest` suite. `yarn test:unit` in `sdk-ts` expects 24 passing tests.

## Hardware spec for ZK bench (cite when reporting times)

GCE `c3-highmem-4`, 4 vCPU Intel Xeon Sapphire Rapids @ ~3.4 GHz, 32 GB RAM, Ubuntu 22.04.5 LTS, node 20.20.2, snarkjs 0.7.6.
