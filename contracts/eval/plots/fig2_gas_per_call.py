"""Fig. 2 — gas/call vs batch size headline plot.

Reads eval/data/raw/e5.csv; produces eval/data/figures/fig2_gas_per_call.pdf.

E5 was extended after the Day-8 plan was written to include per-receipt
``claimPayout`` measurements (rows whose ``system`` field ends in ``Claim``).
Those rows describe a different operation (per-receipt user claim, batch
size always 1) and would distort the sweep curves; we therefore skip them
in the curve loop and instead surface the cold per-receipt claim cost as a
single annotated horizontal reference line."""
from __future__ import annotations
import csv
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import matplotlib.pyplot as plt
from style import (
    apply, save,
    DOUBLE_COLUMN_IN, SHORT_HEIGHT_IN,
    SYSTEM_COLORS, SYSTEM_LABELS,
)

ROOT = Path(__file__).resolve().parent.parent
CSV  = ROOT / "data" / "raw" / "e5.csv"
OUT  = ROOT / "data" / "figures" / "fig2_gas_per_call.pdf"

CLAIM_REF_GAS = 67_290  # cold per-receipt claimPayout from TallyMeshOpt*Claim rows
CLAIM_REF_LABEL = "TallyMesh per-receipt claim (cold)"


def main() -> None:
    apply()
    series: dict[str, list[tuple[int, int]]] = defaultdict(list)
    with CSV.open() as f:
        for r in csv.DictReader(f):
            system = r["system"]
            # Skip per-receipt claim rows — they describe a different op,
            # not a batch-size sweep, and would otherwise plot as a single
            # disconnected dot at N=1.
            if system.endswith("Claim"):
                continue
            series[system].append((int(r["batch_size"]), int(r["gas_per_call"])))
    fig, ax = plt.subplots(figsize=(DOUBLE_COLUMN_IN, SHORT_HEIGHT_IN + 0.5))
    for system, pts in series.items():
        pts.sort()
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        ax.loglog(
            xs, ys,
            marker="o", markersize=4,
            color=SYSTEM_COLORS.get(system, "#444"),
            label=SYSTEM_LABELS.get(system, system),
            linewidth=1.4,
        )

    # Annotated reference line for the per-receipt claim cost. Placed after
    # the curves so it sits on top; dashed + grey to read as "context, not a
    # sweep".
    ax.axhline(
        CLAIM_REF_GAS,
        color="#555555",
        linestyle="--",
        linewidth=0.9,
        alpha=0.85,
        zorder=1,
    )
    # Right-anchored label to avoid colliding with the curves.
    ax.text(
        0.985, CLAIM_REF_GAS,
        f" {CLAIM_REF_LABEL} ({CLAIM_REF_GAS:,} gas)",
        transform=ax.get_yaxis_transform(),
        ha="right", va="bottom",
        fontsize=7, color="#333333",
    )

    ax.set_xlabel("Batch size $N$")
    ax.set_ylabel("On-chain gas per receipt (commitment publication;\n claim measured separately)")
    ax.set_title("")
    ax.grid(True, which="both", linewidth=0.4, alpha=0.4)
    ax.legend(loc="lower left", frameon=False, ncols=2)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    save(fig, str(OUT))


if __name__ == "__main__":
    main()
