# TallyMesh ZK Pipeline

Groth16 + Circom + snarkjs pipeline for the validity-proof settlement path.

## Statement

For private input `chargedAmounts[MAX_RECEIPTS]` and `leafTags[MAX_RECEIPTS]` (with padding zeros for unused slots) and public input `(receiptsRoot, receiptCount, chargedCeiling)`, prove:

1. Poseidon Merkle root over the active leaves equals `receiptsRoot`.
2. Padding leaves at index `>= receiptCount` are zero in both fields.
3. For every active receipt, `chargedAmount <= chargedCeiling`.

`MAX_RECEIPTS = 1024` (depth 10) is fixed at circuit-compile time; smaller batches pad with zeros.

## Generate artifacts

One-time setup (large download for ptau):

```bash
cd UA/research/DeAuth/code/zk
yarn install
yarn compile
yarn setup:ptau     # downloads pot22_final.ptau (~700MB) to build/
yarn setup:zkey     # trusted-setup ceremony; commits BatchValidity_final.zkey + verification_key.json
yarn export:verifier  # writes auto-generated Solidity verifier under contracts/src/zk/
```

Per-fixture:

```bash
yarn build:input    # writes fixtures/input.json
yarn prove:fixture  # writes fixtures/proof.json, fixtures/public.json
yarn proof:to-solidity  # prints abi-encoded proof bytes for use in Foundry tests
```

## Files in version control

- `circuits/BatchValidity.circom` — circuit source
- `circuits/PoseidonMerkleRoot.circom` — helper
- `build/BatchValidity_final.zkey` — proving + verification key (committed for reproducibility, ~MBs)
- `build/verification_key.json` — verification key (small)
- `fixtures/input.json`, `fixtures/proof.json`, `fixtures/public.json` — deterministic test fixtures
- `scripts/*.js` — orchestration

## Files NOT in version control

- `*.ptau` — Powers-of-Tau, too large; downloaded by `setup:ptau`
- `build/*.r1cs`, `*.wasm`, `*.sym`, `*_js/` — regenerable from circuit source
- `node_modules/` — npm dependencies
