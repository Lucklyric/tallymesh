# Proof-based payout for a finalized batch

This local experiment measures the payout step only. A provider collects a batch of N charges with one Groth16 proof and one local EVM call. N is 16, 64, 100, 256 or 1024. Admission, consent, and data availability are outside the proof. No funds leave the test VM.

Run from this directory with Go 1.24, Foundry, and Solidity 0.8.24:

    go run .
    forge test --offline

    ./run.sh

The first two commands build and test. `run.sh` repeats them, measures gas per batch size, and rewrites `evidence/` and `results.json` (it runs `collect.py` through uv). The Go run creates a fresh local setup, Solidity verifier and matching test vector for each batch size under `generated/`. Use those files together. `go run .` alone also rewrites `evidence/go-sweep.json`, so run `./run.sh` afterward to keep `results.json` and the evidence from one run. Setup is for demonstration, not a production ceremony.

## What the proof binds

Five public inputs: payout root, session, provider, first sequence number, and total in integer minor units. Count is fixed when the circuit is compiled, so each batch size has its own circuit, setup and verifier. Each private leaf has a payload identifier and a 64-bit charge. Its position fixes its 64-bit sequence number. The leaf hash commits to the payload and packed sequence/amount. A binary Poseidon2 tree pads the leaves with zero to the next power of two (100 leaves to 128). The final compression binds the session and provider to the tree root. Summing up to 1024 unsigned 64-bit inputs cannot overflow the BN254 scalar field.

The fixture uses synthetic payload identifiers, not signed paper receipts. Inclusion proofs for individual leaves remain possible if the records and paths remain available. The proof does not certify customer assent or actual inference. In production the index must match the canonical signed receipt sequence, and the charge and payload digest must derive from that same receipt. Otherwise the construction proves accounting over arbitrary rows.

## State and integration

For this experiment one funded reservation serves one session and one provider. A fixture injects an accepted root. The production adapter would accept it only from the settlement contract after challenge-free finalization or validity verification. Neither admission path is implemented here. Settlement must bind the payout commitment to exactly the admitted records, through a canonical commitment or a consistency proof. Merely publishing an unrelated second root is insufficient.

Anyone may relay the claim, but the immutable provider alone receives the payment. Require the root to be finalized, the starting sequence to equal the next unpaid sequence, the balance to cover the total, and the proof to verify. Advance the cursor before transfer; failure reverts the entire claim. The example transfers one test wei per cent. Production would need the actual asset, reservation accounting, chain/contract domain separation and compatible receipt identities. Fixed contiguous ranges require ordered settlement. Mixing this cursor with the existing individual claim path without shared spent state would enable double payment.

## Benchmark

Measured results are in [RESULTS.md](RESULTS.md), with raw numbers in `results.json` and command output in `evidence/`. They cover batch sizes 16, 64, 100, 256 and 1024: constraints, setup, proving (median of 5), native verify, `verifyProof` gas and claim gas, a per-receipt baseline contract in the same harness (`src/PerReceiptPayout.sol`), and the rejection tests.

At 100 receipts (50 at 10 units and 50 at 110 units, 6,000 units): 44,576 constraints, 214,606 `verifyProof` gas, 286,352 claim gas for the claim proof and 3,444,970 claim gas for the per-receipt baseline. Claim gas shifts by multiples of 12 between runs because each run makes a new proof with different calldata bytes. RESULTS.md explains this and lists what the numbers do not show.

`evidence/SHA256.txt` covers the sources and the paper PDF. Check it with `shasum -a 256 -c evidence/SHA256.txt`. Files under `generated/` and the measurement outputs change on every run and are not hashed.
