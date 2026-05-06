# TallyMesh

Implementation artifact for the BCCA 2026 paper *TallyMesh: Intent-Bound Authorization and Batched Settlement for Open Service Markets*.

Public submission repo (when published): `tallymesh-bcca2026`.

## Layout

- `contracts/` — Foundry / Solidity contracts and tests
- `sdk-ts/` — TypeScript SDK (signing, client, service, aggregator) — added Day 4
- `services/` — Python synthetic providers and routing harness — added Day 6
- `eval/` — experiments, plots, tables — added Day 5

## Running tests

```bash
cd contracts
forge test -vvv
```

## TypeScript SDK

The `sdk-ts/` package provides the off-chain glue: EIP-712 typed-data signing for `SessionIntent` / `SessionAccept` / `SignedRequest` / `SignedReceipt`, a client signer + service-side handler with `prevHash`-linked transcripts, Keccak (optimistic) and Poseidon (ZK) Merkle aggregators, a Groth16 prover bridge, and a viem-based settlement helper that talks to the deployed Anvil contracts.

```bash
cd sdk-ts
yarn install
yarn typecheck
yarn test          # 24 unit + 5 integration; integration tests spin up Anvil
```

The integration tests deploy the full contract suite via `forge script`, exercise the optimistic and ZK end-to-end flows, and assert the §2.3 attack-1 / attack-3 closures.
