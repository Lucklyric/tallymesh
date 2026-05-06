"""E10: gas-price sensitivity post-processor.

Reads e4.csv (per-function gas) and e5.csv (gas/call vs batch size); produces
e10.json with USD/call across 3 rollups x 3 gas-price snapshots for each
measurement. Pure analytical, no chain calls.
"""
from __future__ import annotations
import sys
from pathlib import Path
import csv
import json

sys.path.insert(0, str(Path(__file__).resolve().parent))
from l1_l2_cost import GAS_PRICE_SNAPSHOTS_GWEI, ETH_USD, usd_per_call

ROOT = Path(__file__).resolve().parent.parent
RAW  = ROOT / "data" / "raw"
OUT  = ROOT / "data" / "derived" / "e10.json"


def load_e4() -> list[dict]:
    rows = []
    with (RAW / "e4.csv").open() as f:
        for r in csv.DictReader(f):
            rows.append({"system": r["system"], "function": r["function"], "gas": int(r["gas"])})
    return rows


def load_e5() -> list[dict]:
    rows = []
    with (RAW / "e5.csv").open() as f:
        for r in csv.DictReader(f):
            rows.append({
                "system": r["system"],
                "batch_size": int(r["batch_size"]),
                "gas_per_call": int(r["gas_per_call"]),
            })
    return rows


def expand(measurements: list[dict], gas_key: str) -> list[dict]:
    out = []
    for m in measurements:
        for snapshot, prices in GAS_PRICE_SNAPSHOTS_GWEI.items():
            for rollup in prices:
                out.append({
                    **m,
                    "rollup": rollup,
                    "snapshot": snapshot,
                    "usd_per_unit": usd_per_call(m[gas_key], rollup, snapshot),
                })
    return out


def main() -> None:
    e4 = load_e4()
    e5 = load_e5()
    payload = {
        "eth_usd": ETH_USD,
        "snapshots": GAS_PRICE_SNAPSHOTS_GWEI,
        "e4_per_function": expand(e4, "gas"),
        "e5_gas_per_call": expand(e5, "gas_per_call"),
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(payload, indent=2))
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
