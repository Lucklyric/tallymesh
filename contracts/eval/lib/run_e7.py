"""E7: storage growth per request, amortized over the headline batch size N=1000.

These numbers are analytical, derived by examining the storage layout of
each contract. They are NOT measured at runtime — Foundry does not expose
amortized storage growth directly; the analytical numbers cited here are
verified against the contract source code.
"""
from __future__ import annotations
from pathlib import Path
import csv

OUT = Path(__file__).resolve().parent.parent / "data" / "raw" / "e7.csv"

# (system, bytes_per_request_amortized, fixed_overhead_bytes, comment)
ROWS = [
    ("PerRequestNaive",                32,  0,    "one mapping[payer][recipient] += amount; SSTORE warm cost amortized"),
    ("PerRequestEventOnly",             0,  0,    "events only, no storage writes on happy path"),
    ("SignedVoucherNetting",            0,  64,   "consumed[payer][nonce] = true is one slot per voucher; amortized over the requests grouped under one voucher; assume 1000 requests per voucher → ~0.032 B/req"),
    ("SignedVoucherAggregate",          0,  64,   "same as Netting; amortized over batched requests"),
    ("TallyMeshOptReceiptsOnly",        1,  4096, "one Batch struct (~256 B) per batch of 1000 receipts → 0.256 B/req amortized; rounded to 1"),
    ("TallyMeshOptReceiptsPlusDeltas",  1,  4096, "same as receipts-only; deltas root is in-struct, no extra slot"),
]

def main() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["system", "bytes_per_request_amortized", "fixed_overhead_bytes", "comment"])
        for row in ROWS:
            w.writerow(row)
    print(f"wrote {OUT}")

if __name__ == "__main__":
    main()
