"""Fig. 3 — Trilemma frontier scatter. x=D_sub, y=throughput_rps (log),
color=S_fail (log)."""
from __future__ import annotations
import csv
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import matplotlib.pyplot as plt
from matplotlib.colors import LogNorm
from style import apply, save, DOUBLE_COLUMN_IN, TALL_HEIGHT_IN

ROOT = Path(__file__).resolve().parent.parent
SWEEP = ROOT / "data" / "derived" / "e11_sweep.csv"
ARCH  = ROOT / "data" / "derived" / "e11_archetypes.csv"
OUT   = ROOT / "data" / "figures" / "fig3_trilemma_frontier.pdf"

S_MIN_FLOOR = 1e-12  # for log-scale colorbar; clamp values below this


def main() -> None:
    apply()
    # Seeded jitter: D_sub and throughput live on a coarse grid (3 K × 3 N = 9
    # discrete (x,y) positions in the current sweep), so without a small
    # perturbation the 729 points pile into 9 stacks that hide the S_fail
    # gradient. Jitter is for visual readability only; archetype markers below
    # are drawn from the unjittered archetype CSV.
    rng = random.Random(0xE11)
    xs, ys, cs = [], [], []
    with SWEEP.open() as f:
        for r in csv.DictReader(f):
            x = int(r["D_sub"]) + rng.uniform(-0.18, 0.18)
            y = float(r["throughput_rps"]) * (1.0 + rng.uniform(-0.08, 0.08))
            xs.append(x)
            ys.append(y)
            cs.append(max(float(r["S_fail"]), S_MIN_FLOOR))

    fig, ax = plt.subplots(figsize=(DOUBLE_COLUMN_IN, TALL_HEIGHT_IN))
    sc = ax.scatter(xs, ys, c=cs, cmap="viridis_r", norm=LogNorm(vmin=1e-8, vmax=1.0),
                    s=6, alpha=0.75, edgecolors="none")
    ax.set_yscale("log")
    ax.set_xlabel("Decentralization $D_{\\mathrm{sub}}$ (Nakamoto coefficient)")
    ax.set_ylabel("Throughput $T$ (requests/sec)")
    cbar = fig.colorbar(sc, ax=ax, pad=0.02)
    cbar.set_label("Security failure $S_{\\mathrm{fail}}$")

    # Annotate the three archetypes. LLMGateway and DeFiRouter resolve to the
    # same (D_sub, T) point (same K and N, different f), so steer their labels
    # to opposite sides to avoid overprint.
    archetype_offsets = {
        "LLMGateway": (-78, 10),
        "OracleNode": (10, 8),
        "DeFiRouter": (-78, -14),
    }
    arch_xy = []
    with ARCH.open() as f:
        for r in csv.DictReader(f):
            arch_xy.append((r["archetype"], int(r["D_sub"]), float(r["throughput_rps"])))
    for name, x, y in arch_xy:
        ax.annotate(
            name, (x, y),
            xytext=archetype_offsets.get(name, (8, 6)),
            textcoords="offset points",
            fontsize=8,
            arrowprops={"arrowstyle": "-", "linewidth": 0.6, "color": "black"},
        )
        ax.scatter([x], [y], s=60, facecolors="none", edgecolors="black", linewidth=1.2, zorder=5)

    ax.grid(True, which="both", linewidth=0.4, alpha=0.4)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    save(fig, str(OUT))


if __name__ == "__main__":
    main()
