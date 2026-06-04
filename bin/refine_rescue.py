#!/usr/bin/env python
"""Evidence-based rescue of single-exon genes.

A genome >300 Mb makes BRAKER/TSEBRA apply --filter_single_exon_genes, which drops
*all* mono-exonic models regardless of support. That discards real single-exon genes
(many are genuinely intronless and/or expressed). Here we instead keep a single-exon
gene when it has independent evidence: RNA-seq read coverage over its CDS OR a
Nasonia protein homolog. Multi-exon genes are always kept.

Subcommands (driven by run_model_refinement.sh):
  classify  GTF -> genes.tsv, single_exon.bed, single_exon_gene_ids.txt, multi_exon_gene_ids.txt
  decide    coverage.tsv + diamond.tsv -> rescue_report.tsv, kept_gene_ids.txt
  subset    GTF + kept_gene_ids.txt -> filtered.gtf
"""
import argparse, re, sys
from collections import defaultdict

TX_RE = re.compile(r'transcript_id "([^"]+)"')
GN_RE = re.compile(r'gene_id "([^"]+)"')


def _ids(col9):
    """Return (transcript_id, gene_id) from a GTF attribute column, tolerating
    both quoted (CDS/exon lines) and bare (gene/transcript feature lines) forms."""
    tx = TX_RE.search(col9)
    gn = GN_RE.search(col9)
    return (tx.group(1) if tx else None, gn.group(1) if gn else None)


def parse_cds(gtf):
    """transcript -> list of (chrom, start, end, strand); transcript -> gene."""
    tx_cds = defaultdict(list)
    tx_gene = {}
    with open(gtf) as fh:
        for line in fh:
            if line.startswith("#") or not line.strip():
                continue
            f = line.rstrip("\n").split("\t")
            if len(f) < 9 or f[2] != "CDS":
                continue
            tx, gn = _ids(f[8])
            if tx is None:
                continue
            tx_cds[tx].append((f[0], int(f[3]), int(f[4]), f[6]))
            if gn:
                tx_gene[tx] = gn
    return tx_cds, tx_gene


def gene_table(gtf):
    """gene_id -> dict(chrom,start,end,strand,max_cds,n_tx, rep_tx, rep_cds_iv)."""
    tx_cds, tx_gene = parse_cds(gtf)
    genes = {}
    # group transcripts by gene
    g_tx = defaultdict(list)
    for tx in tx_cds:
        g_tx[tx_gene.get(tx, tx)].append(tx)
    for gn, txs in g_tx.items():
        max_cds = 0
        rep_tx, rep_len, rep_iv = None, -1, None
        chrom = strand = None
        gstart, gend = None, None
        for tx in txs:
            cds = sorted(tx_cds[tx], key=lambda x: x[1])
            n = len(cds)
            tlen = sum(e - s + 1 for _, s, e, _ in cds)
            chrom, strand = cds[0][0], cds[0][3]
            lo, hi = cds[0][1], cds[-1][2]
            gstart = lo if gstart is None else min(gstart, lo)
            gend = hi if gend is None else max(gend, hi)
            if n > max_cds:
                max_cds = n
            if tlen > rep_len:               # representative = longest CDS transcript
                rep_len, rep_tx = tlen, tx
                rep_iv = (cds[0][0], cds[0][1], cds[-1][2], cds[0][3])
        genes[gn] = dict(chrom=chrom, start=gstart, end=gend, strand=strand,
                         max_cds=max_cds, n_tx=len(txs), rep_tx=rep_tx, rep_iv=rep_iv)
    return genes


def cmd_classify(a):
    genes = gene_table(a.gtf)
    single, multi = [], []
    with open(a.out_genes, "w") as gt, open(a.out_bed, "w") as bed:
        gt.write("gene_id\tchrom\tstart\tend\tstrand\tmax_cds_exons\tn_transcripts\n")
        for gn, d in sorted(genes.items()):
            gt.write(f"{gn}\t{d['chrom']}\t{d['start']}\t{d['end']}\t{d['strand']}"
                     f"\t{d['max_cds']}\t{d['n_tx']}\n")
            if d["max_cds"] <= 1:
                single.append(gn)
                c, s, e, st = d["rep_iv"]
                bed.write(f"{c}\t{s-1}\t{e}\t{gn}\t.\t{st}\n")  # BED 0-based start
            else:
                multi.append(gn)
    with open(a.out_single_ids, "w") as fh:
        fh.write("\n".join(single) + ("\n" if single else ""))
    with open(a.out_multi_ids, "w") as fh:
        fh.write("\n".join(multi) + ("\n" if multi else ""))
    sys.stderr.write(f"[classify] {len(genes)} genes: {len(multi)} multi-exon, "
                     f"{len(single)} single-exon candidates\n")


