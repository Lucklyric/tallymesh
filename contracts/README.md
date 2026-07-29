# TallyMesh Contracts

Solidity implementation for the BCCA 2026 paper *TallyMesh: Intent-Bound Authorization and Batched Settlement for Open Service Markets*.

## Layout

- `src/lib/` — `EIP712Domain`, `Signatures` (OZ ECDSA + ERC-1271), `ReceiptLib` (domain-separated leaves + Merkle), `FeeSchedule` (hash-locked commitment)
- `src/interfaces/` — `IServiceRegistry`
- `src/` — `ServiceRegistry`, `RolePolicyRegistry`, `DepositEscrow`, `BatchSettlement` (optimistic), `DisputeManager`
- `src/baselines/` — added Day 5 (`PerRequestNaive`, `PerRequestEventOnly`, `SignedVoucherNetting`, `SignedVoucherAggregate`)
- `test/unit/` — per-contract unit tests
- `test/unit/mocks/` — `MockERC1271`, `PhantomERC1271`
- `test/integration/` — end-to-end flow
- `test/invariant/` — Foundry invariant tests
- `test/security/` — adversarial battery (§2.3 of the experimental design)

## Build and test

```bash
forge build
forge test -vvv
forge test --gas-report
forge snapshot
```

## Toolchain

See `TOOLCHAIN.md` for exact tool versions captured at the latest gas snapshot.
