"""Shared matplotlib style for paper figures. IEEE-conf single-column ~ 3.5",
double-column ~ 7.16". Use serif body, sans-serif math is OK for legibility."""
from __future__ import annotations
import matplotlib as mpl
import matplotlib.pyplot as plt

SINGLE_COLUMN_IN = 3.5
DOUBLE_COLUMN_IN = 7.16
SHORT_HEIGHT_IN = 2.5
TALL_HEIGHT_IN = 4.0


def apply() -> None:
    mpl.rcParams.update({
        "font.family": "serif",
        "font.size": 9,
        "axes.titlesize": 9,
        "axes.labelsize": 9,
        "xtick.labelsize": 8,
        "ytick.labelsize": 8,
        "legend.fontsize": 8,
        "axes.spines.top": False,
        "axes.spines.right": False,
        "figure.dpi": 150,
        "savefig.dpi": 300,
        "savefig.bbox": "tight",
        "savefig.pad_inches": 0.02,
    })


SYSTEM_COLORS = {
    "PerRequestNaive":             "#a6611a",
    "PerRequestEventOnly":         "#dfc27d",
    "SignedVoucherNetting":        "#80cdc1",
    "SignedVoucherAggregate":      "#018571",
    "TallyMeshOptReceiptsOnly":    "#1a76d2",
    "TallyMeshOptReceiptsPlusDeltas": "#b22222",
}

SYSTEM_LABELS = {
    "PerRequestNaive":             "Per-request (naive)",
    "PerRequestEventOnly":         "Per-request (event-only)",
    "SignedVoucherNetting":        "Signed voucher (netting)",
    "SignedVoucherAggregate":      "Signed voucher (aggregate)",
    "TallyMeshOptReceiptsOnly":    "TallyMesh (receipts-only)",
    "TallyMeshOptReceiptsPlusDeltas": "TallyMesh (receipts+deltas)",
}


def save(fig: "plt.Figure", path: str) -> None:
    fig.savefig(path)
    fig.savefig(path.replace(".pdf", ".png"))
    print(f"wrote {path} (+ .png)")
