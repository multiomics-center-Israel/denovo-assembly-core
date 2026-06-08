#!/usr/bin/env python3
"""Normalize Tiberius GTF gene_id/transcript_id to the GLOBALLY-UNIQUE id.

The Tiberius outputs use THREE unrelated numbering schemes:
  - GTF gene_id            (e.g. "g4793") -> per-contig, NOT globally unique
  - protein header token 0 (e.g. "g5")    -> also not the gtf id, not unique
  - protein header token 1 (e.g. "g19730")-> the GLOBAL unique id == BUSCO seq id
merge_tib.py keys everything on the global id (token 1). The only reliable join
between the GTF and the protein/BUSCO namespace is COORDINATES:
  protein header: >{t0}|{GLOBAL}.t{k}|{contig}:{start0}-{end}({strand})
  gtf gene line : {contig}\\t...\\tgene\\t{start1}\\t{end}\\t...   (start0 == start1-1)
So map (contig,start0,end)->GLOBAL from the headers, then rewrite every GTF line's
gene_id/transcript_id via (contig, local_gene_id) -> GLOBAL resolved on the gene line.
"""
import re, sys

aa, gtf_in, gtf_out = sys.argv[1], sys.argv[2], sys.argv[3]

# (contig, start0, end) -> global, from protein headers
coord2glob = {}
with open(aa) as f:
    for l in f:
        if not l.startswith('>'): continue
        parts = l[1:].strip().split('|')
        if len(parts) < 3: continue
        glob = parts[1].split('.')[0]
        m = re.match(r'([^:]+):(\d+)-(\d+)', parts[2])
        if not m: continue
        contig, s0, e = m.group(1), int(m.group(2)), int(m.group(3))
        coord2glob[(contig, s0, e)] = glob
print(f"coord->global entries: {len(coord2glob)}  unique globals: {len(set(coord2glob.values()))}")

# pass 1: gene line coords -> resolve (contig, local_gene_id) -> global
gene2glob = {}
miss_coord = 0
with open(gtf_in) as f:
    for l in f:
        if l.startswith('#'): continue
        c = l.rstrip('\n').split('\t')
        if len(c) < 9 or c[2] != 'gene': continue
        gm = re.search(r'gene_id "([^"]+)"', c[8])
        if not gm: continue
        local = gm.group(1)
        key = (c[0], int(c[3]) - 1, int(c[4]))   # gtf start is 1-based -> 0-based
        glob = coord2glob.get(key)
        if glob is None:
            miss_coord += 1
            continue
        gene2glob[(c[0], local)] = glob
print(f"genes resolved: {len(gene2glob)}  gene lines with no coord match: {miss_coord}")

# pass 2: rewrite all feature lines
n_ok = n_miss = 0
with open(gtf_in) as f, open(gtf_out, 'w') as o:
    for l in f:
        if l.startswith('#'):
            o.write(l); continue
        c = l.rstrip('\n').split('\t')
        if len(c) < 9:
            o.write(l); continue
        gm = re.search(r'gene_id "([^"]+)"', c[8])
        glob = gene2glob.get((c[0], gm.group(1))) if gm else None
        if glob is None:
            n_miss += 1
            o.write(l); continue
        attr = re.sub(r'gene_id "[^"]+"', f'gene_id "{glob}"', c[8])
        tm = re.search(r'transcript_id "([^"]+)"', c[8])
        if tm:
            suf = tm.group(1).split('.', 1)
            newt = glob + ('.' + suf[1] if len(suf) > 1 else '.t1')
            attr = re.sub(r'transcript_id "[^"]+"', f'transcript_id "{newt}"', attr)
        o.write('\t'.join(c[:8] + [attr]) + '\n')
        n_ok += 1
print(f"rewrote {n_ok} feature lines; unmatched feature lines: {n_miss}")
