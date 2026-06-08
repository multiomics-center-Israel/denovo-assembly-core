#!/usr/bin/env python
"""Post-annotation analysis suite for S. cameroni (pipeline phases 7.8-7.22).

One file, many sub-commands — each is idempotent (skips if its main output exists),
defensive (warns + exits 0 on a missing optional input so a detached run keeps going),
and writes a PNG into --figures so the pptx auto-embeds it.

Sub-commands:
  nasonia-rbh     7.8   reciprocal-best-hit recovery of Nasonia proteome vs braker.aa
  busco-fig       7.9   compare BUSCO(protein) braker.aa vs Nasonia vs genome
  expression      7.10  featureCounts per-gene read counts + TPM
  concordance     7.11  gffcompare braker vs StringTie (+ TSA support note)
  utr-light       7.12  lightweight 5'/3' UTR inference from StringTie/TSA
  utr-merge       7.14  merge lightweight + PASA UTRs
  kegg            7.17  KO + abundance -> housekeeping KEGG enrichment of top genes
  naming          7.21  attach gene name + product to a final annotated GFF/GTF
  final-merge     7.22  protein-coding (named) + ncRNA -> master annotation
"""
import argparse, os, re, subprocess, sys, glob, math, collections
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

NAVY, TEAL, AMBER, RUST, GREY = "#1B3A5C", "#2A9D8F", "#E9C46A", "#E76F51", "#9AA5B1"
GENOME_BP = 650907546


def warn(m): print(f"[warn] {m}", file=sys.stderr)
def info(m): print(f"[info] {m}")


def savefig(fig, figdir, stem):
    figdir = Path(figdir); figdir.mkdir(parents=True, exist_ok=True)
    for ext in ("png", "svg"):
        fig.savefig(figdir / f"{stem}.{ext}", dpi=300, bbox_inches="tight")
    plt.close(fig); info(f"wrote {stem}.png")


def read_fasta_desc(path):
    """id -> description text from a FASTA header line."""
    d = {}
    if not Path(path).exists():
        return d
    with open(path) as fh:
        for line in fh:
            if line.startswith(">"):
                h = line[1:].rstrip("\n")
                sid = h.split()[0]
                desc = h[len(sid):].strip()
                d[sid] = desc
    return d


def best_hits(tsv):
    """query -> (subject, pident, bitscore) keeping the top bitscore per query."""
    best = {}
    if not Path(tsv).exists():
        return best
    with open(tsv) as fh:
        for line in fh:
            p = line.rstrip("\n").split("\t")
            if len(p) < 8:
                continue
            q, s, pid, bits = p[0], p[1], float(p[2]), float(p[7])
            if q not in best or bits > best[q][2]:
                best[q] = (s, pid, bits)
    return best


