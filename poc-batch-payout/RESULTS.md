# Results: batch payout with one claim proof

All numbers below come from one run of `./run.sh` on 2026-11-18. Raw output is in `evidence/`, and `results.json` holds every number, including all five proving samples per size.

## Setup

- Machine: Apple M5 Max, 18 cores, macOS arm64. Go 1.24.5, gnark 0.13.0, gnark-crypto 0.18.0, forge 1.5.1, solc 0.8.24, Shanghai gas schedule, optimizer 200 runs.
- Claim proof: Groth16 over BN254, Poseidon2 tree padded with zero leaves to the next power of two, five public inputs. One circuit, one fresh local setup and one Solidity verifier per batch size N.
- Proving time is the median of 5 runs on the same witness and includes witness solving. Setup time is a single sample.
- Receipts: sequence s pays 10 or 110 minor units, so a batch of N totals 60 N units. Amounts are abstract minor units.
- Baseline: `src/PerReceiptPayout.sol`, our own per-receipt contract in the same harness. It is not the contract measured in the paper. For each receipt it checks a Keccak Merkle path against a finalized root, sets a paid flag in a mapping, adds the amount, and pays once at the end. Same asset (native wei), one session, one provider, same recipient, same finalized-root gate.
- Gas is the forge gas report value for a single `claim` call. In this forge version that value includes the 21,000 intrinsic gas and the calldata gas of the call (`evidence/gas-report-probe.txt`). Both designs make their first payment to an empty account, so both carry the same new-account charge.

## Main table

| N | Constraints | Prove median ms (min, max) | Claim-proof gas | per receipt | Baseline gas | per receipt | Baseline / claim-proof |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 16 | 7,310 | 16.7 (15.9, 18.1) | 286,364 | 17,897.8 | 541,501 | 33,843.8 | 1.89 |
| 64 | 28,286 | 57.8 (54.1, 59.9) | 286,352 | 4,474.2 | 2,144,894 | 33,514.0 | 7.49 |
| 100 | 44,576 | 89.8 (85.0, 96.3) | 286,352 | 2,863.5 | 3,444,970 | 34,449.7 | 12.03 |
| 256 | 112,190 | 174.5 (168.6, 179.9) | 286,352 | 1,118.6 | 9,124,753 | 35,643.6 | 31.87 |
| 1024 | 447,809 | 699.0 (626.1, 716.6) | 286,352 | 279.6 | 41,221,465 | 40,255.3 | 143.95 |

The last column is baseline claim gas divided by claim-proof claim gas. No size was skipped. The test VM reports a block gas limit of 1,073,741,824, so the 1024-receipt baseline claim ran as one call. At 41,221,465 gas it would not fit on a chain whose block or transaction gas limit is below that figure. Chain limits were not checked here.

## Other measurements

| N | Setup ms (1 sample) | Native verify median ms | `verifyProof` gas | Claim-proof second claim | Baseline second claim | Claim-proof calldata bytes | Baseline calldata bytes | Baseline calldata gas |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 16 | 165 | 0.722 | 214,606 | 261,364 | 516,597 | 356 | 5,252 | 47,444 |
| 64 | 557 | 0.727 | 214,606 | 261,340 | 2,120,494 | 356 | 24,708 | 251,640 |
| 100 | 915 | 0.735 | 214,606 | 261,364 | 3,420,786 | 356 | 41,732 | 443,480 |
| 256 | 2,348 | 0.748 | 214,606 | 261,352 | 9,105,201 | 356 | 114,820 | 1,266,808 |
| 1024 | 9,216 | 0.908 | 214,606 | 261,352 | 41,205,909 | 356 | 524,420 | 6,128,888 |

- `verifyProof` gas is the inner call from the escrow to the verifier and has no intrinsic gas in it.
- The second claim is the next batch (sequences N+1 to 2N, its own root and proof) claimed in the same test transaction as the first. Storage slots and accounts are already warm and the recipient account already exists. It is not a separate transaction.
- Claim-proof calldata gas is 4,940 or 4,952 depending on the proof bytes.
- Derived from the numbers above (report value minus 21,000 minus calldata gas): claim-proof execution is 260,412 gas at every N. Baseline execution per receipt is 29,566 at 16, 29,254 at 64, 29,805 at 100, 30,613 at 256 and 34,250 at 1024.

