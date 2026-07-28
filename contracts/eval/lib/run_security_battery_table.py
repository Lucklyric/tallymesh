# code/contracts/eval/lib/run_security_battery_table.py
"""Generate the §2.3 security-battery coverage table for the paper.

Each row maps an attack ID to its current test coverage. Status values:
  - 'covered'       — concrete Forge or sdk-ts test demonstrates the defense.
  - 'partial'       — a primitive-level test exists, but no end-to-end
                       scenario (or coverage spans only one layer when both
                       on-chain and off-chain enforcement exist).
  - 'design'        — defense is structural (no setter exists, no on-chain
                       enforcement point) rather than a discrete test.
"""
from __future__ import annotations
import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT  = ROOT / "data" / "derived" / "security_battery.csv"

# Each tuple: (id, name, layer, expected_outcome, status, test_file, test_function, notes)
ROWS = [
    (1,  "Replay of settled SignedRequest",            "core",       "revert: nonce/seq",
     "covered",
     "sdk-ts/test/integration/attacks-1-3.test.ts; contracts/test/security/SecurityBatteryDay3.t.sol",
     "Attacks 1+3 closure (sdk-ts) + cross-batch (Forge); on-chain backstop via claimedReceipt[]",
     "off-chain Service rejects re-handled SignedRequest; on-chain claimedReceipt[] mapping rejects re-claim"),
    (2,  "Duplicate receipt within batch",             "settlement", "revert: leaf-uniqueness",
     "covered",
     "contracts/test/security/SecurityBatteryDay3.t.sol",
     "test_attack02_duplicateReceiptWithinBatch",
     "second claim against same receiptKey reverts ReceiptAlreadyClaimed"),
    (3,  "Out-of-order seq in linked transcript",      "core",       "revert: seq/prevHash mismatch",
     "covered",
     "sdk-ts/test/integration/attacks-1-3.test.ts",
     "Attack 3 closure",
     "off-chain Service tracks lastReceiptHash and rejects mismatches"),
    (4,  "Invalid role-policy proof",                  "core",       "revert at session accept",
     "design",
     "contracts/test/unit/RolePolicyRegistry.t.sol",
     "test_setRolePolicy_onlyServiceOwner; test_setRolePolicy_revertsForUnknownService",
     "RolePolicyRegistry primitives are owner-gated; v1 design routes session-accept rejection through off-chain Service consulting the registry"),
    (5,  "Per-call overspend",             "core",       "off-chain policy; over-ceiling challengeable",
     "design",
     "paper threat model (service boundary)",
     "-",
     "per-call cap is an off-chain service obligation; an over-ceiling charge remains challengeable via DisputeManager (attack 7)"),
    (6,  "Forged service signer",                      "core",       "rejected: signer not in registry set",
     "covered",
     "contracts/test/unit/ServiceRegistry.t.sol",
     "test_isServiceSigner_returnsFalseForUnregistered",
     "off-chain Service.handle verifies signer recovery; ServiceRegistry primitives owner-gate signer set"),
    (7,  "Invalid-batch fraud proof",                  "settlement", "challenge succeeds, slash",
     "covered",
     "contracts/test/security/SecurityBatteryDay3.t.sol",
     "test_attack07_validChallengeSlashes",
     "DisputeManager invalidates batch + slashes bond to challenger"),
    (8,  "Revocation propagation",                     "core",       "revert at registry check",
     "design",
     "contracts/test/unit/ServiceRegistry.t.sol",
     "test_deactivateService",
     "ServiceRegistry.deactivateService is owner-gated; off-chain Service consults registry at session-accept time per v1 design"),
    (9,  "Cross-chain replay (stale chainId)",         "crypto",     "signer diverges: domain mismatch",
     "covered",
     "contracts/test/security/CrossDomainReplay.t.sol",
     "test_attack09_crossChainReplay_recoversDifferentSigner",
     "EIP-712 domain embeds chainId; stale chainId yields different recovered signer"),
    (10, "Cross-contract replay (stale verifyingContract)", "crypto", "signer diverges: domain mismatch",
     "covered",
     "contracts/test/security/CrossDomainReplay.t.sol",
     "test_attack10_crossContractReplay_recoversDifferentSigner",
     "EIP-712 domain embeds verifyingContract; stale value yields different recovered signer"),
    (11, "Cross-batch double-claim",                   "settlement", "revert: receipt-already-settled",
     "covered",
     "contracts/test/security/SecurityBatteryDay3.t.sol",
     "test_attack11_crossBatchDoubleClaimGlobalKey",
     "global claimedReceipt[keccak256(sessionId, seq, requestHash)] mapping prevents replay across batches"),
    (12, "ECDSA signature malleability (high-s)",      "crypto",     "revert: canonical-s enforced",
     "covered",
     "contracts/test/unit/Signatures.t.sol",
     "test_recoverEOA_revertsOnHighS",
     "OZ ECDSA.recover reverts ECDSAInvalidSignatureS for any s above the half-order"),
    (13, "ERC-1271 phantom signer",                    "crypto",     "rejected: registry binding required",
     "covered",
     "contracts/test/security/Erc1271ProtocolBinding.t.sol",
     "test_attack13_phantomValidatesAnything_butIsNotInRegistry",
     "PhantomERC1271 returns valid magic for any hash; ServiceRegistry membership check rejects unbound address"),
    (14, "Fee-schedule poisoning (TOCTOU)",            "core",       "revert: fee-hash immutable",
     "covered",
     "contracts/test/security/FeeScheduleImmutable.t.sol",
     "test_attack14_feeScheduleHashIsImmutableAfterRegistration",
     "ServiceRegistry exposes no fee-hash setter; structural defense"),
    (15, "Escrow withdraw / reservation race",         "escrow",     "no double-spend",
     "covered",
     "contracts/test/invariant/DepositEscrow.invariant.t.sol",
     "DepositEscrow invariant suite",
     "invariants assert balance accounting consistency under random sequences of deposit/reserve/release/settle"),
    (16, "Malformed Merkle proof / leaf-type collision","settlement", "revert: leaf domain-separated",
     "covered",
     "contracts/test/unit/ReceiptLib.t.sol",
     "test_leafHash_differsFromRawAbiEncode",
     "leafHash includes RECEIPT_TYPEHASH; raw abi.encode of fields hashes to a different root"),
    (17, "Unauthorized registry/signing-key update",   "governance", "revert: owner-gated",
     "covered",
     "contracts/test/unit/{ServiceRegistry,RolePolicyRegistry,RouterRegistry}.t.sol",
     "test_*_onlyOwner / NotServiceOwner",
     "every registry mutation function is owner-gated"),
    (18, "Router false-route evidence",                "router",     "downgrade: still settles, evidence flagged",
     "design",
     "contracts/test/unit/RouterRegistry.t.sol",
     "test_register_emitsEvent; test_addBond_*; test_deactivate_*",
     "v1 contract surface stops at router lifecycle and bond; routing-receipt evidence handling is sdk-ts off-chain analytical and not implemented. Mark as design/future, not covered."),
    (19, "Content-mismatched blob denying payout",     "settlement", "off-chain watcher invariant; not on-chain challengeable",
     "design",
     "paper threat model (blob DA)",
     "-",
     "hash-bound but content-mismatched blob passes BLOBHASH check; reconstruction is an off-chain watcher invariant, not an on-chain predicate"),
]


def main() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["id", "name", "layer", "expected_outcome", "status", "test_file", "test_function", "notes"])
        for r in ROWS:
            w.writerow(r)
    by_status = {}
    for r in ROWS:
        by_status[r[4]] = by_status.get(r[4], 0) + 1
    print(f"wrote {OUT}")
    print(f"summary: {dict(sorted(by_status.items()))}")


if __name__ == "__main__":
    main()
