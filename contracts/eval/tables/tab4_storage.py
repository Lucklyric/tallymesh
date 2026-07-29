# eval/tables/tab4_storage.py
"""Tab. 4 — Storage growth from e7.csv (analytical)."""
from __future__ import annotations
import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC  = ROOT / "data" / "raw" / "e7.csv"
OUT_DIR = ROOT / "data" / "tables"


def main() -> None:
    rows = list(csv.DictReader(SRC.open()))
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    lines = [
        r"\begin{table}[t]",
        r"\centering",
        r"\caption{Storage growth per request, amortized over the headline batch size $N{=}1000$.}",
        r"\label{tab:storage}",
        r"\begin{tabular}{lrr}",
        r"\hline",
        r"System & Bytes/req (amortized) & Fixed overhead (B) \\",
        r"\hline",
    ]
    for r in rows:
        sys_short = r["system"].replace("TallyMeshOpt", "TM-").replace("PerRequest", "PR-").replace("SignedVoucher", "SV-")
        lines.append(
            f"{sys_short} & {r['bytes_per_request_amortized']} & {r['fixed_overhead_bytes']} \\\\"
        )
    lines += [r"\hline", r"\end{tabular}", r"\end{table}"]
    (OUT_DIR / "tab4_storage.tex").write_text("\n".join(lines) + "\n")
    print(f"wrote {OUT_DIR / 'tab4_storage.tex'}")


if __name__ == "__main__":
    main()
