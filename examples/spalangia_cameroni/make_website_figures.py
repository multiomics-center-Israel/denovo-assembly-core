#!/usr/bin/env python
"""Regenerate website figures from current canonical v3 numbers (2026-06-30).
All values verified against annotation/canonical_annotation/Spalangia_cameroni.final.*
and analysis/busco/* . Run: conda run -n genome_assembly python make_figures.py
"""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch
import numpy as np
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "figures")
os.makedirs(OUT, exist_ok=True)
DPI = 150
plt.rcParams.update({"font.size": 11, "axes.titlesize": 13, "axes.titleweight": "bold",
                     "figure.facecolor": "white", "savefig.facecolor": "white"})

C_BLUE   = "#2c6fbb"
C_GREEN  = "#3a9d5d"
C_ORANGE = "#e08a1e"
C_RED    = "#c0392b"
C_PURPLE = "#7d5ba6"
C_GRAY   = "#9aa3ab"
C_NAVY   = "#142a4f"

def save(fig, name):
    p = os.path.join(OUT, name)
    fig.savefig(p, dpi=DPI, bbox_inches="tight")
    plt.close(fig)
    print("wrote", p)

# ---------------------------------------------------------------------------
# 1. Assembly summary stats
# ---------------------------------------------------------------------------
def plot_assembly_stats():
    rows = [
        ("Total length",        "650,907,546 bp  (650.9 Mb)"),
        ("Number of contigs",   "4,980"),
        ("Largest contig",      "3,185,538 bp  (3.19 Mb)"),
        ("Contig N50",          "273,137 bp  (273 kb)"),
        ("N90",                 "50,430 bp"),
        ("L50",                 "631"),
        ("Mean contig length",  "130,704 bp"),
        ("GC content",          "37.06 %"),
        ("Gaps (N's)",          "0  (0.00 %)"),
        ("Assembly QV (Merqury)","45.63"),
        ("k-mer completeness",  "88.94 %"),
        ("Genome BUSCO (odb10)","C:89.3% [S:77.4% D:11.9%] F:1.9% M:8.8%"),
    ]
    fig, ax = plt.subplots(figsize=(9.2, 5.4))
    ax.axis("off")
    ax.set_title("Final assembly  —  final_assembly.fa (hifiasm, NextPolish-polished, contig-level)",
                 pad=14)
    tbl = ax.table(cellText=rows, colLabels=["Metric", "Value"],
                   cellLoc="left", colLoc="left", loc="center",
                   colWidths=[0.34, 0.66])
    tbl.auto_set_font_size(False)
    tbl.set_fontsize(11)
    tbl.scale(1, 1.55)
    for (r, c), cell in tbl.get_celld().items():
        cell.set_edgecolor("#cdd5dc")
        if r == 0:
            cell.set_facecolor(C_BLUE); cell.set_text_props(color="white", weight="bold")
        elif r % 2 == 0:
            cell.set_facecolor("#eef3f8")
    save(fig, "01_assembly_stats.png")

# ---------------------------------------------------------------------------
# 2. Protein BUSCO across build steps + genome & Nasonia references
# ---------------------------------------------------------------------------
def plot_busco_tracks():
    tracks = ["EVM\nconsensus", "BRAKER3\nall 11", "+Tiberius\nrescue",
              "+busco\nrescue", "+PASA UTRs\ncanonical v3",
              "genome\nassembly", "Nasonia\nproteome"]
    S = [65.9, 53.0, 71.8, 72.8, 64.2, 77.4, 43.5]
    D = [ 9.1, 22.9, 10.1,  9.2, 18.8, 11.9, 52.8]
    F = [ 3.8,  2.7,  5.0,  4.4,  4.1,  1.9,  0.5]
    M = [21.1, 21.5, 13.1, 13.7, 12.8,  8.8,  3.3]
    C = [75.1, 75.9, 81.9, 82.0, 83.0, 89.3, 96.3]   # reported complete %
    x = np.arange(len(tracks))
    fig, ax = plt.subplots(figsize=(10.2, 5.4))
    ax.bar(x, S, color=C_GREEN, label="Complete single-copy (S)")
    ax.bar(x, D, bottom=S, color="#8fd0a6", label="Complete duplicated (D)")
    ax.bar(x, F, bottom=np.array(S)+np.array(D), color=C_ORANGE, label="Fragmented (F)")
    ax.bar(x, M, bottom=np.array(S)+np.array(D)+np.array(F), color=C_RED, label="Missing (M)")
    for i in range(len(tracks)):
        ax.text(i, C[i] + (F[i]+M[i])/2 + 1, f"C={C[i]:.1f}%", ha="center",
                va="center", fontweight="bold", fontsize=9)
    ax.set_xticks(x); ax.set_xticklabels(tracks, fontsize=9)
    ax.set_ylabel("% of BUSCO groups (n=5,991)")
    ax.set_ylim(0, 108)
    ax.set_title("Protein BUSCO across annotation build steps, vs genome and Nasonia references")
    ax.legend(loc="upper left", fontsize=8.3, framealpha=0.95, ncol=2)
    # separator before the two reference bars
    ax.axvline(4.5, ls=":", color="#5a6168", lw=1.2)
    ax.text(5.5, 103, "reference points", ha="center", fontsize=8.5, color="#5a6168")
    ax.text(0.02, -0.16,
            "build steps & Nasonia: protein mode · genome assembly: miniprot mode · hymenoptera_odb10",
            transform=ax.transAxes, fontsize=8, color="#5a6168")
    save(fig, "02_busco_tracks.png")

