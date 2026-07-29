# code/contracts/eval/lib/run_e11_archetypes.py
"""E11 archetypes: three worked examples showing how an operator picks an
operating point given their priorities and constraints. Output suitable for
paper §"Pareto frontier" table."""
from __future__ import annotations
import csv
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

ROOT = Path(__file__).resolve().parent.parent
DERIVED = ROOT / "data" / "derived"
SWEEP_IN = DERIVED / "e11_sweep.csv"
OUT = DERIVED / "e11_archetypes.csv"

S_MIN = 1e-2  # paper-default security target


@dataclass(frozen=True)
class Archetype:
    name: str
    priority: str           # "decentralization" | "throughput" | "security"
    f: float
    T_resp: int
    description: str


ARCHETYPES = [
    Archetype("LLMGateway",  "throughput",       0.2, 300,
              "High-volume settlement aggregator; favors throughput once security floor is met"),
    Archetype("OracleNode",  "security",         0.1, 300,
              "Low-volume, high-value receipts; willing to wait long τ for tightest finality"),
    Archetype("DeFiRouter",  "decentralization", 0.1, 300,
              "Public-good infrastructure; maximize Nakamoto coefficient over bonded submitters"),
]


def load_sweep(path: Path) -> list[dict]:
    with path.open() as f:
        return list(csv.DictReader(f))


def pick_for_archetype(rows: list[dict], a: Archetype) -> dict:
    """Filter the sweep to rows matching the archetype's hard constraints,
    then pick the row that maximizes its priority objective."""
    candidates = [
        r for r in rows
        if float(r["f"]) == a.f
        and int(r["T_resp_sec"]) == a.T_resp
        and float(r["S_fail"]) <= S_MIN
    ]
    if not candidates:
        raise RuntimeError(f"no feasible operating point for archetype {a.name}")

    if a.priority == "throughput":
        # Prefer max throughput, breaking ties toward larger N (richer batches).
        candidates.sort(
            key=lambda r: (float(r["throughput_rps"]), int(r["N"])),
            reverse=True,
        )
    elif a.priority == "security":
        # Prefer tightest S_fail; break ties toward smaller N to keep workload
        # bounded (high-value, low-volume operator).
        candidates.sort(key=lambda r: (float(r["S_fail"]), int(r["N"])))
    elif a.priority == "decentralization":
        # Prefer max D_sub, then max throughput, then larger N as a final tiebreak
        # so the public-good archetype lands on a batch size that exercises scale.
        candidates.sort(
            key=lambda r: (int(r["D_sub"]), float(r["throughput_rps"]), int(r["N"])),
            reverse=True,
        )
    else:
        raise ValueError(f"unknown priority {a.priority!r}")

    return candidates[0]


def main() -> None:
    rows = load_sweep(SWEEP_IN)
    DERIVED.mkdir(parents=True, exist_ok=True)
    with OUT.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow([
            "archetype", "priority", "description",
            "tau_sec", "B_eth", "K", "T_resp_sec", "f",
            "N", "dt_sec",
            "D_sub", "throughput_rps", "S_fail",
            "gas_per_call",
            "usd_per_call_base_median", "usd_per_call_op_median", "usd_per_call_arb_median",
        ])
        for a in ARCHETYPES:
            chosen = pick_for_archetype(rows, a)
            w.writerow([
                a.name, a.priority, a.description,
                chosen["tau_sec"], chosen["B_eth"], chosen["K"], chosen["T_resp_sec"], chosen["f"],
                chosen["N"], chosen["dt_sec"],
                chosen["D_sub"], chosen["throughput_rps"], chosen["S_fail"],
                chosen["gas_per_call"],
                chosen["usd_per_call_base_median"], chosen["usd_per_call_op_median"], chosen["usd_per_call_arb_median"],
            ])
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
