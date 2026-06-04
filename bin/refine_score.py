#!/usr/bin/env python
"""AED-like per-gene evidence scoring + cross-stage upgrade summary.

AED (annotation edit distance) measures how far a gene model is from its supporting
evidence (0 = fully supported, 1 = unsupported). True AED needs exon-level
concordance; here we use a faithful proxy per gene:

  support = max( frac of CDS bases covered by RNA-seq reads,
                 best Nasonia-protein blastp query-coverage,
                 frac of CDS bases overlapped by transcript/PASA alignments )
  AED_like = 1 - support

Subcommands:
  aed      per-gene AED-like from bedtools-coverage + diamond tables
  summary  aggregate BUSCO + counts + AED across pipeline stages -> table + figure
"""
import argparse, re, sys, glob, statistics
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from refine_rescue import gene_table  # noqa: E402


def _agg_cov(path):
    """bedtools coverage -a cds.bed -b X  ->  gene -> covered_frac (bases_cov/len)."""
    cov_bases, tot = defaultdict(int), defaultdict(int)
    if not path or not Path(path).exists():
        return {}
    with open(path) as fh:
        for line in fh:
            f = line.rstrip("\n").split("\t")
            if len(f) < 10:
                continue
            g = f[3]
            cov_bases[g] += int(f[7])   # bases covered (>=1)
            tot[g] += int(f[8])         # interval length
    return {g: (cov_bases[g] / tot[g] if tot[g] else 0.0) for g in tot}


def _best_qcov(path):
    """diamond outfmt6 with qcovhsp as the LAST field -> gene -> best qcov fraction.
    Query ids are transcript ids (g123.t1); collapse to gene by stripping .tN."""
    best = defaultdict(float)
    if not path or not Path(path).exists():
        return best
    with open(path) as fh:
        for line in fh:
            f = line.rstrip("\n").split("\t")
            if len(f) < 2:
                continue
            g = re.sub(r"\.t\d+$", "", f[0])
            try:
                q = float(f[-1]) / 100.0
            except ValueError:
                continue
            if q > best[g]:
                best[g] = q
    return best


def cmd_aed(a):
    rna = _agg_cov(a.cov)
    tx = _agg_cov(a.txcov)
    prot = _best_qcov(a.diamond)
    genes = [g.split("\t")[0] for g in Path(a.genelen).read_text().splitlines()[1:] if g]
    aeds = []
    with open(a.out, "w") as out:
        out.write("gene_id\trnaseq_frac\tprotein_qcov\ttranscript_frac\tsupport\taed_like\n")
        for g in genes:
            r, p, t = rna.get(g, 0.0), prot.get(g, 0.0), tx.get(g, 0.0)
            sup = max(r, p, t)
            aed = round(1.0 - sup, 4)
            aeds.append(aed)
            out.write(f"{g}\t{r:.3f}\t{p:.3f}\t{t:.3f}\t{sup:.3f}\t{aed}\n")
    if aeds:
        supported = sum(1 for x in aeds if x < 0.5)
        sys.stderr.write(
            f"[aed] {len(aeds)} genes  median_AED={statistics.median(aeds):.3f}  "
            f"mean_AED={statistics.mean(aeds):.3f}  %AED<0.5={100*supported/len(aeds):.1f}\n")


def _parse_busco(busco_dir):
    hits = glob.glob(f"{busco_dir}/short_summary*.txt") + \
           glob.glob(f"{busco_dir}/**/short_summary*.txt", recursive=True)
    for h in hits:
        m = re.search(r"C:([\d.]+)%\[S:([\d.]+)%,D:([\d.]+)%\],F:([\d.]+)%,M:([\d.]+)%,n:(\d+)",
                      Path(h).read_text())
        if m:
            return [float(m.group(i)) for i in range(1, 6)] + [int(m.group(6))]
    return None


def _counts(gtf):
    if not gtf or not Path(gtf).exists():
        return None
    g = gene_table(gtf)
    n_tx = sum(d["n_tx"] for d in g.values())
    mono = sum(1 for d in g.values() if d["max_cds"] <= 1)
    return dict(genes=len(g), tx=n_tx, mono=mono)


