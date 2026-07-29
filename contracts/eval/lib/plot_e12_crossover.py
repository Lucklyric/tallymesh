"""Fig. 4 generator — optimistic-vs-ZK cost crossover.

Sweeps per-batch value-at-risk V_N for three L2 gas-price regimes (Base, OP,
Arbitrum) at the median snapshot from e10.json, plugging the measured
G_opt, G_verify, and prover-cost numbers into the per-batch decision rule:

  C_opt(V_N) = p_g * G_opt + ρ * V_N * f * exp(-τ/T_resp)
  C_zk(V_N)  = p_g * G_verify + c_prover + ρ * V_N * ε_zk

The crossover happens where rising V_N makes the optimistic watcher-arrival
risk term dominate ZK's fixed verifier+prover cost.

Outputs: paper-draft/figures/fig4_crossover.pdf + a CSV side-car for repro.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
# Embed TrueType (Type 42) fonts in PDF output to satisfy IEEE PDF eXpress
# (default Type 3 bitmap fonts are rejected by the IEEE compliance tools).
matplotlib.rcParams["pdf.fonttype"] = 42
matplotlib.rcParams["ps.fonttype"] = 42
# Match the paper body font (Times-flavored) rather than Matplotlib's DejaVu default.
matplotlib.rcParams["font.family"] = "serif"
matplotlib.rcParams["font.serif"] = [
    "Times",
    "Nimbus Roman",
    "TeX Gyre Termes",
    "DejaVu Serif",
]
matplotlib.rcParams["mathtext.fontset"] = "stix"
import matplotlib.pyplot as plt
import numpy as np


# ------- repo paths -------
HERE = Path(__file__).resolve().parent
EVAL_ROOT = HERE.parent
DEAUTH_ROOT = EVAL_ROOT.parent.parent.parent  # up to DeAuth/
PAPER_FIG_DIR = DEAUTH_ROOT / "paper-draft" / "figures"
OUTPUT_PDF = PAPER_FIG_DIR / "fig4_crossover.pdf"
OUTPUT_CSV = EVAL_ROOT / "data" / "derived" / "e12_crossover.csv"


# ------- measured constants -------
G_OPT_PER_BATCH = 142_530          # submitOptimisticBatch, N=1 batch-sweep measurement from e5.csv
G_VERIFY = 263_207                 # submitZkBatch median gas
C_PROVER_USD = 0.0054              # 76.7 s on c3-highmem-4 at ~$0.25/hr effective
# Use the archetype-table operating point (tau in {900, 3600} s, T_resp = 300 s).
# Production 7-day windows zero out the watcher term in floating point and hide
# the crossover; the archetype windows are the operationally relevant regime.
TAU_SEC = 900.0                    # 15-min watcher arrival window (matches LLMGateway archetype)
T_RESP_SEC = 300                   # mean watcher arrival time (5 min)
FRAUD_RATE = 0.2                   # LLMGateway archetype f=0.2 (Tab.V); DeFiRouter uses 0.1
EPS_ZK = 2 ** -80                  # Groth16 soundness error (negligibly small)
RHO = 1.0                          # no risk-aversion multiplier
ETH_USD = 3500.0


def load_gas_prices() -> dict[str, float]:
    """Return median gas prices (gwei) per chain from e10.json."""
    path = EVAL_ROOT / "data" / "derived" / "e10.json"
    with path.open() as f:
        e10 = json.load(f)
    return e10["snapshots"]["median"]


def cost_usd_per_batch(gas_amount: int, gwei: float) -> float:
    """Convert (gas, gwei) -> USD using ETH/USD baseline."""
    eth = gas_amount * gwei * 1e-9
    return eth * ETH_USD


def watcher_term_usd(v_n_usd: float) -> float:
    """Optimistic-mode expected loss term in USD."""
    return RHO * v_n_usd * FRAUD_RATE * np.exp(-TAU_SEC / T_RESP_SEC)


def zk_residual_term_usd(v_n_usd: float) -> float:
    """ZK-mode residual cryptographic-error loss term in USD (typically negligible)."""
    return RHO * v_n_usd * EPS_ZK


def compute_curve(v_n_array: np.ndarray, gwei: float, mode: str) -> np.ndarray:
    if mode == "opt":
        gas_usd = cost_usd_per_batch(G_OPT_PER_BATCH, gwei)
        return gas_usd + watcher_term_usd(v_n_array)
    else:  # "zk"
        gas_usd = cost_usd_per_batch(G_VERIFY, gwei)
        return gas_usd + C_PROVER_USD + zk_residual_term_usd(v_n_array)


def find_crossover(v_n_array: np.ndarray, opt: np.ndarray, zk: np.ndarray) -> float | None:
    """Return V_N at which opt and zk curves intersect (None if no crossover in range)."""
    diff = opt - zk
    sign_changes = np.where(np.diff(np.sign(diff)) != 0)[0]
    if len(sign_changes) == 0:
        return None
    i = sign_changes[0]
    # linear interp in log space
    x1, x2 = np.log10(v_n_array[i]), np.log10(v_n_array[i + 1])
    y1, y2 = diff[i], diff[i + 1]
    if y2 == y1:
        return float(v_n_array[i])
    x_cross = x1 - y1 * (x2 - x1) / (y2 - y1)
    return float(10 ** x_cross)


def main() -> None:
    PAPER_FIG_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUT_CSV.parent.mkdir(parents=True, exist_ok=True)

    # Base and OP share the same gas-price snapshot, so their curves are
    # numerically identical. We render a single "Base/Optimism" curve pair and a
    # separate "Arbitrum" pair, giving 4 visually distinct elements instead
    # of 6 redundant ones.
    chain_groups = [
        ("Base/Optimism", "Base", "#1f77b4"),    # blue (same gwei as OP)
        ("Arbitrum", "Arbitrum", "#9467bd"),  # purple
    ]
    prices = load_gas_prices()
    # Tighter axes focus on the operational range; the linear far-tail above
    # 10^4 USD is operationally irrelevant.
    v_n_array = np.logspace(-1, 4, 500)  # $0.10 .. $10k per batch

    fig, ax = plt.subplots(figsize=(4.8, 3.4))
    csv_rows = ["chain,gwei,v_n_usd,c_opt_usd,c_zk_usd,crossover_v_n_usd"]
    crossovers: dict[str, float | None] = {}

    # CSV rows still cover all three chains for downstream consumers.
    for chain in ["Base", "OP", "Arbitrum"]:
        gwei = prices[chain]
        for v in v_n_array:
            opt_v = compute_curve(np.array([v]), gwei, "opt")[0]
            zk_v = compute_curve(np.array([v]), gwei, "zk")[0]
            csv_rows.append(f"{chain},{gwei},{v:.6g},{opt_v:.8g},{zk_v:.8g},")

    for label, chain_key, color in chain_groups:
        gwei = prices[chain_key]
        opt = compute_curve(v_n_array, gwei, "opt")
        zk = compute_curve(v_n_array, gwei, "zk")
        ax.plot(v_n_array, opt, color=color, linestyle="-", lw=1.8,
                label=f"{label} optimistic", zorder=3)
        ax.plot(v_n_array, zk, color=color, linestyle="--", lw=1.8,
                label=f"{label} ZK admission", zorder=3)
        crossover = find_crossover(v_n_array, opt, zk)
        crossovers[label] = crossover
        if crossover is not None and v_n_array[0] <= crossover <= v_n_array[-1]:
            y_at = cost_usd_per_batch(G_VERIFY, gwei) + C_PROVER_USD
            ax.scatter([crossover], [y_at], marker="*", s=180,
                       color=color, edgecolor="black", linewidth=0.9, zorder=6)
            # Callouts placed to the right of each star into the gray ZK-cheaper
            # region, with vertical offsets staggered so the two labels do not
            # collide and neither overlaps the y-axis label or the curves.
            xytext = (62, -18) if label == "Base/Optimism" else (62, 24)
            ax.annotate(rf"{label}: $V_N\!=\!\${crossover:.2f}$",
                        xy=(crossover, y_at), xytext=xytext,
                        textcoords="offset points",
                        fontsize=7.5, color="black", zorder=7, ha="left",
                        bbox=dict(boxstyle="round,pad=0.25", fc="white",
                                  ec=color, lw=0.9, alpha=0.95),
                        arrowprops=dict(arrowstyle="->", color=color,
                                        lw=0.8, shrinkA=3, shrinkB=4))

    ax.set_xscale("log")
    ax.set_yscale("log")
    ax.set_xlim(1e-1, 1e4)
    ax.set_ylim(1e-3, 1e2)
    ax.set_xlabel(r"per-batch value-at-risk $V_N$ (USD)")
    ax.set_ylabel(r"per-batch admission-phase cost (USD)")
    # Title intentionally omitted; the LaTeX figure caption carries the same
    # parameter declaration (LLMGateway: tau=900s, f=0.2).
    # Major-only grid keeps the plot uncluttered against the log scale.
    ax.grid(True, which="major", ls=":", lw=0.5, alpha=0.55)
    ax.grid(True, which="minor", ls=":", lw=0.3, alpha=0.18)
    # Shade the ZK-favored region (above the maximum crossover) lightly so the
    # reader can read mode preference at a glance.
    max_xover = max(c for c in crossovers.values() if c is not None)
    ax.axvspan(max_xover, 1e4, color="gray", alpha=0.05, zorder=1)
    ax.text(0.98, 0.96, "ZK admission cheaper",
            transform=ax.transAxes, fontsize=7, color="gray", style="italic",
            ha="right", va="top", zorder=4)
    ax.text(0.02, 0.04, "Optimistic cheaper",
            transform=ax.transAxes, fontsize=7, color="gray", style="italic",
            ha="left", va="bottom", zorder=4)
    # Two-column legend below the plot.
    ax.legend(fontsize=7.5, ncol=2, loc="upper center",
              bbox_to_anchor=(0.5, -0.18), framealpha=0.95,
              handlelength=2.4, columnspacing=1.4)
    plt.tight_layout()
    fig.savefig(OUTPUT_PDF, format="pdf", bbox_inches="tight")
    plt.close(fig)

    with OUTPUT_CSV.open("w") as f:
        f.write("\n".join(csv_rows))

    print(f"Wrote {OUTPUT_PDF}")
    print(f"Wrote {OUTPUT_CSV}")
    print(f"Crossovers (USD V_N): {crossovers}")


if __name__ == "__main__":
    sys.exit(main())
