"""Builds results.json from the files that run.sh wrote under evidence/. Prints the RESULTS.md table."""
import json, re

sizes = [16, 64, 100, 256, 1024]
go = {row["receipts"]: row for row in json.load(open("evidence/go-sweep.json"))}

def report(kind, n, test, contract, function):
    rows = json.load(open(f"evidence/gas-json/{kind}-{n}-{test}.json"))
    for row in rows:
        if row["contract"].endswith(":" + contract):
            for name, stats in row["functions"].items():
                if name.startswith(function + "("):
                    return stats
    raise KeyError((kind, n, test, contract, function))

calldata = {}
suite = None
for line in open("evidence/evm-calldata.txt"):
    found = re.search(r":(ClaimProof|Baseline)(\d+)Test", line)
    if found:
        suite = (found.group(1), int(found.group(2)))
    found = re.match(r"\s+(\w+): (\d+)", line)
    if found and suite:
        calldata.setdefault(suite, {})[found.group(1)] = int(found.group(2))

rejections = sorted(set(re.findall(r"\[PASS\] (testReject\w+)\(\)", open("evidence/evm-rejections.txt").read())))
failed = re.findall(r"\[FAIL[^\n]*", open("evidence/evm-all-tests.txt").read())
summary = re.findall(r"Ran \d+ test suites.*", open("evidence/evm-all-tests.txt").read())

out = {
    "notes": [
        "Gas figures are forge gas report values for one call. In this forge version they include the 21000 intrinsic gas and the calldata gas of the call.",
        "second_claim is the second claim call inside one test transaction (min of the two calls). Storage and accounts are already warm and the recipient account already exists.",
        "Proving times include witness solving. Setup is one sample. Amounts are abstract minor units.",
        "baseline is this repository's own per-receipt contract (src/PerReceiptPayout.sol), not the contract measured in the paper.",
    ],
    "environment": open("evidence/environment.txt").read().splitlines(),
    "block_gaslimit_in_test_vm": calldata[("ClaimProof", 100)]["block_gaslimit_in_test_vm"],
    "forge_suite_summary": summary,
    "forge_failures": failed,
    "rejection_tests_passed_claim_proof": {},
    "rejection_tests_passed_baseline": {},
    "sizes": [],
}
text = open("evidence/evm-rejections.txt").read()
for block in text.split("\nRan ")[1:]:
    found = re.search(r":(ClaimProof|Baseline)(\d+)Test", block)
    if found:
        key = "rejection_tests_passed_claim_proof" if found.group(1) == "ClaimProof" else "rejection_tests_passed_baseline"
        out[key][found.group(2)] = sorted(re.findall(r"\[PASS\] (testReject\w+)\(\)", block))

table = ["| N | Constraints | Prove median ms (min, max) | Claim-proof gas | per receipt | Baseline gas | per receipt | Baseline / claim-proof |", "|---:|---:|---:|---:|---:|---:|---:|---:|"]
for n in sizes:
    proof_first = report("ClaimProof", n, "testClaim", "FinalityFixture", "claim")
    proof_both = report("ClaimProof", n, "testSecondClaim", "FinalityFixture", "claim")
    verify = report("ClaimProof", n, "testClaim", f"Verifier{n}", "verifyProof")
    base_first = report("Baseline", n, "testClaim", "BaselineFixture", "claim")
    base_both = report("Baseline", n, "testSecondClaim", "BaselineFixture", "claim")
    assert proof_first["calls"] == 1 and base_first["calls"] == 1 and proof_both["calls"] == 2 and base_both["calls"] == 2
    assert proof_both["max"] == proof_first["max"] and base_both["max"] == base_first["max"]
    p, b = proof_first["max"], base_first["max"]
    row = dict(go[n])
    row["claim_proof"] = {
        "verify_proof_gas": verify["max"],
        "claim_gas": p,
        "claim_gas_per_receipt": round(p / n, 1),
        "second_claim_gas": proof_both["min"],
        "calldata_bytes": calldata[("ClaimProof", n)]["claim_calldata_bytes"],
        "calldata_gas_included": calldata[("ClaimProof", n)]["claim_calldata_gas_at_4_per_zero_16_per_nonzero"],
    }
    row["baseline"] = {
        "claim_gas": b,
        "claim_gas_per_receipt": round(b / n, 1),
        "second_claim_gas": base_both["min"],
        "calldata_bytes": calldata[("Baseline", n)]["claim_calldata_bytes"],
        "calldata_gas_included": calldata[("Baseline", n)]["claim_calldata_gas_at_4_per_zero_16_per_nonzero"],
    }
    row["baseline_gas_over_claim_proof_gas"] = round(b / p, 2)
    # Derived, not separately measured: report value minus 21000 intrinsic minus calldata gas.
    for side in ("claim_proof", "baseline"):
        execution = row[side]["claim_gas"] - 21000 - row[side]["calldata_gas_included"]
        row[side]["derived_execution_gas"] = execution
        row[side]["derived_execution_gas_per_receipt"] = round(execution / n, 1)
    out["sizes"].append(row)
    table.append(f"| {n} | {row['constraints']:,} | {row['prove_ms_median']:.1f} ({row['prove_ms_min']:.1f}, {row['prove_ms_max']:.1f}) | {p:,} | {p / n:,.1f} | {b:,} | {b / n:,.1f} | {b / p:.2f} |")

json.dump(out, open("results.json", "w"), indent=2)
open("results.json", "a").write("\n")
print("\n".join(table))
print()
print("| N | Setup ms (1 sample) | Native verify median ms | verifyProof gas | Claim-proof second claim | Baseline second claim | Claim-proof calldata bytes | Baseline calldata bytes | Baseline calldata gas |")
print("|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
for row in out["sizes"]:
    c, b = row["claim_proof"], row["baseline"]
    print(f"| {row['receipts']} | {row['setup_ms_single_sample']:,.0f} | {row['native_verify_ms_median']:.3f} | {c['verify_proof_gas']:,} | {c['second_claim_gas']:,} | {b['second_claim_gas']:,} | {c['calldata_bytes']:,} | {b['calldata_bytes']:,} | {b['calldata_gas_included']:,} |")
print()
for row in out["sizes"]:
    print(row["receipts"], "execution-only:", row["claim_proof"]["derived_execution_gas"], row["baseline"]["derived_execution_gas"], row["baseline"]["derived_execution_gas_per_receipt"], "calldata gas claim-proof:", row["claim_proof"]["calldata_gas_included"])
print("rejections claim proof:", out["rejection_tests_passed_claim_proof"])
print("rejections baseline:", out["rejection_tests_passed_baseline"])
print(summary, failed)
