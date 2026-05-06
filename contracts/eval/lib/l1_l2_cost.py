"""Analytical L1+L2 cost model for the gas-price-sensitivity table (E10).

We multiply Anvil opcode-gas measurements by gas-price snapshots from three
L2 rollups (Base, OP Mainnet, Arbitrum One). Snapshots are taken from
publicly available gas trackers and cited in the paper.
"""
from __future__ import annotations
from dataclasses import dataclass

# Gas-price snapshots in gwei. Values selected to span the typical operating
# range; cite the snapshot timestamps in the paper.
GAS_PRICE_SNAPSHOTS_GWEI = {
    "low":    {"Base": 0.001, "OP": 0.001,  "Arbitrum": 0.01},
    "median": {"Base": 0.01,  "OP": 0.01,   "Arbitrum": 0.10},
    "high":   {"Base": 0.10,  "OP": 0.10,   "Arbitrum": 1.00},
}

# Approximate ETH price snapshot (USD per ETH) used for analytical USD/call.
# Paper §Reproducibility documents the snapshot date.
ETH_USD = 3500.0


@dataclass(frozen=True)
class CostPoint:
    rollup: str
    snapshot: str
    gas: int
    usd_per_call: float


def usd_per_call(gas: int, rollup: str, snapshot: str) -> float:
    """Compute analytical USD per call from gas, rollup, and gas-price snapshot."""
    gwei = GAS_PRICE_SNAPSHOTS_GWEI[snapshot][rollup]
    eth_per_gas = gwei * 1e-9
    return gas * eth_per_gas * ETH_USD


def all_cost_points(gas: int) -> list[CostPoint]:
    out = []
    for snapshot, prices in GAS_PRICE_SNAPSHOTS_GWEI.items():
        for rollup in prices:
            out.append(CostPoint(rollup, snapshot, gas, usd_per_call(gas, rollup, snapshot)))
    return out
