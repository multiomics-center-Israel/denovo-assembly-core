#!/usr/bin/env python
"""Regenerate the two-column pipeline overview from current canonical v3 numbers.
Run: conda run -n genome_assembly python make_pipeline_overview.py
Outputs website_transfer/figures/pipeline_overview.{png,svg}
"""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch
import matplotlib.patches as mpatches
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "figures")
os.makedirs(OUT, exist_ok=True)

NAVY="#34495e"; TEAL="#2c7a8c"; RED="#b03a2e"; GREEN="#3a7d44"; PURPLE="#7d5ba6"
DGREEN="#196f5b"; BROWN="#8a7060"; BLUE="#1f6fb2"; ORANGE="#e08a1e"; SLATE="#5d6d7e"
MAGENTA="#a61e6b"; ARROW="#5a6168"

left = [
 ("Raw sequencing data  (sample GMCF_3514_04)",
  ["PacBio Revio HiFi · 866K reads · 7.9 Gb · ~12×",
   "Illumina NovaSeq X · 364M reads · 52 Gb · ~80×"], NAVY, False),
 ("Phase 1 · QC & genome profiling",
  ["seqkit / NanoPlot · fastp (Illumina trim)",
   "Jellyfish + GenomeScope 2.0",
   "→ ~612 Mb haploid · 0.55% het (diploid ♀) · ~30% repeats"], TEAL, False),
 ("★ Read-level decontamination  (alignment + insect rescue)",
  ["minimap2 map-hifi (HiFi) · bowtie2 --local (Illumina)",
   "vs composite contaminant ref · unique-best filter",
   "DROP = contaminant hits − insect hits  (NOT k-mer LCA)"], RED, False),
 ("Phase 2 · De novo assembly  (two assemblers)",
  ["hifiasm + Flye compared  (MaSuRCA / NextDenovo not completed)",
   "purge_dups → QUAST + BUSCO + MUMmer",
   "→ hifiasm selected on contiguity + completeness"], GREEN, False),
 ("Phase 3 · Polishing",
  ["NextPolish with Illumina short reads (2 rounds)",
   "→ consensus base accuracy"], PURPLE, False),
 ("★ Phase 4 · Contig-level decontamination  (Kaiju)",
  ["Kaiju vs NCBI nr protein DB (zeus HPC, ~240 GB)",
   "+ read-depth + insect-homology rescue → per-contig call",
   "→ drop tier-1 contam · bin Wolbachia (8.7 Mb) → 5,040 → 4,980 contigs"], RED, False),
 ("Phase 6 · Final assembly QC",
  ["BUSCO hymenoptera_odb10  89.3%  · QUAST",
   "Merqury QV 45.6 · k-mer completeness 88.9%"], TEAL, False),
 ("FINAL ASSEMBLY  →  final_assembly.fa",
  ["4,980 contigs · 650.9 Mb · N50 273 kb · GC 37.1%"], DGREEN, False),
]

right = [
 ("Phase 7.1 · Repeat modeling & masking",
  ["RepeatModeler → species TE library",
   "RepeatMasker → soft-masked genome",
   "input: masked final_assembly.fa"], BROWN, False),
 ("Phase 7.2–7.3 · Evidence alignment",
  ["11 RNA-Seq libraries → HISAT2 / STAR + StringTie",
   "TSA GBVV01 transcripts → minimap2 splice",
   "Nasonia vitripennis proteome → protein evidence"], BLUE, False),
 ("Phase 7.4 · Gene prediction",
  ["BRAKER3 (GeneMark-ETP + AUGUSTUS + TSEBRA) over 11 BAMs",
   "+ Tiberius ab-initio rescue (GPU, StringTie-gated)"], ORANGE, False),
 ("Consensus & structure refinement",
  ["EVidenceModeler — weighted consensus",
   "PASA all-11 → 5′/3′ UTRs + isoforms  (integrated)"], ORANGE, False),
 ("Phase 7.5 · Functional annotation",
  ["funannotate annotate + eggNOG (emapper-2.1.13)",
   "PFAM 11,825 · MEROPS 642 · CAZyme 237",
   "products 14,178 · GO 9,486 mRNA"], PURPLE, False),
 ("Pseudogene flagging  (pre-submission)",
  ["300 sole-isoform internal-stop genes → pseudogene",
   "CDS removed · proteome clean = 19,769, 0 internal stops"], SLATE, False),
 ("CANONICAL GENE SET  —  v3",
  ["18,461 genes = 17,523 PC + 300 pseudo + 638 ncRNA",
   "19,769 proteins · BUSCO 83.0% · GO / PFAM / eggNOG",
   "structural + functional GFF3 · NCBI-submission-ready"], DGREEN, False),
 ("Dedicated venom track  (decoupled)",
  ["miniprot / DIAMOND vs Nasonia venom proteome",
   "+ SignalP secretion filter",
   "→ venom-gland candidate catalogue"], MAGENTA, True),
]

