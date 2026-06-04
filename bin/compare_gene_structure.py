#!/usr/bin/env python
"""Compare gene-structure statistics between two annotations (GFF3/GTF) and plot
them side by side. Same parser on both so the numbers are apples-to-apples.
Restricts to protein-coding transcripts (mRNA features / transcripts with CDS).

  compare_gene_structure.py --a LABEL:file.gff --b LABEL:file.gff \
      --out-fig fig.png --out-tsv table.tsv
"""
import argparse, re, sys, collections, json
import numpy as np
import matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as plt

NAVY, TEAL = "#1B3A5C", "#2A9D8F"


def attr(s, *keys):
    for k in keys:
        m = re.search(rf'{k}[ =]"?([^";]+)"?', s)
        if m:
            return m.group(1)
    return None


def parse(path):
    """Return per-mRNA exons/CDS for protein-coding transcripts."""
    is_mrna, mrna_gene, strand = set(), {}, {}
    exons = collections.defaultdict(list); cds = collections.defaultdict(list)
    tx_type = {}
    for line in open(path):
        if line.startswith("#") or "\t" not in line:
            continue
        p = line.rstrip("\n").split("\t")
        if len(p) < 9:
            continue
        typ = p[2]
        if typ in ("mRNA", "transcript"):
            tid = attr(p[8], "ID", "transcript_id")
            if tid:
                is_mrna.add(tid); strand[tid] = p[6]
                mrna_gene[tid] = attr(p[8], "Parent", "gene_id") or tid
        elif typ == "exon":
            par = attr(p[8], "Parent", "transcript_id")
            if par:
                exons[par].append((int(p[3]), int(p[4])))
        elif typ == "CDS":
            par = attr(p[8], "Parent", "transcript_id")
            if par:
                cds[par].append((int(p[3]), int(p[4])))
    # protein-coding = transcripts that have CDS
    coding = [t for t in (is_mrna or set(exons)) if cds.get(t)]
    if not coding:                       # GTF without explicit mRNA lines
        coding = [t for t in exons if cds.get(t)]
    return coding, exons, cds, mrna_gene, strand


def compute(path):
    coding, exons, cds, mrna_gene, strand = parse(path)
    iso = collections.Counter()
    for t in coding:
        iso[mrna_gene.get(t, t)] += 1
    exons_per, prot_len, tx_span, exon_len, introns = [], [], [], [], []
    mono = multi = 0
    for t in coding:
        ex = sorted(exons.get(t, []))
        if not ex:
            continue
        exons_per.append(len(ex))
        mono += len(ex) == 1; multi += len(ex) > 1
        prot_len.append(sum(e - s + 1 for s, e in cds[t]) // 3)
        tx_span.append(ex[-1][1] - ex[0][0] + 1)
        for s, e in ex:
            exon_len.append(e - s + 1)
        for i in range(len(ex) - 1):
            introns.append(ex[i + 1][0] - ex[i][1] - 1)
    med = lambda x: int(np.median(x)) if x else 0
    return {
        "genes": len(set(mrna_gene[t] for t in coding if t in mrna_gene)) or len(iso),
        "transcripts": len(coding),
        "mean_isoforms_per_gene": round(np.mean(list(iso.values())), 2) if iso else 0,
        "median_exons_per_tx": med(exons_per),
        "pct_mono_exonic": round(100 * mono / (mono + multi), 1) if (mono + multi) else 0,
        "median_protein_aa": med(prot_len),
        "median_tx_span_bp": med(tx_span),
        "median_intron_bp": med([i for i in introns if i > 0]),
        "median_exon_bp": med(exon_len),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--a", required=True)   # LABEL:path
    ap.add_argument("--b", required=True)
    ap.add_argument("--out-fig", required=True)
    ap.add_argument("--out-tsv", required=True)
    g = ap.parse_args()
    (la, fa), (lb, fb) = g.a.split(":", 1), g.b.split(":", 1)
    sa, sb = compute(fa), compute(fb)

    metrics = [
        ("genes", "Genes"), ("transcripts", "Transcripts"),
        ("mean_isoforms_per_gene", "Isoforms/gene (mean)"),
        ("median_exons_per_tx", "Exons/tx (median)"),
        ("pct_mono_exonic", "% mono-exonic"),
        ("median_protein_aa", "Protein aa (median)"),
        ("median_tx_span_bp", "Tx span bp (median)"),
        ("median_intron_bp", "Intron bp (median)"),
    ]
    with open(g.out_tsv, "w") as f:
        f.write(f"metric\t{la}\t{lb}\n")
        for k, lab in metrics:
            f.write(f"{lab}\t{sa[k]}\t{sb[k]}\n")
    print(open(g.out_tsv).read())

    fig, axes = plt.subplots(2, 4, figsize=(16, 7))
    for ax, (k, lab) in zip(axes.ravel(), metrics):
        va, vb = sa[k], sb[k]
        bars = ax.bar([la, lb], [va, vb], color=[TEAL, NAVY])
        ax.set_title(lab, fontsize=11)
        for bar, v in zip(bars, [va, vb]):
            ax.text(bar.get_x() + bar.get_width() / 2, v,
                    f"{v:,}" if v >= 100 else f"{v}", ha="center", va="bottom", fontsize=9, fontweight="bold")
        ax.margins(y=0.18); ax.tick_params(labelsize=9)
    fig.suptitle(f"Gene-structure comparison: {la} vs {lb}", fontsize=15, color=NAVY, fontweight="bold")
    fig.tight_layout(rect=[0, 0, 1, 0.96])
    for ext in ("png", "svg"):
        fig.savefig(g.out_fig.replace(".png", f".{ext}"), dpi=300, bbox_inches="tight")
    print("figure ->", g.out_fig)


if __name__ == "__main__":
    main()
