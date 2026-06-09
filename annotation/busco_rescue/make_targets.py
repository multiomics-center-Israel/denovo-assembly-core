#!/usr/bin/env python3
"""Emit the 395 rescue targets: BUSCOs Complete in genome-mode but Missing in
annotation-mode, sitting on a single contig. Writes targets.tsv (busco_id,
contig[_np], start, end, strand) and ancestral_targets.faa (BUSCO consensus
proteins for these, as the miniprot fallback queries)."""
import re
from collections import defaultdict
P="/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly"
GEN=f"{P}/qc/busco_results/run_hymenoptera_odb10/full_table.tsv"
ANN=f"{P}/analysis/busco/merged_canonical_prot/run_hymenoptera_odb10/full_table.tsv"
ANC=f"{P}/busco_downloads/lineages/hymenoptera_odb10/ancestral"
OUTDIR=f"{P}/annotation/busco_rescue"

def status(path):
    st={}
    rank={'Complete':3,'Duplicated':3,'Fragmented':2,'Missing':1}
    rows=defaultdict(list)
    for ln in open(path):
        if ln.startswith('#'): continue
        c=ln.rstrip('\n').split('\t')
        if len(c)<2: continue
        b,s=c[0],c[1]
        if b not in st or rank.get(s,0)>rank.get(st[b],0): st[b]=s
        if len(c)>=6 and c[2]:
            try: rows[b].append((c[2],int(c[3]),int(c[4]),c[5]))
            except ValueError: pass
    return st,rows

g,grows=status(GEN); a,_=status(ANN)
def simp(s): return 'Complete' if s=='Duplicated' else s
targets=[]
for b in g:
    if simp(g[b])=='Complete' and a.get(b,'Missing')=='Missing':
        contigs={r[0] for r in grows[b]}
        if len(contigs)==1:
            rs=grows[b]; contig=rs[0][0]
            start=min(r[1] for r in rs); end=max(r[2] for r in rs)
            strand=rs[0][3] if rs[0][3] in ('+','-') else '+'
            targets.append((b,contig,start,end,strand))
targets.sort()
with open(f"{OUTDIR}/targets.tsv","w") as o:
    o.write("busco_id\tcontig\tstart\tend\tstrand\n")
    for t in targets: o.write("\t".join(map(str,t))+"\n")
print(f"targets: {len(targets)}")

# ancestral query fasta for these BUSCOs
want={t[0] for t in targets}
keep=False; n=0
with open(f"{OUTDIR}/ancestral_targets.faa","w") as o:
    for ln in open(ANC):
        if ln.startswith('>'):
            bid=ln[1:].strip().split()[0]
            keep=bid in want
            if keep: n+=1
        if keep: o.write(ln)
print(f"ancestral query seqs written: {n}")
