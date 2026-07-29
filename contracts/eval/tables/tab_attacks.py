# eval/tables/tab_attacks.py
"""Sec. 2.3 attack-coverage table from security_battery.csv."""
from __future__ import annotations
import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC  = ROOT / "data" / "derived" / "security_battery.csv"
OUT_DIR = ROOT / "data" / "tables"


def _escape(s: str) -> str:
    # Order matters: escape backslash first (none expected in source, but
    # safe), then literal braces, then the usual LaTeX-special triplet.
    return (s
            .replace("\\", r"\textbackslash{}")
            .replace("{", r"\{")
            .replace("}", r"\}")
            .replace("&", r"\&")
            .replace("_", r"\_")
            .replace("#", r"\#"))


def main() -> None:
    rows = list(csv.DictReader(SRC.open()))
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    lines = [
        r"\begin{table*}[t]",
        r"\centering",
        r"\caption{Security battery (\S\,2.3): attack coverage status. Status \emph{covered} = concrete test asserts the defense; \emph{design} = structural defense (no setter, off-chain enforcement, primitives owner-gated).}",
        r"\label{tab:attacks}",
        r"\begin{tabular}{rlllll}",
        r"\hline",
        r"\# & Attack & Layer & Expected outcome & Status & Test \\",
        r"\hline",
    ]
    for r in rows:
        # Trim test_file to last path component for readability.
        test_short = r["test_file"].split(";")[0].rsplit("/", 1)[-1]
        lines.append(
            f"{r['id']} & {_escape(r['name'])} & {_escape(r['layer'])} & {_escape(r['expected_outcome'])} & {r['status']} & \\texttt{{{_escape(test_short)}}} \\\\"
        )
    lines += [r"\hline", r"\end{tabular}", r"\end{table*}"]
    (OUT_DIR / "tab_attacks.tex").write_text("\n".join(lines) + "\n")
    print(f"wrote {OUT_DIR / 'tab_attacks.tex'}")


if __name__ == "__main__":
    main()