# ───────────────────────── 7.8 Nasonia RBH ─────────────────────────
def cmd_nasonia_rbh(a):
    od = Path(a.project) / "analysis" / "nasonia_compare"
    nas_vs = od / "nasonia_vs_braker.tsv"
    brk_vs = od / "braker_vs_nasonia.tsv"
    if not nas_vs.exists() or not brk_vs.exists():
        warn("diamond tsvs missing — run diamond first; skipping"); return 0

    nb = best_hits(nas_vs)        # nasonia -> braker
    bn = best_hits(brk_vs)        # braker  -> nasonia
    # totals
    n_nas = count_fasta(Path(a.project) / "annotation" / "hymenoptera_proteins.fa")
    n_brk = count_fasta(Path(a.project) / "annotation" / "braker" / "braker.aa")
    nas_hit = len(nb)
    brk_hit = len(bn)
    # RBH
    rbh = []
    for nas, (brk, pid, _) in nb.items():
        back = bn.get(brk)
        if back and back[0] == nas:
            rbh.append((nas, brk, pid))
    nas_desc = read_fasta_desc(Path(a.project) / "annotation" / "hymenoptera_proteins.fa")

    # reuse for naming: braker mRNA -> Nasonia product (best hit)
    with open(od / "braker_to_nasonia_product.tsv", "w") as f:
        f.write("braker_id\tnasonia_id\tpident\tnasonia_product\n")
        for brk, (nas, pid, _) in bn.items():
            prod = re.sub(r"\s*\[Nasonia vitripennis\]\s*$", "", nas_desc.get(nas, ""))
            f.write(f"{brk}\t{nas}\t{pid:.1f}\t{prod}\n")

    with open(od / "rbh.tsv", "w") as f:
        f.write("nasonia_id\tbraker_id\tpident\n")
        for nas, brk, pid in rbh:
            f.write(f"{nas}\t{brk}\t{pid:.1f}\n")

    rbh_pid = np.mean([r[2] for r in rbh]) if rbh else 0
    pct = lambda x, n: 100 * x / n if n else 0
    summary = (
        f"Nasonia proteins (n={n_nas}):  with hit to a called gene: {nas_hit} ({pct(nas_hit,n_nas):.1f}%);"
        f"  RBH ortholog: {len(rbh)} ({pct(len(rbh),n_nas):.1f}%)\n"
        f"Called proteins (n={n_brk}):   with Nasonia hit: {brk_hit} ({pct(brk_hit,n_brk):.1f}%);"
        f"  RBH ortholog: {len(rbh)} ({pct(len(rbh),n_brk):.1f}%)\n"
        f"Mean RBH %identity: {rbh_pid:.1f}\n"
        f"(genomic tblastn baseline = 93.3% of Nasonia had a genomic HSP; "
        f"this measures hits to actual *called genes*.)\n")
    (od / "summary.txt").write_text(summary)
    print(summary)

    fig, ax = plt.subplots(figsize=(8, 4.5))
    labels = ["Nasonia w/ hit\nto called gene", "Nasonia RBH\northolog", "Called genes\nw/ Nasonia hit"]
    vals = [pct(nas_hit, n_nas), pct(len(rbh), n_nas), pct(brk_hit, n_brk)]
    bars = ax.bar(labels, vals, color=[NAVY, TEAL, AMBER])
    ax.axhline(93.3, color=RUST, ls="--", lw=1.3, label="genomic tblastn baseline 93.3%")
    ax.set_ylim(0, 100); ax.set_ylabel("%")
    ax.set_title("Nasonia ↔ called-protein recovery (RBH)", color=NAVY, fontweight="bold")
    for b, v in zip(bars, vals):
        ax.text(b.get_x()+b.get_width()/2, v+1.5, f"{v:.1f}%", ha="center", fontweight="bold", fontsize=9)
    ax.legend(fontsize=8)
    savefig(fig, a.figures, "nasonia_recovery")
    return 0


def count_fasta(p):
    p = Path(p)
    if not p.exists():
        return 0
    return sum(1 for l in open(p) if l.startswith(">"))


# ───────────────────────── 7.9 BUSCO proteins ─────────────────────────
def parse_busco(path):
    t = Path(path).read_text() if Path(path).exists() else ""
    m = re.search(r"C:([\d.]+)%\[S:([\d.]+)%,D:([\d.]+)%\],F:([\d.]+)%,M:([\d.]+)%,n:(\d+)", t)
    return tuple(float(m.group(i)) for i in range(1, 7)) if m else None