# ---------------------------------------------------------------------------
# 3. Annotation feature counts (canonical v3 final.gff3)
# ---------------------------------------------------------------------------
def plot_feature_counts():
    feats = ["gene", "mRNA", "pseudogene", "exon", "CDS", "5'UTR", "3'UTR", "tRNA", "rRNA"]
    vals  = [18461,  19769,  300,          100978, 94335, 12937,   10653,   630,    8]
    colors = [C_BLUE, C_BLUE, C_GRAY, C_GREEN, C_GREEN, C_ORANGE, C_ORANGE, C_PURPLE, C_PURPLE]
    fig, ax = plt.subplots(figsize=(9.4, 5.0))
    bars = ax.bar(feats, vals, color=colors)
    ax.set_yscale("log")
    ax.set_ylabel("count (log scale)")
    ax.set_title("Canonical v3 feature counts (Spalangia_cameroni.final.gff3)")
    for b, v in zip(bars, vals):
        ax.text(b.get_x() + b.get_width()/2, v*1.08, f"{v:,}",
                ha="center", va="bottom", fontsize=9, fontweight="bold")
    ax.set_ylim(top=max(vals)*2.2)
    ax.text(0.01, -0.14, "18,461 genes = 17,523 protein-coding + 300 pseudogene + 630 tRNA + 8 rRNA",
            transform=ax.transAxes, fontsize=8.5, color="#5a6168")
    plt.setp(ax.get_xticklabels(), rotation=20, ha="right")
    save(fig, "03_feature_counts.png")

# ---------------------------------------------------------------------------
# 4. RNA-Seq libraries — primary mapped reads (unchanged inputs)
# ---------------------------------------------------------------------------
def plot_rnaseq():
    libs   = ["public","venom","wholebody","NS_5","NS_6","NS_7","NS_8","S_1","S_2","S_3","S_4"]
    tissue = ["body","venom","body","body_NS","body_NS","body_NS","body_NS","body_S","body_S","body_S","body_S"]
    mapped = [15358759,25638896,112640094,30809399,44114007,37791916,38026246,
              55570724,48863759,45056798,54769047]
    cmap = {"body":C_BLUE,"venom":C_RED,"body_NS":C_GREEN,"body_S":C_ORANGE}
    colors = [cmap[t] for t in tissue]
    vals = [m/1e6 for m in mapped]
    fig, ax = plt.subplots(figsize=(9.0, 5.0))
    bars = ax.bar(libs, vals, color=colors)
    ax.set_ylabel("primary mapped reads (millions)")
    ax.set_title("RNA-Seq evidence — 11 libraries aligned to genome (HISAT2)")
    for b, v in zip(bars, vals):
        ax.text(b.get_x()+b.get_width()/2, v+1.5, f"{v:.0f}", ha="center",
                va="bottom", fontsize=8.5)
    handles = [mpatches.Patch(color=c, label=l) for l,c in cmap.items()]
    ax.legend(handles=handles, title="tissue/condition", fontsize=8.5, title_fontsize=9)
    ax.set_ylim(top=max(vals)*1.15)
    plt.setp(ax.get_xticklabels(), rotation=30, ha="right")
    save(fig, "04_rnaseq_libs.png")

