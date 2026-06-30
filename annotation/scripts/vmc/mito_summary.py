#!/usr/bin/env python3
"""Summarise tblastn of mitochondrial proteins vs the genome to pick the mito contig.
Usage: mito_summary.py <tblastn.fmt6> <genome.fai> <out_summary.tsv>
fmt6 cols: qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore
"""
import sys, collections
tab, fai, out = sys.argv[1], sys.argv[2], sys.argv[3]

lengths = {}
try:
    with open(fai) as fh:
        for line in fh:
            p = line.split("\t")
            lengths[p[0]] = int(p[1])
except FileNotFoundError:
    pass

# best hit (lowest evalue) per (protein, contig)
best = {}
with open(tab) as fh:
    for line in fh:
        c = line.rstrip("\n").split("\t")
        if len(c) < 12:
            continue
        q, s = c[0], c[1]
        ev = float(c[10]); bits = float(c[11])
        key = (q, s)
        if key not in best or ev < best[key][0]:
            best[key] = (ev, bits)

prot_per_contig = collections.defaultdict(set)
hits_per_contig = collections.Counter()
bits_per_contig = collections.Counter()
for (q, s), (ev, bits) in best.items():
    if ev <= 1e-5:
        prot_per_contig[s].add(q)
        hits_per_contig[s] += 1
        bits_per_contig[s] += bits

ranked = sorted(prot_per_contig, key=lambda s: (len(prot_per_contig[s]), bits_per_contig[s]),
                reverse=True)
with open(out, "w") as o:
    o.write("contig\tn_distinct_mito_proteins\ttotal_bitscore\tcontig_len_bp\tproteins\n")
    for s in ranked[:15]:
        o.write(f"{s}\t{len(prot_per_contig[s])}\t{bits_per_contig[s]:.0f}\t"
                f"{lengths.get(s,'NA')}\t{','.join(sorted(prot_per_contig[s]))}\n")

if ranked:
    top = ranked[0]
    print(f"MITO_CONTIG\t{top}\t{len(prot_per_contig[top])} distinct mito proteins"
          f"\tlen={lengths.get(top,'NA')} bp")
else:
    print("MITO_CONTIG\tNONE_FOUND")
