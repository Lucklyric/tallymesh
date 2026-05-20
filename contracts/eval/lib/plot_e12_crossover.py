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
G_OPT_PER_BATCH = 142_500          # submitOptimisticBatch, N-invariant headline gas
G_VERIFY = 263_207                 # submitZkBatch median gas
C_PROVER_USD = 0.0054              # 76.7 s on c3-highmem-4 at $0.27/hr
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

    chains = ["Base", "OP", "Arbitrum"]
    colors = {"Base": "#1f77b4", "OP": "#d62728", "Arbitrum": "#2ca02c"}
    prices = load_gas_prices()
    v_n_array = np.logspace(-1, 6, 500)  # $0.10 .. $1M per batch (crossover lies at ~$2 under archetype τ=900s)

    fig, ax = plt.subplots(figsize=(4.8, 3.4))
    csv_rows = ["chain,gwei,v_n_usd,c_opt_usd,c_zk_usd,crossover_v_n_usd"]
    crossovers: dict[str, float | None] = {}

    for chain in chains:
        gwei = prices[chain]
        opt = compute_curve(v_n_array, gwei, "opt")
        zk = compute_curve(v_n_array, gwei, "zk")
        ax.plot(v_n_array, opt, color=colors[chain], linestyle="-", lw=1.2,
                label=f"opt {chain}")
        ax.plot(v_n_array, zk, color=colors[chain], linestyle="--", lw=1.2,
                label=f"zk {chain}")
        crossover = find_crossover(v_n_array, opt, zk)
        crossovers[chain] = crossover
        if crossover is not None and v_n_array[0] <= crossover <= v_n_array[-1]:
            y_at = cost_usd_per_batch(G_VERIFY, gwei) + C_PROVER_USD
            ax.scatter([crossover], [y_at], marker="*", s=70,
                       color=colors[chain], edgecolor="black", linewidth=0.6, zorder=5)
        for v in v_n_array:
            csv_rows.append(
                f"{chain},{gwei},{v:.6g},"
                f"{compute_curve(np.array([v]), gwei, 'opt')[0]:.8g},"
                f"{compute_curve(np.array([v]), gwei, 'zk')[0]:.8g},"
                f"{crossover if crossover else ''}"
            )

    ax.set_xscale("log")
    ax.set_yscale("log")
    ax.set_xlabel(r"per-batch value at risk $V_N$ (USD)")
    ax.set_ylabel(r"per-batch expected cost (USD)")
    ax.set_title("Optimistic vs. ZK settlement crossover")
    ax.grid(True, which="both", ls=":", lw=0.4, alpha=0.5)
    ax.legend(fontsize=7, ncol=3, loc="lower right", framealpha=0.85)
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