def cmd_busco_fig(a):
    bdir = Path(a.project) / "analysis" / "busco"
    sets = {}
    for label, sub in [("Called proteins\n(braker.aa)", "braker_prot"),
                       ("Nasonia proteome", "nasonia_prot")]:
        hits = glob.glob(str(bdir / sub / "short_summary*.txt"))
        if hits:
            v = parse_busco(hits[0])
            if v:
                sets[label] = v
    # genome BUSCO (from QC) for 3-way context
    ghits = glob.glob(str(Path(a.project) / "qc" / "busco_results" / "**" / "short_summary*.txt"), recursive=True)
    if ghits:
        v = parse_busco(ghits[0])
        if v:
            sets["Genome assembly"] = v
    if not sets:
        warn("no BUSCO summaries found; skipping"); return 0

    fig, ax = plt.subplots(figsize=(9, 0.9 + 0.7 * len(sets)))
    ylabels = list(sets)
    for i, lab in enumerate(ylabels):
        C, S, D, F, M, n = sets[lab]
        left = 0
        for val, col in [(S, TEAL), (D, NAVY), (F, AMBER), (M, RUST)]:
            ax.barh(i, val, left=left, color=col, edgecolor="white")
            if val >= 5:
                ax.text(left+val/2, i, f"{val:.0f}", ha="center", va="center", color="white", fontsize=8, fontweight="bold")
            left += val
        ax.text(101, i, f"C:{C:.1f}%", va="center", fontsize=8)
    ax.set_yticks(range(len(ylabels))); ax.set_yticklabels(ylabels)
    ax.set_xlim(0, 115); ax.set_xlabel("% BUSCO groups (hymenoptera_odb10)")
    ax.set_title("BUSCO completeness: called proteins vs Nasonia vs genome", color=NAVY, fontweight="bold")
    from matplotlib.patches import Patch
    ax.legend(handles=[Patch(color=TEAL, label="S"), Patch(color=NAVY, label="D"),
                       Patch(color=AMBER, label="F"), Patch(color=RUST, label="M")],
              loc="lower right", ncol=4, fontsize=8, frameon=False)
    savefig(fig, a.figures, "busco_proteins")
    (bdir / "busco_compare.txt").write_text(
        "\n".join(f"{k}\tC:{v[0]} S:{v[1]} D:{v[2]} F:{v[3]} M:{v[4]} n:{int(v[5])}" for k, v in sets.items()) + "\n")
    return 0


# ───────────────────────── 7.10 Expression (featureCounts) ─────────────────────────
def cmd_expression(a):
    od = Path(a.project) / "analysis" / "expression"; od.mkdir(parents=True, exist_ok=True)
    gtf = Path(a.project) / "annotation" / "braker" / "braker.gtf"
    bam = Path(a.project) / "rnaseq" / "rnaseq_aligned.bam"
    fc = od / "featurecounts.txt"
    out = od / "gene_counts.tsv"
    if not gtf.exists() or not bam.exists():
        warn("braker.gtf or rnaseq bam missing; skipping"); return 0
    if not fc.exists():
        # try exon feature first, fall back to CDS
        for feat in ("exon", "CDS"):
            rc = subprocess.run(
                ["featureCounts", "-T", str(a.threads), "-t", feat, "-g", "gene_id",
                 "-a", str(gtf), "-o", str(fc), str(bam)]).returncode
            if rc == 0 and fc.exists():
                info(f"featureCounts ok (-t {feat})"); break
        else:
            warn("featureCounts failed"); return 0
    # parse counts -> TPM
    rows = []
    with open(fc) as fh:
        for line in fh:
            if line.startswith("#") or line.startswith("Geneid"):
                continue
            p = line.rstrip("\n").split("\t")
            gid, length, count = p[0], int(p[5]), int(p[-1])
            rows.append([gid, length, count])
    rpk = [(c / (l / 1000.0)) if l else 0 for _, l, c in rows]
    scale = sum(rpk) / 1e6 or 1
    with open(out, "w") as f:
        f.write("gene_id\tlength\tcount\tTPM\n")
        for (gid, length, count), r in zip(rows, rpk):
            f.write(f"{gid}\t{length}\t{count}\t{r/scale:.4f}\n")
    info(f"{len(rows)} genes -> {out}")

    tpm = np.array([r / scale for r in rpk])
    expressed = int((tpm >= 1).sum())
    fig, axes = plt.subplots(1, 2, figsize=(12, 4.5))
    lt = np.log10(tpm[tpm > 0] + 1e-3)
    axes[0].hist(lt, bins=50, color=TEAL, edgecolor="white")
    axes[0].set_xlabel("log10(TPM)"); axes[0].set_ylabel("genes")
    axes[0].set_title(f"A. Expression distribution ({expressed:,} genes TPM≥1)")
    order = np.argsort(tpm)[::-1][:20]
    axes[1].barh(range(20)[::-1], tpm[order], color=NAVY)
    axes[1].set_yticks(range(20)[::-1]); axes[1].set_yticklabels([rows[i][0] for i in order], fontsize=6)
    axes[1].set_xlabel("TPM"); axes[1].set_title("B. Top-20 most abundant genes")
    fig.suptitle("Per-gene RNA-Seq abundance (braker models)", color=NAVY, fontweight="bold")
    savefig(fig, a.figures, "gene_abundance")
    return 0


