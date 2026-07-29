# TallyMesh evaluation harness

All eval scripts emit raw CSVs to `data/raw/` and derived JSON/CSV to `data/derived/`. Plots and paper tables are generated from these files; we do NOT recompute measurements at plot time.

## Running

```bash
export PATH="$HOME/.foundry/bin:$PATH"

# E4: per-function gas
forge script eval/scripts/E4_PerFunctionGas.s.sol --ffi
# E5: gas/call vs batch size (headline)
forge script eval/scripts/E5_BatchSizeSweep.s.sol --ffi
# E6: dispute roundtrip
forge script eval/scripts/E6_DisputeCost.s.sol --ffi
# E7: storage growth
forge script eval/scripts/E7_StorageGrowth.s.sol --ffi
# E10: gas-price sensitivity (Python post-processing of E4 + E5)
uv run eval/lib/run_e10.py
```

## Outputs

- `data/raw/e4.csv` — system, function, gas
- `data/raw/e5.csv` — system, batch_size, gas_per_call, total_gas
- `data/raw/e6.csv` — phase, gas, latency_blocks
- `data/raw/e7.csv` — system, bytes_per_request_amortized, fixed_overhead_bytes
- `data/derived/e10.json` — per-system, per-rollup, per-snapshot USD/call

## Cost model

`lib/l1_l2_cost.py` documents the gas-price snapshots and ETH/USD assumptions used in E10.