def cmd_summary(a):
    # manifest lines: label \t busco_dir \t aed_tsv \t gtf
    rows = []
    for line in Path(a.manifest).read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        label, busco_dir, aed_tsv, gtf = (line.split("\t") + ["", "", "", ""])[:4]
        b = _parse_busco(busco_dir) if busco_dir else None
        c = _counts(gtf) if gtf else None
        med = pct = None
        if aed_tsv and Path(aed_tsv).exists():
            vals = [float(x.split("\t")[-1]) for x in Path(aed_tsv).read_text().splitlines()[1:] if x]
            if vals:
                med = statistics.median(vals)
                pct = 100 * sum(1 for v in vals if v < 0.5) / len(vals)
        rows.append((label, c, b, med, pct))

    # write table
    with open(a.out_tsv, "w") as out:
        out.write("stage\tgenes\ttranscripts\tmono_exonic\tBUSCO_C\tBUSCO_S\tBUSCO_D\t"
                  "BUSCO_F\tBUSCO_M\tmedian_AED\tpct_AED_lt_0.5\n")
        for label, c, b, med, pct in rows:
            cg = c["genes"] if c else ""
            ct = c["tx"] if c else ""
            cm = c["mono"] if c else ""
            bb = b if b else ["", "", "", "", "", ""]
            out.write(f"{label}\t{cg}\t{ct}\t{cm}\t{bb[0]}\t{bb[1]}\t{bb[2]}\t{bb[3]}\t{bb[4]}\t"
                      f"{'' if med is None else round(med,3)}\t{'' if pct is None else round(pct,1)}\n")
    sys.stderr.write(f"[summary] wrote {a.out_tsv} ({len(rows)} stages)\n")

    # figure: BUSCO completeness per stage (stacked S/D/F/M)
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        labels = [r[0] for r in rows if r[2]]
        B = [r[2] for r in rows if r[2]]
        if labels:
            S = [b[1] for b in B]; D = [b[2] for b in B]; F = [b[3] for b in B]; M = [b[4] for b in B]
            y = range(len(labels))
            fig, ax = plt.subplots(figsize=(9, 0.9 + 0.7 * len(labels)))
            ax.barh(y, S, color="#2a9d8f", label="S")
            ax.barh(y, D, left=S, color="#264653", label="D")
            ax.barh(y, F, left=[s+d for s, d in zip(S, D)], color="#e9c46a", label="F")
            ax.barh(y, M, left=[s+d+f for s, d, f in zip(S, D, F)], color="#bc4749", label="M")
            ax.set_yticks(list(y)); ax.set_yticklabels(labels)
            ax.set_xlim(0, 115); ax.set_xlabel("% BUSCO groups (hymenoptera_odb10)")
            ax.set_title("Gene-set BUSCO completeness across refinement stages", fontweight="bold")
            ax.legend(loc="lower right", ncol=4, fontsize=8, frameon=False)
            fig.tight_layout(); fig.savefig(a.out_fig, dpi=150)
            sys.stderr.write(f"[summary] wrote {a.out_fig}\n")
    except Exception as e:  # noqa: BLE001
        sys.stderr.write(f"[summary] figure skipped: {e}\n")


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    a1 = sub.add_parser("aed")
    a1.add_argument("--cov"); a1.add_argument("--txcov"); a1.add_argument("--diamond")
    a1.add_argument("--genelen", required=True); a1.add_argument("--out", required=True)
    a1.set_defaults(func=cmd_aed)
    a2 = sub.add_parser("summary")
    a2.add_argument("--manifest", required=True); a2.add_argument("--out-tsv", dest="out_tsv", required=True)
    a2.add_argument("--out-fig", dest="out_fig", required=True)
    a2.set_defaults(func=cmd_summary)
    a = p.parse_args(); a.func(a)


if __name__ == "__main__":
    main()