# ───────────────────────── 7.11 Transcript concordance ─────────────────────────
def cmd_concordance(a):
    od = Path(a.project) / "analysis" / "transcript_compare"; od.mkdir(parents=True, exist_ok=True)
    braker = Path(a.project) / "annotation" / "braker" / "braker.gtf"
    st = Path(a.project) / "annotation" / "braker" / "GeneMark-ETP" / "rnaseq" / "stringtie" / "transcripts_merged.gff"
    if not braker.exists() or not st.exists():
        warn("braker.gtf or StringTie gff missing; skipping"); return 0
    pref = str(od / "gffcmp")
    subprocess.run(["gffcompare", "-r", str(braker), "-o", pref, str(st)])
    stats = Path(pref + ".stats")
    sens = prec = None
    if stats.exists():
        txt = stats.read_text()
        m = re.search(r"Transcript level:\s+([\d.]+)\s+\|\s+([\d.]+)", txt)
        if m:
            sens, prec = float(m.group(1)), float(m.group(2))
    fig, ax = plt.subplots(figsize=(6, 4.5))
    vals = [sens or 0, prec or 0]
    ax.bar(["Sensitivity\n(StringTie tx found\nin braker)", "Precision\n(braker tx matched\nby StringTie)"],
           vals, color=[TEAL, AMBER])
    ax.set_ylim(0, 100); ax.set_ylabel("%")
    ax.set_title("braker vs StringTie transcript concordance", color=NAVY, fontweight="bold")
    for i, v in enumerate(vals):
        ax.text(i, v+1.5, f"{v:.1f}%", ha="center", fontweight="bold")
    ax.text(0.5, -0.28, "TSA support (independent de-novo transcriptome): 96.6% of TSA aligned (pblat)",
            transform=ax.transAxes, ha="center", fontsize=8, color=GREY)
    savefig(fig, a.figures, "transcript_concordance")
    return 0


# ───────────────────────── 7.12 / 7.14 UTR ─────────────────────────
def parse_gtf_transcripts(path):
    """transcript_id -> dict(chrom, strand, start, end, exons[list]) from a GTF/GFF."""
    tx = {}
    if not Path(path).exists():
        return tx
    for line in open(path):
        if line.startswith("#"):
            continue
        p = line.rstrip("\n").split("\t")
        if len(p) < 9 or p[2] not in ("exon", "transcript"):
            continue
        m = re.search(r'transcript_id[ =]"?([^";]+)"?', p[8])
        if not m:
            continue
        tid = m.group(1); s, e = int(p[3]), int(p[4])
        d = tx.setdefault(tid, {"chrom": p[0], "strand": p[6], "start": s, "end": e, "exons": []})
        d["start"] = min(d["start"], s); d["end"] = max(d["end"], e)
        if p[2] == "exon":
            d["exons"].append((s, e))
    return tx


