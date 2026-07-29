# TallyMesh SDK (TypeScript)

Off-chain SDK for the TallyMesh BCCA 2026 paper. Drives the full client → service → aggregator → settlement flow against an Anvil node.

## Modules

- `domain`, `types` — EIP-712 typed-data schemas mirroring the on-chain typehashes.
- `client` — wallet-side signer. Produces a `prevHash`-linked transcript of `SignedRequest`s.
- `service` — service-side request verifier + receipt signer.
- `aggregator-keccak` — Keccak-256 Merkle aggregator for the optimistic settlement path.
- `aggregator-poseidon` — Poseidon Merkle aggregator + Groth16 prover bridge for the ZK path.
- `settlement` — viem-based contract helper.

## Quickstart

```bash
yarn install
yarn typecheck
yarn test:unit                 # pure unit tests, no chain
yarn test:integration          # spins up Anvil, deploys contracts, full e2e
```

## How it fits with the rest of the repo

- The Forge contracts live in `../contracts/`. Run `forge build` there before integration tests.
- The ZK pipeline lives in `../zk/`. Run `cd ../zk && yarn install && yarn all` once before the ZK integration test.
- The SDK ships ABI fragments (not full Foundry artifacts) in `src/abis.ts` to keep tests fast.

## Notes

- Native ETH only (matches `DepositEscrow`).
- Anvil only — no testnet calls.
- Closed-form Poseidon hashing via `circomlibjs`. The SDK's Poseidon root must match the circuit; see `aggregator-poseidon.ts` for the encoding.