fig, ax = plt.subplots(figsize=(20, 13.0))
ax.set_xlim(0, 100); ax.set_ylim(0, 100); ax.axis("off")

LX0, RX0, W = 2.0, 54.0, 44.0
TOP, SLOT, BH = 86.0, 10.0, 8.4

def draw_col(items, x0):
    pos = []
    for i,(title, lines, col, dashed) in enumerate(items):
        ytop = TOP - i*SLOT
        y = ytop - BH
        style = "round,pad=0.15,rounding_size=0.5"
        b = FancyBboxPatch((x0, y), W, BH, boxstyle=style,
                           linewidth=(2.2 if dashed else 1.2),
                           edgecolor=("#ffffff" if not dashed else col),
                           facecolor=col, alpha=(0.45 if dashed else 1.0),
                           linestyle=("--" if dashed else "-"))
        ax.add_patch(b)
        tcol = "white" if not dashed else "#3a0f25"
        ax.text(x0+W/2, ytop-1.5, title, ha="center", va="center",
                fontsize=12.5, fontweight="bold", color=tcol)
        for j,ln in enumerate(lines):
            ax.text(x0+W/2, ytop-3.4-j*1.75, ln, ha="center", va="center",
                    fontsize=9.6, color=tcol)
        pos.append((x0, ytop, y))
    return pos

lpos = draw_col(left, LX0)
rpos = draw_col(right, RX0)

def varrow(pos, i, x0, col=ARROW):
    _,_,ybot_i = pos[i]; _,ytop_j,_ = pos[i+1]
    ax.add_patch(FancyArrowPatch((x0+W/2, ybot_i), (x0+W/2, ytop_j),
                 arrowstyle="-|>", mutation_scale=18, color=col, lw=2.0))

for i in range(len(left)-1):
    varrow(lpos, i, LX0)
# right main chain 0..6 (skip venom box index 7)
for i in range(6):
    varrow(rpos, i, RX0)

# masked-genome cross arrow: final assembly (left, box7) -> 7.1 (right, box0)
lx, lytop, ly = lpos[7]
rx, rytop, ry = rpos[0]
ax.add_patch(FancyArrowPatch((lx+W, lytop-BH/2), (rx, rytop-BH/2),
             arrowstyle="-|>", mutation_scale=18, color=DGREEN, lw=2.2,
             connectionstyle="arc3,rad=0.32"))
ax.text(50.0, 70.0, "masked\ngenome", ha="center", va="center",
        fontsize=10.5, fontweight="bold", color=DGREEN)

# venom is a decoupled side deliverable (dashed box + label convey this; no derivation arrow)
vx, vytop, vy = rpos[7]
ax.text(RX0+W/2, vytop-BH-0.7, "fed by protein evidence · separate deliverable, not part of the canonical chain",
        ha="center", va="center", fontsize=8.5, fontstyle="italic", color=MAGENTA)

# headers
ax.text(50, 98.5, "Spalangia cameroni  —  genome assembly & annotation pipeline",
        ha="center", va="center", fontsize=20, fontweight="bold", color="#1a1f27")
ax.text(50, 95.2, "PacBio HiFi + Illumina · two-assembler contig assembly · evidence-based annotation"
        "   |   two contaminant filters (★) highlighted in red",
        ha="center", va="center", fontsize=11.5, fontstyle="italic", color="#4a525c")
ax.text(LX0+W/2, 90.0, "ASSEMBLY", ha="center", fontsize=13, fontweight="bold", color=GREEN)
ax.text(RX0+W/2, 90.0, "ANNOTATION", ha="center", fontsize=13, fontweight="bold", color=ORANGE)

# legend
leg = [("★ contaminant filtering steps", RED), ("assembly", GREEN),
       ("gene prediction / refinement", ORANGE), ("venom track (decoupled)", MAGENTA)]
handles = [mpatches.Patch(color=c, label=l) for l,c in leg]
ax.legend(handles=handles, loc="lower center", ncol=4, fontsize=10.5,
          frameon=False, bbox_to_anchor=(0.5, -0.02))
ax.text(99, 1.0, "S. cameroni · contig-level (no Hi-C) · conda env genome_assembly · 2026-06-30",
        ha="right", va="center", fontsize=8.5, color="#8a929b")

for ext in ("png", "svg"):
    p = os.path.join(OUT, f"pipeline_overview.{ext}")
    fig.savefig(p, dpi=150, bbox_inches="tight")
    print("wrote", p)
plt.close(fig)