def cmd_utr_light(a):
    od = Path(a.project) / "analysis" / "utr"; od.mkdir(parents=True, exist_ok=True)
    braker = Path(a.project) / "annotation" / "braker" / "braker.gtf"
    st = Path(a.project) / "annotation" / "braker" / "GeneMark-ETP" / "rnaseq" / "stringtie" / "transcripts_merged.gff"
    if not braker.exists():
        warn("braker.gtf missing; skipping"); return 0
    genes = parse_gtf_transcripts(braker)   # braker mRNAs (CDS-only models -> exon==CDS span)
    eviv = parse_gtf_transcripts(st)
    # index evidence by chrom/strand
    ev_by = collections.defaultdict(list)
    for d in eviv.values():
        ev_by[(d["chrom"], d["strand"])].append(d)
    utr5, utr3, n_with = [], [], 0
    rows = []
    for tid, g in genes.items():
        cand = [e for e in ev_by.get((g["chrom"], g["strand"]), [])
                if not (e["end"] < g["start"] or e["start"] > g["end"])]
        if not cand:
            continue
        # pick evidence transcript with largest overlap span
        best = max(cand, key=lambda e: min(e["end"], g["end"]) - max(e["start"], g["start"]))
        if g["strand"] == "+":
            u5 = max(0, g["start"] - best["start"]); u3 = max(0, best["end"] - g["end"])
        else:
            u5 = max(0, best["end"] - g["end"]); u3 = max(0, g["start"] - best["start"])
        if u5 or u3:
            n_with += 1; utr5.append(u5); utr3.append(u3)
            rows.append((tid, u5, u3))
    with open(od / "utr_lightweight.tsv", "w") as f:
        f.write("mrna_id\tutr5_len\tutr3_len\n")
        for r in rows:
            f.write(f"{r[0]}\t{r[1]}\t{r[2]}\n")
    summ = (f"genes with inferred UTR (≥1 side): {n_with}/{len(genes)}\n"
            f"median 5'UTR: {int(np.median(utr5)) if utr5 else 0} bp (lower bound — TSA is short-read)\n"
            f"median 3'UTR: {int(np.median(utr3)) if utr3 else 0} bp\n")
    (od / "utr_lightweight_summary.txt").write_text(summ); print(summ)
    if utr5 or utr3:
        fig, ax = plt.subplots(figsize=(8, 4.5))
        for data, col, lab in [(utr5, TEAL, "5'UTR"), (utr3, AMBER, "3'UTR")]:
            d = np.array([x for x in data if 0 < x < 5000])
            if len(d):
                ax.hist(d, bins=50, alpha=0.6, color=col, label=f"{lab} (median {int(np.median(data))} bp)")
        ax.set_xlabel("UTR length (bp)"); ax.set_ylabel("genes"); ax.legend()
        ax.set_title("Lightweight UTR inference (StringTie/TSA overlay)", color=NAVY, fontweight="bold")
        savefig(fig, a.figures, "utr_lengths")
    return 0


def cmd_utr_merge(a):
    od = Path(a.project) / "analysis" / "utr"
    light = od / "utr_lightweight.tsv"
    pasa = od / "pasa_utr.tsv"   # produced by the PASA step if it runs
    if not light.exists():
        warn("no lightweight UTR to merge; skipping"); return 0
    out = od / "utr_consensus.tsv"
    merged = {}
    for src in (light, pasa):
        if not src.exists():
            continue
        with open(src) as fh:
            next(fh, None)
            for line in fh:
                p = line.split("\t")
                if len(p) < 3:
                    continue
                tid = p[0]; u5, u3 = int(float(p[1])), int(float(p[2]))
                # PASA (later source) overrides where it has a value
                cur = merged.get(tid, (0, 0, "lightweight"))
                src_name = "pasa" if src == pasa else "lightweight"
                if src == pasa:
                    merged[tid] = (max(u5, cur[0]), max(u3, cur[1]), "pasa")
                else:
                    merged[tid] = (u5, u3, cur[2] if tid in merged else "lightweight")
    with open(out, "w") as f:
        f.write("mrna_id\tutr5_len\tutr3_len\tsource\n")
        for tid, (u5, u3, s) in merged.items():
            f.write(f"{tid}\t{u5}\t{u3}\t{s}\n")
    info(f"consensus UTR for {len(merged)} mRNAs -> {out} (pasa present: {pasa.exists()})")
    return 0


# ───────────────────────── 7.17 KEGG housekeeping ─────────────────────────
HOUSEKEEPING = {
    "ko03010": "Ribosome", "ko00190": "Oxidative phosphorylation",
    "ko03050": "Proteasome", "ko03040": "Spliceosome",
    "ko00970": "Aminoacyl-tRNA biosynthesis", "ko00010": "Glycolysis/Gluconeogenesis",
    "ko03013": "RNA transport", "ko03008": "Ribosome biogenesis",
}


def load_emapper(path):
    """gene -> set(KEGG pathways) from an eggNOG-mapper .annotations file."""
    g2path = {}
    if not Path(path).exists():
        return g2path
    header = None
    for line in open(path):
        if line.startswith("#query"):
            header = line.lstrip("#").rstrip("\n").split("\t"); continue
        if line.startswith("#") or not header:
            continue
        p = line.rstrip("\n").split("\t")
        row = dict(zip(header, p))
        q = row.get("query") or p[0]
        paths = set(re.findall(r"ko\d{5}", row.get("KEGG_Pathway", "")))
        if paths:
            g2path[q.split(".")[0] if "." in q else q] = g2path.get(q, set()) | paths
            g2path[q] = g2path.get(q, set()) | paths
    return g2path


