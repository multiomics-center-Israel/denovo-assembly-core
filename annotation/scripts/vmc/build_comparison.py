#!/usr/bin/env python3
"""Cross-stage annotation + assembly comparison table & figure.
Parses every BUSCO short_summary it can find, counts genes from each stage's
GFF/GTF, and tabulates Spalangia stages alongside Nasonia. Writes a TSV and a
matplotlib bar figure. Pure stdlib + matplotlib; no network.
"""
import os, re, glob, sys
PROJ = "/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly"

BUSCO_RE = re.compile(
    r"C:([\d.]+)%\[S:([\d.]+)%,D:([\d.]+)%\],F:([\d.]+)%,M:([\d.]+)%,n:(\d+)")

def parse_busco(path):
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

def count_genes(path):
    """Count 'gene' features in a GFF3/GTF; fall back to unique gene_id, then proteins."""
    if not path or not os.path.exists(path):
        return None
    genes = 0
    gids = set()
    with open(path) as fh:
        for line in fh:
            if line.startswith("#") or "\t" not in line:
                continue
            cols = line.rstrip("\n").split("\t")
            if len(cols) < 9:
                continue
            if cols[2] == "gene":
                genes += 1
            m = re.search(r'gene_id "?([^";]+)"?', cols[8])
            if m:
                gids.add(m.group(1))
    if genes:
        return genes
    return len(gids) or None

def count_fasta(path):
    if not path or not os.path.exists(path):
        return None
    n = 0
    with open(path) as fh:
        for line in fh:
            if line.startswith(">"):
                n += 1
    return n

# (label, kind, busco_summary, gene_gff, protein_fa)
B = os.path.join(PROJ, "analysis", "busco")
def ss(d):
    g = glob.glob(os.path.join(B, d, "short_summary*.txt"))
    return g[0] if g else None

STAGES = [
    ("Spalangia genome (assembly)", "assembly",
        os.path.join(PROJ, "qc/busco_results/short_summary.specific.hymenoptera_odb10.busco_results.txt"),
        None, None),
    ("Spalangia BRAKER3", "annotation", ss("braker_prot"),
        os.path.join(PROJ, "annotation/braker/braker.gff3"), None),
    ("Spalangia rescued (RNA-seq)", "annotation", ss("rescued_prot"),
        os.path.join(PROJ, "annotation/refine/rescued.gff3"), None),
    ("Spalangia BRAKER+OrthoDB", "annotation", ss("odb_prot"),
        os.path.join(PROJ, "annotation/braker_odb/braker.gff3"), None),
    ("Spalangia EVM+PASA (CANONICAL)", "annotation", ss("evm_pasa_prot"),
        os.path.join(PROJ, "annotation/funannotate_evm_out/annotate_results/Spalangia_cameroni.gff3"),
        os.path.join(PROJ, "annotation/funannotate_evm_out/annotate_results/Spalangia_cameroni.proteins.fa")),
    ("Spalangia Tiberius (ab initio)", "annotation", ss("tiberius_prot"),
        os.path.join(PROJ, "tiberius_athena_res/tiberius_insecta.gtf"),
        os.path.join(PROJ, "tiberius_athena_res/tiberius_insecta.aa.fa")),
    ("Nasonia vitripennis (RefSeq)", "annotation", ss("nasonia_prot"),
        None, os.path.join(PROJ, "/mnt/data/genomes/wasp_nasonia/GCF_009193385.2_Nvit_psr_1.1_protein.faa")),
]

rows = []
for label, kind, bpath, gff, fa in STAGES:
    bu = parse_busco(bpath)
    ng = count_genes(gff)
    if ng is None and fa:
        ng = count_fasta(fa)
    rows.append((label, kind, ng, bu))

out_tsv = os.path.join(PROJ, "analysis/comparison/annotation_comparison.tsv")
with open(out_tsv, "w") as o:
    o.write("stage\tkind\tn_genes_or_proteins\tBUSCO_C%\tS%\tD%\tF%\tM%\tn\n")
    for label, kind, ng, bu in rows:
        if bu:
            o.write(f"{label}\t{kind}\t{ng if ng is not None else 'NA'}\t"
                    f"{bu['C']}\t{bu['S']}\t{bu['D']}\t{bu['F']}\t{bu['M']}\t{bu['n']}\n")
        else:
            o.write(f"{label}\t{kind}\t{ng if ng is not None else 'NA'}\tNA\tNA\tNA\tNA\tNA\tNA\n")
print("wrote", out_tsv)

# ---- figure: BUSCO completeness (stacked S/D/F/M) across annotation stages ----
try:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    labels, S, D, F, M = [], [], [], [], []
    for label, kind, ng, bu in rows:
        if not bu:
            continue
        labels.append(label.replace("Spalangia ", "").replace(" (CANONICAL)", "*"))
        S.append(bu['S']); D.append(bu['D']); F.append(bu['F']); M.append(bu['M'])
    import numpy as np
    x = np.arange(len(labels))
    fig, ax = plt.subplots(figsize=(11, 6))
    ax.bar(x, S, label="Single (S)", color="#2c7bb6")
    ax.bar(x, D, bottom=S, label="Duplicated (D)", color="#abd9e9")
    bottom2 = [s+d for s, d in zip(S, D)]
    ax.bar(x, F, bottom=bottom2, label="Fragmented (F)", color="#fdae61")
    bottom3 = [b+f for b, f in zip(bottom2, F)]
    ax.bar(x, M, bottom=bottom3, label="Missing (M)", color="#d7191c")
    ax.set_ylabel("% of 5,991 hymenoptera_odb10 BUSCOs")
    ax.set_title("BUSCO completeness across annotation stages (Spalangia vs Nasonia)\n* = canonical EVM+PASA set")
    ax.set_xticks(x); ax.set_xticklabels(labels, rotation=30, ha="right", fontsize=8)
    ax.legend(loc="lower right", fontsize=8); ax.set_ylim(0, 100)
    fig.tight_layout()
    png = os.path.join(PROJ, "annotation/figures/stage_comparison.png")
    fig.savefig(png, dpi=150); print("wrote", png)
except Exception as e:
    print("figure skipped:", e, file=sys.stderr)
