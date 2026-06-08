#!/usr/bin/env python
"""Result figures for the S. cameroni annotation (Phase 7.6).

Generates three publication-style figures (PNG @300dpi + SVG) into --out:
  1. rnaseq_coverage_*  — RNA-Seq genome coverage from rnaseq_aligned.bam
  2. protein_support_*  — Nasonia tblastn + TSA pblat support of the assembly
  3. busco_*            — BUSCO completeness (hymenoptera_odb10)

Designed to depend only on already-existing inputs (BAMs, comparison_to_nasonia
outputs, BUSCO summary) so it can run in parallel with gene prediction. Each panel
degrades gracefully (prints a note, skips) if its input is missing.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

NAVY = "#1B3A5C"
TEAL = "#2A9D8F"
AMBER = "#E9C46A"
RUST = "#E76F51"
GREY = "#9AA5B1"


def save(fig, out: Path, stem: str):
    out.mkdir(parents=True, exist_ok=True)
    for ext in ("png", "svg"):
        fig.savefig(out / f"{stem}.{ext}", dpi=300, bbox_inches="tight")
    plt.close(fig)
    print(f"[fig] wrote {stem}.png / .svg")


# ────────────────────────────────────────────────────────────────────────────
# 1. RNA-Seq coverage  (uses `samtools coverage` — fast, per-contig)
# ────────────────────────────────────────────────────────────────────────────
def fig_rnaseq_coverage(project: Path, out: Path):
    bam = project / "rnaseq" / "rnaseq_aligned.bam"
    if not bam.exists():
        print(f"[skip] {bam} missing — no coverage figure")
        return
    cov_tsv = out / "rnaseq_samtools_coverage.tsv"
    print("[run] samtools coverage ...")
    with open(cov_tsv, "w") as fh:
        subprocess.run(["samtools", "coverage", str(bam)], stdout=fh, check=True)
    df = pd.read_csv(cov_tsv, sep="\t")
    # columns: #rname startpos endpos numreads covbases coverage meandepth meanbaseq meanmapq
    df = df.rename(columns={"#rname": "rname"})
    df["length"] = df["endpos"] - df["startpos"] + 1
    total_len = df["length"].sum()
    total_reads = int(df["numreads"].sum())
    wmean_depth = float((df["meandepth"] * df["length"]).sum() / max(total_len, 1))
    breadth1x = float((df["covbases"].sum() / max(total_len, 1)) * 100)

    fig, axes = plt.subplots(1, 3, figsize=(15, 4.5))
    fig.suptitle("RNA-Seq coverage of the assembly (SRR1502981 → final_assembly.fa)",
                 fontsize=14, color=NAVY, fontweight="bold")

    # A: per-contig mean depth histogram (log x)
    md = df["meandepth"].replace(0, np.nan).dropna()
    ax = axes[0]
    if len(md):
        bins = np.logspace(np.log10(max(md.min(), 0.1)), np.log10(md.max() + 1), 40)
        ax.hist(md, bins=bins, color=TEAL, edgecolor="white")
        ax.set_xscale("log")
    ax.axvline(wmean_depth, color=RUST, ls="--", lw=1.5,
               label=f"length-weighted mean = {wmean_depth:.1f}×")
    ax.set_xlabel("per-contig mean depth (×, log)")
    ax.set_ylabel("contigs")
    ax.set_title("A. Mean depth per contig")
    ax.legend(fontsize=8)

    # B: coverage breadth (%) distribution
    ax = axes[1]
    ax.hist(df["coverage"], bins=40, color=AMBER, edgecolor="white")
    ax.set_xlabel("contig breadth covered (%)")
    ax.set_ylabel("contigs")
    ax.set_title("B. Coverage breadth per contig")

    # C: contig length vs mean depth
    ax = axes[2]
    ax.scatter(df["length"], df["meandepth"], s=6, alpha=0.3, color=NAVY)
    ax.set_xscale("log"); ax.set_yscale("log")
    ax.set_xlabel("contig length (bp, log)")
    ax.set_ylabel("mean depth (×, log)")
    ax.set_title("C. Length vs depth")

    txt = (f"contigs: {len(df):,}   total length: {total_len/1e6:.1f} Mb   "
           f"mapped reads: {total_reads:,}   weighted mean depth: {wmean_depth:.1f}×   "
           f"breadth ≥1×: {breadth1x:.1f}%")
    fig.text(0.5, -0.04, txt, ha="center", fontsize=9, color=GREY)
    save(fig, out, "rnaseq_coverage")


# ────────────────────────────────────────────────────────────────────────────
# 2. Protein / transcript support (parse existing summary files)
# ────────────────────────────────────────────────────────────────────────────
def _grab(path: Path, pattern: str):
    if not path.exists():
        return None
    m = re.search(pattern, path.read_text())
    return float(m.group(1)) if m else None


def fig_protein_support(project: Path, out: Path):
    tbl = project / "comparison_to_nasonia" / "tblastn" / "tblastn_summary.txt"
    blt = project / "comparison_to_nasonia" / "blat" / "blat_summary.txt"
    if not tbl.exists() and not blt.exists():
        print("[skip] no tblastn/blat summary — no protein-support figure")
        return

    # tblastn: hit%, qcov>=50%, qcov>=80%
    t_hit = _grab(tbl, r">=1 hit.*?\(([\d.]+)%\)")
    t_50 = _grab(tbl, r">=50%\s*:\s*\d+\s*\(([\d.]+)%\)")
    t_80 = _grab(tbl, r">=80%\s*:\s*\d+\s*\(([\d.]+)%\)")
    # blat: align%, >=50%, >=90%
    b_hit = _grab(blt, r">=1 alignment.*?\(([\d.]+)%\)")
    b_50 = _grab(blt, r">=50% of tx\s*:\s*\d+\s*\(([\d.]+)%\)")
    b_90 = _grab(blt, r">=90% of tx\s*:\s*\d+\s*\(([\d.]+)%\)")

    fig, axes = plt.subplots(1, 2, figsize=(11, 4.5))
    fig.suptitle("External evidence support of the assembly", fontsize=14,
                 color=NAVY, fontweight="bold")

    ax = axes[0]
    labels = ["≥1 hit\n(e<1e-5)", "best-hit\nqcov ≥50%", "best-hit\nqcov ≥80%"]
    vals = [v if v is not None else 0 for v in (t_hit, t_50, t_80)]
    bars = ax.bar(labels, vals, color=[NAVY, TEAL, AMBER])
    ax.set_ylim(0, 100); ax.set_ylabel("% of Nasonia proteins (n=34,173)")
    ax.set_title("A. tblastn: Nasonia proteome → genome")
    for bar, v in zip(bars, vals):
        ax.text(bar.get_x() + bar.get_width()/2, v + 1.5, f"{v:.1f}%",
                ha="center", fontsize=9, fontweight="bold")

    ax = axes[1]
    labels = ["≥1 alignment", "best HSP\n≥50% tx", "best HSP\n≥90% tx"]
    vals = [v if v is not None else 0 for v in (b_hit, b_50, b_90)]
    bars = ax.bar(labels, vals, color=[NAVY, TEAL, AMBER])
    ax.set_ylim(0, 100); ax.set_ylabel("% of TSA transcripts (n=27,735)")
    ax.set_title("B. pblat: Spalangia TSA → genome")
    for bar, v in zip(bars, vals):
        ax.text(bar.get_x() + bar.get_width()/2, v + 1.5, f"{v:.1f}%",
                ha="center", fontsize=9, fontweight="bold")

    save(fig, out, "protein_support")


# ────────────────────────────────────────────────────────────────────────────
# 3. BUSCO completeness
# ────────────────────────────────────────────────────────────────────────────
def fig_busco(project: Path, out: Path):
    candidates = list((project / "qc" / "busco_results").glob("**/short_summary*.txt"))
    if not candidates:
        print("[skip] no BUSCO summary — no busco figure")
        return
    text = candidates[0].read_text()
    m = re.search(r"C:([\d.]+)%\[S:([\d.]+)%,D:([\d.]+)%\],F:([\d.]+)%,M:([\d.]+)%,n:(\d+)",
                  text)
    if not m:
        print("[skip] could not parse BUSCO line")
        return
    C, S, D, F, M, n = (float(m.group(i)) for i in range(1, 7))

    fig, ax = plt.subplots(figsize=(10, 2.6))
    segs = [("Complete single-copy (S)", S, TEAL),
            ("Complete duplicated (D)", D, NAVY),
            ("Fragmented (F)", F, AMBER),
            ("Missing (M)", M, RUST)]
    left = 0
    for label, val, color in segs:
        ax.barh(0, val, left=left, color=color, edgecolor="white", label=f"{label}: {val}%")
        if val >= 4:
            ax.text(left + val/2, 0, f"{val:.1f}%", ha="center", va="center",
                    color="white", fontsize=9, fontweight="bold")
        left += val
    ax.set_xlim(0, 100); ax.set_yticks([])
    ax.set_xlabel("% of BUSCO groups")
    ax.set_title(f"BUSCO hymenoptera_odb10 (n={int(n)})  —  C:{C}%",
                 fontsize=13, color=NAVY, fontweight="bold")
    ax.legend(loc="upper center", bbox_to_anchor=(0.5, -0.4), ncol=2, fontsize=9,
              frameon=False)
    save(fig, out, "busco")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    args = ap.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)

    ok = True
    for fn in (fig_rnaseq_coverage, fig_protein_support, fig_busco):
        try:
            fn(args.project, args.out)
        except Exception as e:
            ok = False
            print(f"[error] {fn.__name__}: {e}", file=sys.stderr)
    print("[done] figures written to", args.out)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