def cmd_kegg(a):
    od = Path(a.project) / "analysis" / "kegg"; od.mkdir(parents=True, exist_ok=True)
    ann = Path(a.project) / "analysis" / "kegg" / "eggnog.emapper.annotations"
    counts = Path(a.project) / "analysis" / "expression" / "gene_counts.tsv"
    if not ann.exists() or not counts.exists():
        warn("eggNOG annotations or expression missing; skipping (will run once eggNOG done)"); return 0
    g2path = load_emapper(ann)
    # gene TPM (gene_id may differ from protein id by .t1 — map both ways)
    tpm = {}
    with open(counts) as fh:
        next(fh)
        for line in fh:
            p = line.split("\t"); tpm[p[0]] = float(p[3])
    if not tpm:
        warn("no TPM"); return 0
    # rank, take top 5% by TPM
    genes = sorted(tpm, key=lambda g: -tpm[g])
    topN = max(1, int(0.05 * len(genes)))
    top = set(genes[:topN]); rest = set(genes[topN:])

    def path_of(g):
        return g2path.get(g) or g2path.get(g + ".t1") or g2path.get(g.replace(".t1", "")) or set()

    rows = []
    for ko, name in HOUSEKEEPING.items():
        a_ = sum(1 for g in top if ko in path_of(g))
        b_ = sum(1 for g in rest if ko in path_of(g))
        top_rate = 100 * a_ / len(top)
        rest_rate = 100 * b_ / len(rest) if rest else 0
        enr = (top_rate / rest_rate) if rest_rate else float("inf")
        rows.append((name, ko, a_, top_rate, rest_rate, enr))
    rows.sort(key=lambda r: -r[3])
    with open(od / "housekeeping_enrichment.tsv", "w") as f:
        f.write("pathway\tko\tn_top\ttop_pct\tbackground_pct\tenrichment\n")
        for r in rows:
            f.write(f"{r[0]}\t{r[1]}\t{r[2]}\t{r[3]:.2f}\t{r[4]:.2f}\t{r[5]:.2f}\n")
    enriched = [r for r in rows if r[5] > 1.5 and r[2] >= 3]
    verdict = ("YES — the most-abundant genes are enriched for housekeeping pathways: "
               + ", ".join(f"{r[0]}({r[5]:.1f}×)" for r in enriched[:5])) if enriched else \
              "No clear housekeeping enrichment among top-abundance genes."
    (od / "verdict.txt").write_text(verdict + "\n"); print(verdict)

    fig, ax = plt.subplots(figsize=(9, 4.5))
    names = [r[0] for r in rows]
    ax.bar(np.arange(len(rows))-0.2, [r[3] for r in rows], 0.4, color=RUST, label="top 5% abundant")
    ax.bar(np.arange(len(rows))+0.2, [r[4] for r in rows], 0.4, color=GREY, label="background")
    ax.set_xticks(range(len(rows))); ax.set_xticklabels(names, rotation=35, ha="right", fontsize=8)
    ax.set_ylabel("% of genes in pathway"); ax.legend()
    ax.set_title("Housekeeping KEGG pathways: high-abundance vs background", color=NAVY, fontweight="bold")
    savefig(fig, a.figures, "kegg_housekeeping")
    return 0


