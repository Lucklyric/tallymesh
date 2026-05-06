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
