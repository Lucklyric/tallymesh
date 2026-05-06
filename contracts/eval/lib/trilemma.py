"""TallyMesh trilemma math model.

Implements the equations in paper-sections/scaling-analysis.md:

  D_sub          = Nakamoto coefficient over bonded batch submitters (50% threshold)
  T(N, dt, K)    = K * N / dt           # settlement-capacity throughput, req/s
  S_fail(τ, T_resp, f) = f * exp(-τ / T_resp)
  τ_min(T_resp, f, S_min) = T_resp * ln(f / S_min)
  T_max(H, h0, h1, D)  = (H - (2D-1) * h0) / h1
  N_max(B, gamma, V_N) = B / (gamma * V_N)

Plus the per-partner cost decision rule from §"Hybrid Optimistic / ZK":

  C_opt(N) = p_g * G_opt(N) + C_bond(B, τ) + ρ * V_N * f * exp(-τ/T_resp)
  C_zk(N)  = p_g * G_verify(N) + c_prover(N) + ρ * V_N * ε_zk

  pick ZK iff C_zk(N) ≤ C_opt(N)
"""
from __future__ import annotations
from dataclasses import dataclass
from math import exp, log


# ------- Decentralization -------

def nakamoto_coefficient(bonds: list[float], threshold: float = 0.5) -> int:
    """Number of largest stakeholders needed to cross the threshold share of total stake."""
    if not bonds:
        return 0
    sorted_bonds = sorted(bonds, reverse=True)
    total = sum(sorted_bonds)
    if total <= 0:
        return 0
    cum = 0.0
    for i, b in enumerate(sorted_bonds, start=1):
        cum += b
        if cum / total >= threshold:
            return i
    return len(sorted_bonds)


# ------- Throughput -------

def throughput(K: int, N: int, dt_sec: float) -> float:
    """Sustained settlement-capacity throughput in requests per second."""
    return (K * N) / dt_sec


# ------- Security -------

def security_failure_prob(f: float, tau_sec: float, T_resp_sec: float) -> float:
    """Probability that a fraudulent batch finalizes (one-honest-watcher model)."""
    return f * exp(-tau_sec / T_resp_sec)


def tau_min_for_security(T_resp_sec: float, f: float, S_min: float) -> float:
    """Minimum challenge window achieving S_fail ≤ S_min, given f and T_resp."""
    if S_min <= 0 or f <= 0:
        raise ValueError("f and S_min must be positive")
    if S_min >= f:
        return 0.0
    return T_resp_sec * log(f / S_min)


# ------- Tradeoff theorem -------

def throughput_max_at_decentralization(
    H: float, h0: float, h1: float, D: int
) -> float:
    """Maximum throughput x = N/dt achievable by D distinct submitters under
    fixed total hardware budget H, with K = 2D - 1 minimum submitters."""
    K = 2 * D - 1
    avail = H - K * h0
    if avail <= 0 or h1 <= 0:
        return 0.0
    return avail / h1


def batch_size_max_for_bond(B: float, gamma: float, V_N: float) -> float:
    """Upper bound on N from the per-batch-value-at-risk bond constraint."""
    if gamma <= 0 or V_N <= 0:
        return float("inf")
    return B / (gamma * V_N)


# ------- Per-partner cost decision rule -------

@dataclass(frozen=True)
class CostInputs:
    N: int                # batch size
    p_g_wei_per_gas: int  # gas price in wei
    G_opt_per_batch: int  # gas for submitOptimisticBatch
    G_verify: int         # gas for submitZkBatch verifier call
    B_eth: float          # bond size locked over the challenge window
    tau_sec: float
    T_resp_sec: float
    f: float              # subjective fraud probability for this submitter
    rho: float            # risk-aversion multiplier
    V_N_wei: float        # batch value at risk
    eps_zk: float         # ZK proof-system soundness error
    bond_opportunity_rate_per_sec: float  # opportunity cost rate for locked bond
    c_prover_per_call_wei: float          # off-chain prover cost amortized per call


def opportunity_cost_bond(B_eth: float, tau_sec: float, rate_per_sec: float) -> float:
    """Opportunity cost of locking B for τ seconds, in ETH-equivalent."""
    return B_eth * rate_per_sec * tau_sec


def cost_optimistic(c: CostInputs) -> float:
    """Per-batch expected cost under the optimistic settlement path, in wei."""
    gas_cost = c.p_g_wei_per_gas * c.G_opt_per_batch
    bond_cost_wei = opportunity_cost_bond(c.B_eth, c.tau_sec, c.bond_opportunity_rate_per_sec) * 1e18
    risk = c.rho * c.V_N_wei * c.f * exp(-c.tau_sec / c.T_resp_sec)
    return gas_cost + bond_cost_wei + risk


def cost_zk(c: CostInputs) -> float:
    """Per-batch expected cost under the validity-proof settlement path, in wei."""
    gas_cost = c.p_g_wei_per_gas * c.G_verify
    risk = c.rho * c.V_N_wei * c.eps_zk
    return gas_cost + c.c_prover_per_call_wei * c.N + risk


def pick_settlement_mode(c: CostInputs) -> str:
    """Returns 'zk' if validity-proof is cheaper, else 'optimistic'."""
    return "zk" if cost_zk(c) <= cost_optimistic(c) else "optimistic"