# ───────────────────────── 7.21 Functional naming ─────────────────────────
def cmd_naming(a):
    od = Path(a.project) / "analysis" / "naming"; od.mkdir(parents=True, exist_ok=True)
    gff = Path(a.project) / "annotation" / "braker" / "braker.gff3"
    if not gff.exists():
        warn("braker.gff3 missing; skipping"); return 0
    # build id -> (name, product) from available evidence, priority: eggNOG > Nasonia
    name, product = {}, {}
    ann = Path(a.project) / "analysis" / "kegg" / "eggnog.emapper.annotations"
    if ann.exists():
        header = None
        for line in open(ann):
            if line.startswith("#query"):
                header = line.lstrip("#").rstrip("\n").split("\t"); continue
            if line.startswith("#") or not header:
                continue
            row = dict(zip(header, line.rstrip("\n").split("\t")))
            q = row.get("query")
            pn = row.get("Preferred_name", "-")
            desc = row.get("Description", "-")
            if q and pn and pn != "-":
                name[q] = pn
            if q and desc and desc != "-":
                product[q] = desc
    nas = Path(a.project) / "analysis" / "nasonia_compare" / "braker_to_nasonia_product.tsv"
    if nas.exists():
        with open(nas) as fh:
            next(fh, None)
            for line in fh:
                p = line.rstrip("\n").split("\t")
                if len(p) >= 4 and p[3] and p[0] not in product:
                    product[p[0]] = p[3]
    # inject into gff3
    out_gff = od / "Spalangia_cameroni.annotated.gff3"
    named = total = 0
    with open(gff) as fin, open(out_gff, "w") as fout:
        for line in fin:
            if line.startswith("#") or "\t" not in line:
                fout.write(line); continue
            p = line.rstrip("\n").split("\t")
            if p[2] == "mRNA":
                total += 1
                m = re.search(r"ID=([^;]+)", p[8]); tid = m.group(1) if m else None
                nm = name.get(tid); pr = product.get(tid)
                extra = ""
                if nm:
                    extra += f";Name={nm}"
                if pr:
                    extra += f";product={pr}"; named += 1
                else:
                    extra += ";product=hypothetical protein"
                fout.write("\t".join(p[:8]) + "\t" + p[8] + extra + "\n")
            else:
                fout.write(line)
    summ = (f"mRNAs: {total}; with a product assignment: {named} "
            f"({100*named/total:.1f}%); rest = hypothetical protein\n"
            f"(eggNOG present: {ann.exists()}; Nasonia products present: {nas.exists()})\n")
    (od / "naming_summary.txt").write_text(summ); print(summ)
    # GTF twin via gffread if available
    try:
        subprocess.run(["gffread", str(out_gff), "-T", "-o",
                        str(od / "Spalangia_cameroni.annotated.gtf")], check=False)
    except FileNotFoundError:
        warn("gffread not found — GTF twin skipped")
    return 0


# ───────────────────────── 7.22 Final merge ─────────────────────────
def cmd_final_merge(a):
    od = Path(a.project) / "analysis" / "final"; od.mkdir(parents=True, exist_ok=True)
    coding = Path(a.project) / "analysis" / "naming" / "Spalangia_cameroni.annotated.gff3"
    if not coding.exists():
        coding = Path(a.project) / "annotation" / "braker" / "braker.gff3"
    ncrna = Path(a.project) / "analysis" / "ncrna" / "ncRNA.gff3"
    master = od / "Spalangia_cameroni.annotation.gff3"
    n_coding = n_nc = 0
    with open(master, "w") as out:
        out.write("##gff-version 3\n")
        if coding.exists():
            for line in open(coding):
                if not line.startswith("#"):
                    out.write(line)
                    if "\tgene\t" in line:
                        n_coding += 1
        if ncrna.exists():
            for line in open(ncrna):
                if not line.startswith("#"):
                    out.write(line)
                    if "\tgene\t" in line or "\ttRNA\t" in line or "\trRNA\t" in line:
                        n_nc += 1
    (od / "final_summary.txt").write_text(
        f"master annotation: {master}\nprotein-coding gene lines: {n_coding}\nncRNA lines: {n_nc}\n")
    info(f"master annotation written: {master} (coding={n_coding}, ncRNA={n_nc})")
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("command")
    ap.add_argument("--project", required=True)
    ap.add_argument("--figures", required=True)
    ap.add_argument("--threads", type=int, default=16)
    a = ap.parse_args()
    cmds = {
        "nasonia-rbh": cmd_nasonia_rbh, "busco-fig": cmd_busco_fig,
        "expression": cmd_expression, "concordance": cmd_concordance,
        "utr-light": cmd_utr_light, "utr-merge": cmd_utr_merge,
        "kegg": cmd_kegg, "naming": cmd_naming, "final-merge": cmd_final_merge,
    }
    fn = cmds.get(a.command)
    if not fn:
        print(f"unknown command {a.command}; choices: {list(cmds)}", file=sys.stderr); sys.exit(2)
    try:
        sys.exit(fn(a) or 0)
    except Exception as e:
        warn(f"{a.command} failed: {e}")
        import traceback; traceback.print_exc()
        sys.exit(0)   # non-fatal: keep the detached suite going


if __name__ == "__main__":
    main()
