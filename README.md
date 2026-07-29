# TallyMesh

Implementation artifact for the paper *TallyMesh: Per-Batch Optimistic Settlement and Zero-Knowledge Admission for Auditable Open Service Markets*, accepted at the 8th International Conference on Blockchain Computing and Applications (BCCA 2026).

This repository is the reference implementation cited in the paper's reproducibility section. It contains the Solidity contracts (optimistic batch settlement, dispute manager, ZK validity-proof admission verifier, ERC-1271/EIP-712 helpers, registries, escrow), a TypeScript SDK (typed-data signing, KeccakAggregator, Poseidon aggregator, Groth16 prover bridge, viem-based settlement helper), a Circom + snarkjs ZK pipeline, and an evaluation harness producing the gas, storage, attack-coverage, and operating-point CSV/figure data behind every numeric claim in the paper.

## Repository layout

```
code/
├── contracts/         Foundry workspace
│   ├── src/           BatchSettlement, DepositEscrow, DisputeManager, registries,
│   │                  baselines (PerRequestNaive, PerRequestEventOnly,
│   │                  SignedVoucherNetting, SignedVoucherAggregate),
│   │                  zk/BatchValidityGroth16Verifier + CircomBatchVerifier
│   ├── test/          165 unit + invariant + integration + security tests
│   └── eval/          experiment scripts (E4 per-function gas, E5 batch-size
│                      sweep, E6 dispute cost, E7 storage growth, E10 USD model,
│                      E11 operating-point sweep, claimPayoutBatch sweep,
│                      ZK verifier gas, prover bench)
├── sdk-ts/            TypeScript SDK + integration tests (vitest + Anvil)
├── zk/                Circom circuit (BatchValidity.circom),
│                      snarkjs scripts (compile, setup, prove, export verifier),
│                      bench harness (bench_prover.sh, build_input_n.js)
└── REPRODUCE.md       Step-by-step recipe for every CSV and figure in the paper
```

## Quick start

```bash
cd contracts && forge test -vvv          # 165 tests
cd ../sdk-ts && yarn install && yarn test # 24 unit + 5 integration
cd ../zk && yarn install && yarn compile  # Circom -> r1cs/wasm
```

For full reproduction of every paper number, see [`REPRODUCE.md`](./REPRODUCE.md).

## Citation

Please use the metadata in [`CITATION.cff`](./CITATION.cff). A BibTeX entry will be added when the paper appears in the BCCA 2026 proceedings.
