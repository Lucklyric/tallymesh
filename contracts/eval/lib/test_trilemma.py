"""Unit tests anchored against the worked examples in
paper-sections/scaling-analysis.md §"Pareto frontier"."""
from __future__ import annotations
import math
import pytest

from trilemma import (
    nakamoto_coefficient,
    throughput,
    security_failure_prob,
    tau_min_for_security,
    throughput_max_at_decentralization,
    pick_settlement_mode,
    cost_optimistic,
    cost_zk,
    CostInputs,
)


def test_nakamoto_equal_bonds():
    assert nakamoto_coefficient([10, 10, 10, 10, 10]) == 3  # need 3 of 5 ≥ 50%

def test_nakamoto_concentrated():
    assert nakamoto_coefficient([100, 1, 1, 1, 1]) == 1  # one entity > 50%

def test_nakamoto_empty():
    assert nakamoto_coefficient([]) == 0

def test_throughput_security_first():
    # paper §Pareto: N=100, dt=60, K=5 → T ≈ 8.3 req/s
    assert throughput(5, 100, 60.0) == pytest.approx(500 / 60, rel=1e-9)

def test_throughput_throughput_first():
    # paper §Pareto: N=5000, dt=10, K=3 → T = 1500 req/s
    assert throughput(3, 5000, 10.0) == 1500.0

def test_throughput_decentralization_first():
    # paper §Pareto: N=1000, dt=60, K=21 → T = 350 req/s
    assert throughput(21, 1000, 60.0) == pytest.approx(21_000 / 60, rel=1e-9)

def test_security_security_first():
    # paper §Pareto: f=0.2, τ=3600, T_resp=300 → S_fail ≈ 1.2e-6
    s = security_failure_prob(0.2, 3600.0, 300.0)
    assert s == pytest.approx(0.2 * math.exp(-12), rel=1e-9)
    assert s < 1.5e-6 and s > 1.0e-6

def test_security_throughput_first():
    # paper §Pareto: f=0.33, τ=60, T_resp=300 → S_fail ≈ 0.27
    s = security_failure_prob(0.33, 60.0, 300.0)
    assert 0.26 < s < 0.28

def test_security_decentralization_first():
    # paper §Pareto: f=0.1, τ=900, T_resp=300 → S_fail ≈ 5.0e-3
    s = security_failure_prob(0.1, 900.0, 300.0)
    assert 4e-3 < s < 6e-3

def test_tau_min_decentralization_first():
    # paper headline: τ ≥ T_resp · ln(f/S_min) for f=0.1, T_resp=300, S_min=1e-2
    # → τ_min = 300 · ln(10) ≈ 691
    tau = tau_min_for_security(300.0, 0.1, 1e-2)
    assert 690.0 < tau < 692.0

def test_tau_min_already_satisfied_returns_zero():
    # If S_min > f, we don't need any waiting time.
    assert tau_min_for_security(300.0, 0.1, 0.5) == 0.0

def test_throughput_max_with_decentralization_pressure():
    # H = 1000, h0 = 50, h1 = 0.01, D = 11 → K = 21 → x_max = (1000 - 21*50) / 0.01 = -50_000 → 0
    assert throughput_max_at_decentralization(1000, 50, 0.01, 11) == 0.0
    # H = 5000, h0 = 50, h1 = 0.01, D = 11 → x_max = (5000 - 1050) / 0.01 = 395_000
    assert throughput_max_at_decentralization(5000, 50, 0.01, 11) == 395_000.0

def test_pick_mode_zk_favored_at_high_volume():
    # With low bond opportunity, low f, high V_N, ZK should win at scale.
    inputs = CostInputs(
        N=1000,
        p_g_wei_per_gas=10**9,            # 1 gwei
        G_opt_per_batch=142_164,           # E4 measurement
        G_verify=217_000,                  # ZK verifier
        B_eth=2.0,
        tau_sec=900.0,
        T_resp_sec=300.0,
        f=0.1,
        rho=10.0,
        V_N_wei=int(1e18 * 100),           # 100 ETH at risk per batch
        eps_zk=2**-128,
        bond_opportunity_rate_per_sec=2.0e-9,  # ~6% APY
        c_prover_per_call_wei=int(1e14),       # 0.0001 ETH per receipt
    )
    assert pick_settlement_mode(inputs) == "zk"

def test_pick_mode_opt_favored_at_low_volume():
    # Small N, low V_N, slow prover → optimistic wins
    inputs = CostInputs(
        N=10,
        p_g_wei_per_gas=10**9,
        G_opt_per_batch=142_164,
        G_verify=217_000,
        B_eth=0.5,
        tau_sec=900.0,
        T_resp_sec=300.0,
        f=0.1,
        rho=1.0,
        V_N_wei=int(1e16),
        eps_zk=2**-128,
        bond_opportunity_rate_per_sec=2.0e-9,
        c_prover_per_call_wei=int(1e15),       # 10x slower prover
    )
    assert pick_settlement_mode(inputs) == "optimistic"