# ---------------------------------------------------------------------------
# 5. PASA UTR / isoform refinement (integrated in v3)
# ---------------------------------------------------------------------------
def plot_pasa_utr():
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(9.4, 4.6))
    labels = ["v2\n(CDS-locked)", "v3\n(PASA all-11)"]
    frac = [38.4, 53.4]   # 6,455/16,820 ; 10,553/19,769
    bars = ax1.bar(labels, frac, color=[C_GRAY, C_GREEN], width=0.55)
    ax1.set_ylabel("% mRNA carrying a UTR")
    ax1.set_ylim(0, 70)
    ax1.set_title("UTR coverage")
    for b, v in zip(bars, frac):
        ax1.text(b.get_x()+b.get_width()/2, v+1.5, f"{v:.1f}%", ha="center",
                 va="bottom", fontweight="bold")
    ax1.annotate("", xy=(1, 55), xytext=(0, 40),
                 arrowprops=dict(arrowstyle="->", color=C_RED, lw=1.6))
    ax1.text(0.5, 61, "+15.0 pts", ha="center", color=C_RED, fontweight="bold")
    # transcript / isoform counts
    x = np.arange(1); w = 0.35
    ax2.bar(x-w/2, [16820], w, color=C_GRAY, label="v2: 16,820")
    ax2.bar(x+w/2, [19769], w, color=C_GREEN, label="v3: 19,769")
    ax2.set_xticks([]); ax2.set_title("mRNA / transcript models")
    ax2.set_ylabel("count")
    ax2.text(0, 19769+400, "+2,949\nmRNA", ha="center", color=C_RED,
             fontweight="bold", fontsize=10)
    ax2.legend(fontsize=8.5, loc="lower center")
    ax2.set_ylim(0, 23000)
    fig.suptitle("PASA UTR/isoform refinement — integrated in canonical v3",
                 fontsize=12, fontweight="bold")
    save(fig, "05_pasa_utr.png")

# ---------------------------------------------------------------------------
# 6. Pipeline flow diagram (2 assemblers, read pre-filter, Kaiju nr)
# ---------------------------------------------------------------------------
def plot_flow():
    steps = [
        ("Sequencing\nPacBio HiFi ~12x\nIllumina ~80x", C_BLUE),
        ("QC & survey\nGenomeScope2\n~612 Mb, 0.55% het", C_BLUE),
        ("Read filter\nminimap2 map-hifi\nvs contaminant panel", C_GREEN),
        ("Assembly\nhifiasm + Flye\n(2 assemblers compared)", C_GREEN),
        ("Polishing\nNextPolish\n(Illumina)", C_GREEN),
        ("Decontamination\nKaiju vs NCBI nr\n+ rescue; Wolbachia bin", C_ORANGE),
        ("NCBI FCS\nGX + Adaptor\nclean, 0 edits", C_ORANGE),
        ("Repeat masking\nRepeatModeler2 +\nRepeatMasker", C_PURPLE),
        ("RNA-Seq align\n11 libs HISAT2/STAR\n+ StringTie", C_PURPLE),
        ("Structural annot.\nBRAKER3 + EVM +\nTiberius + PASA", C_RED),
        ("Functional annot.\nfunannotate + eggNOG\nPFAM / GO / products", C_RED),
    ]
    cols_x = [0.2, 3.55, 6.9]
    rows_y = [8.4, 6.0, 3.6, 1.2]
    bw, bh = 2.7, 1.4
    # serpentine column order per row
    order = []
    for r in range(4):
        cols = [0,1,2] if r % 2 == 0 else [2,1,0]
        for c in cols:
            order.append((cols_x[c], rows_y[r]))
    coords = order[:len(steps)]
    fig, ax = plt.subplots(figsize=(11.8, 8.2))
    ax.axis("off"); ax.set_xlim(0, 10); ax.set_ylim(0, 10)
    positions = []
    for (txt, col), (x, y) in zip(steps, coords):
        b = FancyBboxPatch((x, y), bw, bh, boxstyle="round,pad=0.06,rounding_size=0.12",
                           linewidth=1.4, edgecolor=col, facecolor=col+"22")
        ax.add_patch(b)
        ax.text(x+bw/2, y+bh/2, txt, ha="center", va="center", fontsize=8.6)
        positions.append((x, y, bw, bh))
    for i in range(len(steps)-1):
        x0,y0,w0,h0 = positions[i]; x1,y1,w1,h1 = positions[i+1]
        sx, sy = x0+w0/2, y0+h0/2; ex, ey = x1+w1/2, y1+h1/2
        if abs(sy-ey) < 0.1:
            if ex > sx: sx2, ex2 = x0+w0, x1
            else:       sx2, ex2 = x0, x1+w1
            a = FancyArrowPatch((sx2, sy), (ex2, ey), arrowstyle="-|>",
                                mutation_scale=14, color="#5a6168", lw=1.5)
        else:
            a = FancyArrowPatch((sx, y0), (ex, y1+h1), arrowstyle="-|>",
                                mutation_scale=14, color="#5a6168", lw=1.5)
        ax.add_patch(a)
    ax.set_title("Spalangia cameroni genome assembly & annotation pipeline",
                 fontsize=14, fontweight="bold")
    save(fig, "06_pipeline_flow.png")

if __name__ == "__main__":
    plot_assembly_stats()
    plot_busco_tracks()
    plot_feature_counts()
    plot_rnaseq()
    plot_pasa_utr()
    plot_flow()
    print("ALL FIGURES DONE")
