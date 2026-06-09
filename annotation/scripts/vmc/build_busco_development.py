#!/usr/bin/env python3
"""BUSCO development across the Spalangia cameroni annotation build trajectory.

Parses the odb10 protein-mode BUSCO short_summaries under analysis/busco/ in
build order, writes a TSV, and renders a stacked-bar figure (S/D/F/M) so the
completeness gain from BRAKER -> EVM+PASA -> +Tiberius graft -> final canonical
is visible at a glance. Pure stdlib + matplotlib; no network.
"""
import os, re, glob
PROJ = "/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly"
B = os.path.join(PROJ, "analysis", "busco")
BUSCO_RE = re.compile(
    r"C:([\d.]+)%\[S:([\d.]+)%,D:([\d.]+)%\],F:([\d.]+)%,M:([\d.]+)%,n:(\d+)")

# (busco_key, label, gene_count)   gene_count from prior structural counts
STAGES = [
    ("braker_prot",            "BRAKER3 (RNA-seq+prot)",            9761),
    ("odb_prot",               "BRAKER+OrthoDB",                    10744),
    ("tiberius_prot",          "Tiberius (ab-initio input)",        None),
    ("evm_prot",               "EVM consensus",                     None),
    ("evm_pasa_prot",          "EVM+PASA (prev canonical)",         12580),
    ("evm_tib_consensus_prot", "EVM+Tiberius consensus",            None),
    ("merged_evm_tib_prot",    "Merged: EVM+PASA + Tiberius graft", 16656),
    ("merged_canonical_prot",  "Merged canonical (funannotate)",    16656),
    ("merged_plus_rescue_prot","FINAL + miniprot BUSCO-rescue",     16820),
    ("nasonia_prot",           "Nasonia vitripennis (RefSeq ref)",  None),
]

def parse_path(path):
    if not path or not os.path.exists(path):
        return None
    with open(path) as fh:
        for line in fh:
            m = BUSCO_RE.search(line)
            if m:
                c, s, d, f, mi, n = m.groups()
                return dict(C=float(c), S=float(s), D=float(d),
                            F=float(f), M=float(mi), n=int(n))
    return None

def parse(key):
    g = glob.glob(os.path.join(B, key, "short_summary*.txt"))
    return parse_path(g[0]) if g else None

# Genome-mode BUSCO of the assembly itself = the ceiling any annotation can reach.
GENOME_SS = os.path.join(
    PROJ, "qc/busco_results/short_summary.specific.hymenoptera_odb10.busco_results.txt")

rows = []  # (label, mode, n_genes, busco_dict)
gbu = parse_path(GENOME_SS)
if gbu:
    rows.append(("Genome assembly (CEILING)", "genome", 4980, gbu))
for key, label, ng in STAGES:
    bu = parse(key)
    if bu:
        rows.append((label, "proteins", ng, bu))

out_tsv = os.path.join(B, "busco_development.tsv")
with open(out_tsv, "w") as o:
    o.write("step\tbusco_mode\tn_seqs\tBUSCO_C%\tS%\tD%\tF%\tM%\tn\n")
    for label, mode, ng, bu in rows:
        o.write(f"{label}\t{mode}\t{ng if ng is not None else 'NA'}\t"
                f"{bu['C']}\t{bu['S']}\t{bu['D']}\t{bu['F']}\t{bu['M']}\t{bu['n']}\n")
print("wrote", out_tsv)

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

labels = [l.replace(" (RefSeq ref)", "\n(RefSeq ref)").replace(" (CEILING)", "\n(CEILING)")
          for l, _, _, _ in rows]
modes = [m for _, m, _, _ in rows]
S = [b['S'] for _, _, _, b in rows]
D = [b['D'] for _, _, _, b in rows]
F = [b['F'] for _, _, _, b in rows]
M = [b['M'] for _, _, _, b in rows]
C = [b['C'] for _, _, _, b in rows]
x = np.arange(len(labels))

fig, ax = plt.subplots(figsize=(13, 6.5))
ax.bar(x, S, label="Single-copy (S)", color="#2c7bb6")
ax.bar(x, D, bottom=S, label="Duplicated (D)", color="#abd9e9")
b2 = [s+d for s, d in zip(S, D)]
ax.bar(x, F, bottom=b2, label="Fragmented (F)", color="#fdae61")
b3 = [b+f for b, f in zip(b2, F)]
ax.bar(x, M, bottom=b3, label="Missing (M)", color="#d7191c")

# ceiling line drawn from the genome-mode row
ceiling = next((b['C'] for l, m, _, b in rows if m == "genome"), None)
if ceiling:
    ax.axhline(ceiling, ls="--", lw=1.2, color="#444",
               label=f"Genome-mode ceiling (C:{ceiling}%)")
for xi, c, m in zip(x, C, modes):
    ax.text(xi, 101, f"{c:.1f}", ha="center", va="bottom", fontsize=8, fontweight="bold")
    ax.text(xi, 2, m, ha="center", va="bottom", fontsize=6.5, color="white", rotation=90)

ax.set_ylabel("% of 5,991 hymenoptera_odb10 BUSCOs")
ax.set_title("BUSCO across the Spalangia cameroni annotation build — genome-mode ceiling vs protein-mode steps\n"
             "hymenoptera_odb10 — value above each bar = total Complete (C); mode printed inside each bar")
ax.set_xticks(x)
ax.set_xticklabels(labels, rotation=30, ha="right", fontsize=8)
ax.set_ylim(0, 108)
ax.legend(loc="lower left", fontsize=8, ncol=2)
fig.tight_layout()
png = os.path.join(PROJ, "annotation/figures/busco_development.png")
svg = os.path.join(PROJ, "annotation/figures/busco_development.svg")
fig.savefig(png, dpi=150)
fig.savefig(svg)
print("wrote", png)
print("wrote", svg)