## The earlier 100-receipt data point

The earlier single run reported 44,576 constraints, 214,606 `verifyProof` gas and 286,364 claim gas (`evidence/original-100-evm-claim.txt`). Constraints and `verifyProof` gas reproduce exactly. Claim gas at N=100 is 286,352 in this run, 12 gas lower. The cause is calldata, not the contract. Every `go run .` makes a fresh setup and a new proof, and the gas report charges 16 gas per nonzero calldata byte and 4 per zero byte, so a proof with one more zero byte costs 12 gas less. A rebuild of the original contract and test with another new proof gave 286,340 (checked by hand during this work, output not saved). Execution gas is the same 260,412 at every N. The earlier figure is consistent with this: the N=16 proof in this run has 4,952 calldata gas and its claim measured 286,364 (260,412 + 21,000 + 4,952). The earlier proof itself was not kept, so its calldata gas was not measured.

## Rejection tests

All pass for every N (16, 64, 100, 256, 1024). Each test breaks one condition while every other input stays valid, checks that the cursor and the balance did not move, and then runs the valid claim as a control. The whole suite is 75 tests, 0 failed (`evidence/evm-all-tests.txt`).

Claim-proof contract (`test/Payout.t.sol`):

- `testRejectRootNotFinalized`: valid proof, root not marked final.
- `testRejectWrongStart`: valid proof and finalized root for the second batch while the cursor is still at 1.
- `testRejectTotalAboveBalance`: valid proof, escrow funded with one unit less than the total.
- `testRejectInflatedTotal`: total plus one with enough balance, so the proof check is what fails.
- `testRejectTamperedProofWord`: one bit flipped in each of the 8 proof words in turn. This makes a malformed curve point, and the precompile then burns all gas it was given, so the test caps the call at 1,000,000 gas. A well-formed proof for a wrong statement is covered by the inflated-total test.
- `testRejectReplay`: the same claim sent again after it was paid.

Baseline contract (`test/PerReceiptPayout.t.sol`): `testRejectRootNotFinalized`, `testRejectInflatedAmount`, `testRejectReplay`.

The Go run also rejects, for every N: a claim before finality, an inflated total, a wrong provider, an overdraft, a replay, and a same-total substitution of two amounts under the old root.

## What the numbers show

- On-chain claim gas for the claim proof does not depend on N. It is about 286 thousand gas from 16 to 1024 receipts, of which 214,606 is the Groth16 verifier.
- The per-receipt baseline grows linearly, at 33.5 to 40.3 thousand gas per receipt. The per-receipt cost rises with N because the Merkle path and its calldata get longer.
- The claim proof is cheaper at every measured size, by 1.89 times at 16 receipts and 144 times at 1024. The break-even is below 16 receipts and was not measured.
- Constraints grow at about 437 to 457 per receipt. Proving takes 16.7 ms at 16 receipts and 699 ms at 1024 on this machine.

## What the numbers do not show

- These are local forge gas reports, not receipts from a live chain. There are no fee or currency figures.
- The baseline is one simple design. A bitmap for paid flags, a Merkle multiproof, or a contiguous cursor would lower it. None of these was measured, so the ratio is specific to this baseline.
- The baseline is not the paper's contract. Its derived execution cost per receipt (29,254 at 64 receipts) is close to the 29,901 the paper reports at 64 receipts, but the contracts differ and this is not a reproduction.
- The claim-proof side leaves out the cost of admitting and finalizing the root, verifier deployment (about 1.19 million gas per batch size), data publication, and off-chain proving hardware. The baseline also leaves out root finalization.
- Each N has its own circuit and trusted setup. A deployment would need one setup per supported batch size, or padding to a fixed size. The setup here is a local demonstration, not a ceremony.
- Proving times are five runs on one machine with a fixed witness. Setup time is one sample.
- The fixture uses synthetic payload identifiers. The proof does not show customer consent or that the receipts match the admitted settlement records.
