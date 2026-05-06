# eval/tables/tab1_gas_usd.py
"""Tab. 1 — Per-function gas + analytical USD across 3 rollups x 1 snapshot
(median snapshot for the table; full sweep lives in e10.json).

The 6 main rows come from e4.csv joined against e10.json's median snapshot.
Two extra rows describe the per-receipt ``claimPayout`` cost surfaced after
the Day-8 plan was written: those rows live in e5.csv tagged
``TallyMeshOpt*Claim`` with ``batch_size=1``. We compute their USD figures
inline using e10's gwei snapshots so the table stays self-contained."""
from __future__ import annotations
import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW  = ROOT / "data" / "raw"
DERIVED = ROOT / "data" / "derived"
OUT_DIR = ROOT / "data" / "tables"


def _short(system: str) -> str:
    return (system
            .replace("TallyMeshOpt", "TM-")
            .replace("PerRequest", "PR-")
            .replace("SignedVoucher", "SV-"))


def _claim_rows(e10: dict) -> list[dict]:
    """Pull the two TallyMeshOpt*Claim rows from e5.csv and synthesize USD
    figures via the median gwei snapshot in e10.json."""
    eth_usd = float(e10["eth_usd"])
    median = e10["snapshots"]["median"]
    out: list[dict] = []
    with (RAW / "e5.csv").open() as f:
        for r in csv.DictReader(f):
            system = r["system"]
            if not system.endswith("Claim"):
                continue
            if int(r["batch_size"]) != 1:
                continue
            gas = int(r["gas_per_call"])
            usd = {
                rollup: gas * gwei * 1e-9 * eth_usd
                for rollup, gwei in median.items()
            }
            out.append({
                "system": system,
                "function": "claimPayout",
                "gas": gas,
                "usd_base": usd["Base"],
                "usd_op": usd["OP"],
                "usd_arb": usd["Arbitrum"],
                "is_claim": True,
            })
    return out


def main() -> None:
    e4 = list(csv.DictReader((RAW / "e4.csv").open()))
    e10 = json.loads((DERIVED / "e10.json").read_text())

    # Index e10 by (system, function, rollup, snapshot).
    idx: dict[tuple[str, str, str, str], float] = {}
    for entry in e10["e4_per_function"]:
        idx[(entry["system"], entry["function"], entry["rollup"], entry["snapshot"])] = entry["usd_per_unit"]

    rows: list[dict] = []
    for r in e4:
        system = r["system"]
        fn = r["function"]
        gas = int(r["gas"])
        rows.append({
            "system": system, "function": fn, "gas": gas,
            "usd_base":  idx.get((system, fn, "Base",     "median"), 0.0),
            "usd_op":    idx.get((system, fn, "OP",       "median"), 0.0),
            "usd_arb":   idx.get((system, fn, "Arbitrum", "median"), 0.0),
            "is_claim":  False,
        })
    rows.extend(_claim_rows(e10))

    # Write CSV (traceability).
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    with (OUT_DIR / "tab1_gas_usd.csv").open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["system", "function", "gas", "usd_base_median", "usd_op_median", "usd_arb_median"])
        for r in rows:
            w.writerow([r["system"], r["function"], r["gas"],
                        f"{r['usd_base']:.6f}", f"{r['usd_op']:.6f}", f"{r['usd_arb']:.6f}"])

    # Write LaTeX fragment.
    lines = [
        r"\begin{table}[t]",
        r"\centering",
        r"\caption{Per-function single-call gas (no batching: $N{=}1$) plus analytical USD per call at the median gas-price snapshot across three L2 rollups. Per-batch amortization for the headline $N{=}1000$ point is in Fig.~\ref{fig:gas_per_call} and the §Gas and Cost prose. The last two rows are the per-receipt \texttt{claimPayout} cost (cold-recipient case, single transfer) charged separately from commitment publication.}",
        r"\label{tab:gas_usd}",
        r"\begin{tabular}{lrrrr}",
        r"\hline",
        r"System & Gas & USD (Base) & USD (OP) & USD (Arb) \\",
        r"\hline",
    ]
    inserted_separator = False
    for r in rows:
        if r["is_claim"] and not inserted_separator:
            lines.append(r"\hline")
            inserted_separator = True
        # Truncate system names for table width, with explicit "(claim)" tag for claim rows.
        if r["is_claim"]:
            base = _short(r["system"].removesuffix("Claim"))
            sys_short = f"{base} (claim)"
        else:
            sys_short = _short(r["system"])
        lines.append(
            f"{sys_short} & {r['gas']:,} & ${r['usd_base']:.5f}$ & ${r['usd_op']:.5f}$ & ${r['usd_arb']:.5f}$ \\\\"
        )
    lines += [r"\hline", r"\end{tabular}", r"\end{table}"]
    (OUT_DIR / "tab1_gas_usd.tex").write_text("\n".join(lines) + "\n")
    print(f"wrote {OUT_DIR / 'tab1_gas_usd.tex'}")


if __name__ == "__main__":
    main()
