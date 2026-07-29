# eval/tables/tab_archetypes.py
"""E11 archetypes table for "Pareto frontier" / "Operating points" section."""
from __future__ import annotations
import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC  = ROOT / "data" / "derived" / "e11_archetypes.csv"
OUT_DIR = ROOT / "data" / "tables"


def main() -> None:
    rows = list(csv.DictReader(SRC.open()))
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    lines = [
        r"\begin{table}[t]",
        r"\centering",
        r"\caption{Three operating points selected by archetype-driven priority. $\Delta t=60$\,s; $N$, $K$, $\tau$, and $f$ are picker outputs from the E11 sweep. Gas/call from \S\,5 measurement.}",
        r"\label{tab:archetypes}",
        r"\begin{tabular}{lrrrrrrr}",
        r"\hline",
        r"Archetype & $N$ & $\tau$ (s) & $K$ & $f$ & $D_{\mathrm{sub}}$ & $T$ (rps) & $S_{\mathrm{fail}}$ \\",
        r"\hline",
    ]
    for r in rows:
        sfail = float(r["S_fail"])
        # Format scientific notation as math: m.mm \times 10^{exp}.
        # Using "%.2e" then parsing avoids the brittle string-replace pipeline.
        m, e = f"{sfail:.2e}".split("e")
        exp = int(e)  # strips leading zeros + handles sign
        sfail_str = f"${m}\\times 10^{{{exp}}}$"
        lines.append(
            f"{r['archetype']} & {r['N']} & {r['tau_sec']} & {r['K']} & {r['f']} & {r['D_sub']} & {float(r['throughput_rps']):.0f} & {sfail_str} \\\\"
        )
    lines += [r"\hline", r"\end{tabular}", r"\end{table}"]
    (OUT_DIR / "tab_archetypes.tex").write_text("\n".join(lines) + "\n")
    print(f"wrote {OUT_DIR / 'tab_archetypes.tex'}")


if __name__ == "__main__":
    main()
