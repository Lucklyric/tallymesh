# code/contracts/eval/lib/run_e11_sweep.py
"""E11: Trilemma sweep over design parameters at default N=1000.

Reads E5 gas/call data and produces a CSV with one row per (τ, B, K, T_resp, f)
combination including computed (D_sub, T, S_fail, gas, USD/call across rollup
× snapshot)."""
from __future__ import annotations
import csv
import sys
from itertools import product
from pathlib import Path

# Make sibling-module imports work when invoked as `uv run eval/lib/run_e11_sweep.py`.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from trilemma import (
    nakamoto_coefficient,
    throughput,
    security_failure_prob,
)
from l1_l2_cost import GAS_PRICE_SNAPSHOTS_GWEI, ETH_USD, usd_per_call

ROOT = Path(__file__).resolve().parent.parent
RAW  = ROOT / "data" / "raw"
DERIVED = ROOT / "data" / "derived"
OUT  = DERIVED / "e11_sweep.csv"

# Frozen sweep ranges (from experimental-design.md §"Frozen decisions").
TAU_VALUES   = [60, 900, 3600]
B_VALUES     = [0.5, 2.0, 10.0]
K_VALUES     = [3, 5, 21]
T_RESP_VALUES = [60, 300, 900]
F_VALUES     = [0.1, 0.2, 0.33]

# Headline defaults (same source).
N_DEFAULT = 1000
DT_DEFAULT_SEC = 60.0


def load_e5_gas_per_call(system: str = "TallyMeshOptReceiptsOnly", batch_size: int = N_DEFAULT) -> int:
    """Pull the per-call gas for `system` at `batch_size` from data/raw/e5.csv."""
    with (RAW / "e5.csv").open() as f:
        for r in csv.DictReader(f):
            if r["system"] == system and int(r["batch_size"]) == batch_size:
                return int(r["gas_per_call"])
    raise KeyError(f"e5.csv missing row for system={system}, batch_size={batch_size}")


def equal_bonds(K: int, B: float) -> list[float]:
    return [B] * K


def main() -> None:
    DERIVED.mkdir(parents=True, exist_ok=True)
    gas_per_call = load_e5_gas_per_call()

    with OUT.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow([
            "tau_sec", "B_eth", "K", "T_resp_sec", "f",
            "N", "dt_sec",
            "D_sub", "throughput_rps", "S_fail",
            "gas_per_call",
            "usd_per_call_base_low", "usd_per_call_op_low", "usd_per_call_arb_low",
            "usd_per_call_base_median", "usd_per_call_op_median", "usd_per_call_arb_median",
            "usd_per_call_base_high", "usd_per_call_op_high", "usd_per_call_arb_high",
            "feasible",
        ])

        for tau, B, K, Tr, f in product(TAU_VALUES, B_VALUES, K_VALUES, T_RESP_VALUES, F_VALUES):
            D = nakamoto_coefficient(equal_bonds(K, B))
            tput = throughput(K, N_DEFAULT, DT_DEFAULT_SEC)
            sfail = security_failure_prob(f, tau, Tr)
            row = [tau, B, K, Tr, f, N_DEFAULT, DT_DEFAULT_SEC, D, tput, sfail, gas_per_call]
            for snapshot in ["low", "median", "high"]:
                for rollup in ["Base", "OP", "Arbitrum"]:
                    row.append(usd_per_call(gas_per_call, rollup, snapshot))
            # Feasibility flag: passes the paper's S_min ≤ 1e-2 default.
            row.append("yes" if sfail <= 1e-2 else "no")
            w.writerow(row)

    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