def cmd_decide(a):
    # coverage.tsv from `bedtools coverage -a single_exon.bed -b bam`:
    #   chrom start end gene . strand  n_reads  n_bases_cov  region_len  frac_cov
    cov = {}
    with open(a.coverage) as fh:
        for line in fh:
            f = line.rstrip("\n").split("\t")
            if len(f) < 10:
                continue
            cov[f[3]] = (int(f[6]), float(f[9]))   # gene -> (n_reads, frac_cov)
    # diamond.tsv (outfmt6): qseqid = protein id (transcript id) -> map to gene by strip .tN
    prot_hit = set()
    try:
        with open(a.diamond) as fh:
            for line in fh:
                q = line.split("\t", 1)[0]
                prot_hit.add(re.sub(r"\.t\d+$", "", q))
                prot_hit.add(q)
    except FileNotFoundError:
        pass
    single = [g for g in open(a.single_ids).read().split("\n") if g]
    multi = [g for g in open(a.multi_ids).read().split("\n") if g]
    kept_single = []
    with open(a.report, "w") as rep:
        rep.write("gene_id\tn_reads\tfrac_cds_covered\trnaseq_support\tprotein_support\trescued\n")
        for g in single:
            nr, fc = cov.get(g, (0, 0.0))
            rna = (fc >= a.min_frac) or (nr >= a.min_reads)
            prot = (g in prot_hit)
            keep = rna or prot
            if keep:
                kept_single.append(g)
            rep.write(f"{g}\t{nr}\t{fc:.3f}\t{int(rna)}\t{int(prot)}\t{int(keep)}\n")
    kept = multi + kept_single
    with open(a.kept_ids, "w") as fh:
        fh.write("\n".join(kept) + ("\n" if kept else ""))
    sys.stderr.write(
        f"[decide] single-exon: {len(single)} candidates -> rescued {len(kept_single)} "
        f"(dropped {len(single)-len(kept_single)}). Final gene set: {len(kept)} "
        f"(= {len(multi)} multi + {len(kept_single)} single)\n")


def cmd_subset(a):
    keep = set(g for g in open(a.kept_ids).read().split("\n") if g)
    n_in = n_out = 0
    with open(a.gtf) as fh, open(a.out, "w") as out:
        for line in fh:
            if line.startswith("#") or not line.strip():
                out.write(line)
                continue
            f = line.split("\t")
            if len(f) < 9:
                continue
            n_in += 1
            _, gn = _ids(f[8])
            if gn in keep:
                out.write(line)
                n_out += 1
    sys.stderr.write(f"[subset] wrote {n_out}/{n_in} feature lines for {len(keep)} genes\n")


def parse_feats(gtf, types=("CDS", "exon")):
    """transcript -> {type: [(chrom,start,end,strand,frame)]}, and transcript->gene."""
    tx_f = defaultdict(lambda: defaultdict(list))
    tx_gene = {}
    with open(gtf) as fh:
        for line in fh:
            if line.startswith("#") or not line.strip():
                continue
            f = line.rstrip("\n").split("\t")
            if len(f) < 9 or f[2] not in types:
                continue
            tx, gn = _ids(f[8])
            if tx is None:
                continue
            tx_f[tx][f[2]].append((f[0], int(f[3]), int(f[4]), f[6], f[7]))
            if gn:
                tx_gene[tx] = gn
    return tx_f, tx_gene


