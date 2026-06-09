#!/usr/bin/env python3
"""Convert a normalized Tiberius GTF (global gene_ids, native contig names) into
EVM gene_predictions GFF3, matching the format of the existing BRAKER
gene_predictions.gff3 so it can be added as an ABINITIO_PREDICTION track.

Emits per gene:  gene / mRNA / exon* / CDS*  with source column = SOURCE and
IDs prefixed 'tib_' to avoid collision with BRAKER's 'rsc_' ids. Skips
start_codon/stop_codon/intron lines (EVM only needs gene/mRNA/exon/CDS).
"""
import re, sys, collections

gtf_in, out, SOURCE = sys.argv[1], sys.argv[2], (sys.argv[3] if len(sys.argv) > 3 else "Tiberius")

genes = {}                       # gid -> (contig, strand, gstart, gend)
exons = collections.defaultdict(list)   # gid -> [(s,e)]
cds   = collections.defaultdict(list)   # gid -> [(s,e,frame)]
order = []
for l in open(gtf_in):
    if l.startswith('#'): continue
    c = l.rstrip('\n').split('\t')
    if len(c) < 9: continue
    m = re.search(r'gene_id "([^"]+)"', c[8])
    if not m: continue
    gid = m.group(1)
    t = c[2]
    if t == 'gene':
        if gid not in genes:
            genes[gid] = (c[0], c[6], int(c[3]), int(c[4])); order.append(gid)
    elif t == 'exon':
        exons[gid].append((int(c[3]), int(c[4])))
    elif t == 'CDS':
        cds[gid].append((int(c[3]), int(c[4]), c[7]))

with open(out, 'w') as o:
    o.write("##gff-version 3\n")
    n = 0
    for gid in order:
        contig, strand, gs, ge = genes[gid]
        gg = f"tib_{gid}"; tt = f"{gg}.t1"
        o.write(f"{contig}\t{SOURCE}\tgene\t{gs}\t{ge}\t.\t{strand}\t.\tID={gg}\n")
        o.write(f"{contig}\t{SOURCE}\tmRNA\t{gs}\t{ge}\t.\t{strand}\t.\tID={tt};Parent={gg}\n")
        for i, (s, e) in enumerate(sorted(exons[gid]), 1):
            o.write(f"{contig}\t{SOURCE}\texon\t{s}\t{e}\t.\t{strand}\t.\tID={tt}.exon{i};Parent={tt}\n")
        for s, e, fr in sorted(cds[gid]):
            fr = fr if fr in ('0', '1', '2') else '0'
            o.write(f"{contig}\t{SOURCE}\tCDS\t{s}\t{e}\t.\t{strand}\t{fr}\tID={tt}.cds;Parent={tt}\n")
        n += 1
    print(f"wrote {n} genes to {out}")