def cmd_gff3(a):
    """Emit a properly grouped gene/mRNA/exon/CDS GFF3 from a BRAKER/TSEBRA GTF.
    The GTF carries grouping only in gene_id/transcript_id attributes (no gene
    feature lines), which gffread flattens; this rebuilds explicit gene+mRNA
    records so downstream tools (funannotate, compare) read it correctly."""
    tx_f, tx_gene = parse_feats(a.gtf)
    g_tx = defaultdict(list)
    for tx in tx_f:
        g_tx[tx_gene.get(tx, tx)].append(tx)
    src = "refine"
    with open(a.out, "w") as out:
        out.write("##gff-version 3\n")
        for gn, txs in g_tx.items():
            allf = [iv for tx in txs for t in ("exon", "CDS") for iv in tx_f[tx][t]]
            chrom = allf[0][0]; strand = allf[0][3]
            gstart = min(iv[1] for iv in allf); gend = max(iv[2] for iv in allf)
            out.write(f"{chrom}\t{src}\tgene\t{gstart}\t{gend}\t.\t{strand}\t.\tID={gn}\n")
            for tx in txs:
                exons = sorted(tx_f[tx]["exon"] or tx_f[tx]["CDS"], key=lambda x: x[1])
                cds = sorted(tx_f[tx]["CDS"], key=lambda x: x[1])
                tstart = min(e[1] for e in exons); tend = max(e[2] for e in exons)
                out.write(f"{chrom}\t{src}\tmRNA\t{tstart}\t{tend}\t.\t{strand}\t.\tID={tx};Parent={gn}\n")
                for i, (c, s, e, st, fr) in enumerate(exons, 1):
                    out.write(f"{c}\t{src}\texon\t{s}\t{e}\t.\t{st}\t.\tID={tx}.exon{i};Parent={tx}\n")
                for i, (c, s, e, st, fr) in enumerate(cds, 1):
                    out.write(f"{c}\t{src}\tCDS\t{s}\t{e}\t.\t{st}\t{fr if fr in '012' else '0'}\tID={tx}.cds;Parent={tx}\n")
    sys.stderr.write(f"[gff3] {len(g_tx)} genes, {sum(len(v) for v in g_tx.values())} transcripts -> {a.out}\n")


def cmd_cdsbed(a):
    """Emit every CDS segment (BED6, name=gene_id) + a gene length table, for
    per-gene evidence scoring (AED-like)."""
    tx_cds, tx_gene = parse_cds(a.gtf)
    glen = defaultdict(int)
    with open(a.out_bed, "w") as bed:
        for tx, cds in tx_cds.items():
            gn = tx_gene.get(tx, tx)
            for c, s, e, st in cds:
                bed.write(f"{c}\t{s-1}\t{e}\t{gn}\t.\t{st}\n")
    # gene CDS length = from representative (longest) transcript to avoid double counting isoforms
    genes = gene_table(a.gtf)
    with open(a.out_len, "w") as fh:
        fh.write("gene_id\tcds_len\trep_tx\n")
        for gn, d in genes.items():
            rep = d["rep_tx"]
            ln = sum(e - s + 1 for _, s, e, _ in tx_cds.get(rep, []))
            fh.write(f"{gn}\t{ln}\t{rep}\n")
    sys.stderr.write(f"[cdsbed] {len(genes)} genes\n")


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    gf = sub.add_parser("gff3"); gf.add_argument("--gtf", required=True); gf.add_argument("--out", required=True)
    gf.set_defaults(func=cmd_gff3)
    cb = sub.add_parser("cdsbed"); cb.add_argument("--gtf", required=True)
    cb.add_argument("--out-bed", dest="out_bed", required=True)
    cb.add_argument("--out-len", dest="out_len", required=True)
    cb.set_defaults(func=cmd_cdsbed)
    c = sub.add_parser("classify"); c.add_argument("--gtf", required=True)
    c.add_argument("--out-genes", dest="out_genes", required=True)
    c.add_argument("--out-bed", dest="out_bed", required=True)
    c.add_argument("--out-single-ids", dest="out_single_ids", required=True)
    c.add_argument("--out-multi-ids", dest="out_multi_ids", required=True)
    c.set_defaults(func=cmd_classify)
    d = sub.add_parser("decide"); d.add_argument("--coverage", required=True)
    d.add_argument("--diamond", required=True)
    d.add_argument("--single-ids", dest="single_ids", required=True)
    d.add_argument("--multi-ids", dest="multi_ids", required=True)
    d.add_argument("--report", required=True); d.add_argument("--kept-ids", dest="kept_ids", required=True)
    d.add_argument("--min-frac", dest="min_frac", type=float, default=0.5)
    d.add_argument("--min-reads", dest="min_reads", type=int, default=5)
    d.set_defaults(func=cmd_decide)
    s = sub.add_parser("subset"); s.add_argument("--gtf", required=True)
    s.add_argument("--kept-ids", dest="kept_ids", required=True); s.add_argument("--out", required=True)
    s.set_defaults(func=cmd_subset)
    a = p.parse_args(); a.func(a)


if __name__ == "__main__":
    main()
