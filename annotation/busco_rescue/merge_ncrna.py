#!/usr/bin/env python3
"""Convert tRNAscan-SE output into clean gene->tRNA->exon features (stripped
seqids), gate out any tRNA overlapping a protein-coding CDS, and append to the
protein-coding final set -> Spalangia_cameroni.final.gff3 (+ matching GTF lines).
Pseudogenes are kept but marked gene_biotype=tRNA_pseudogene so they're filterable."""
import re, sys
from collections import defaultdict
P="/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly"
TRNA=f"{P}/analysis/ncrna/trna.gff"
PC_GFF=sys.argv[1]   # protein-coding final gff3 (CDS-bearing) to gate against + extend
OUT_GFF=sys.argv[2]
OUT_GTF=sys.argv[3]

def norm(s): return re.sub(r'_np\d+$','',s)
def ov(a1,a2,b1,b2): return max(0,min(a2,b2)-max(a1,b1)+1)

# ---- protein-coding CDS index (stripped seqid) for gating ----
cds=defaultdict(list)
for ln in open(PC_GFF):
    if ln.startswith('#') or '\t' not in ln: continue
    c=ln.split('\t')
    if len(c)>=8 and c[2]=='CDS': cds[norm(c[0])].append((int(c[3]),int(c[4])))
for k in cds: cds[k].sort()
def hits_cds(sq,lo,hi):
    for s,e in cds.get(sq,[]):
        if s>hi: break
        if ov(lo,hi,s,e): return True
    return False

# ---- parse tRNAscan gff: gene-level (tRNA|pseudogene) + exon children ----
loci={}; exons=defaultdict(list)
for ln in open(TRNA):
    if ln.startswith('#') or '\t' not in ln: continue
    c=ln.rstrip('\n').split('\t')
    if len(c)<9: continue
    seqid,src,ft,s,e,score,strand,_,attr=c[:9]; s,e=int(s),int(e)
    if ft in ('tRNA','pseudogene'):
        tid=re.search(r'ID=([^;]+)',attr).group(1)
        iso=(re.search(r'isotype=([^;]+)',attr) or [None,'Xxx'])[1]
        ac=(re.search(r'anticodon=([^;]+)',attr) or [None,'NNN'])[1]
        pseudo = ft=='pseudogene' or 'pseudogene' in attr
        loci[tid]=dict(seqid=norm(seqid),strand=strand,iso=iso,ac=ac,pseudo=pseudo)
    elif ft=='exon':
        pid=re.search(r'Parent=([^;]+)',attr).group(1)
        exons[pid].append((s,e))

kept=[]; drop_overlap=0
for tid,v in loci.items():
    ex=sorted(exons.get(tid, []))
    if not ex: continue
    lo,hi=ex[0][0],ex[-1][1]
    if hits_cds(v['seqid'],lo,hi): drop_overlap+=1; continue
    kept.append((v['seqid'],lo,hi,v['strand'],ex,v['iso'],v['ac'],v['pseudo']))
kept.sort(key=lambda x:(x[0],x[1]))

PC_GTF=sys.argv[4]
PSE_GFF=sys.argv[5]   # pseudogene tRNAs -> separate file
PSE_GTF=sys.argv[6]
import shutil

def gff_block(rec, idx):
    sq,lo,hi,st,ex,iso,ac,pseudo=rec
    gid=f"tRNA_{idx:05d}"; tx=f"{gid}-T1"
    bt="tRNA_pseudogene" if pseudo else "tRNA"
    prod=f"tRNA-{iso}({ac})"+(" (pseudogene)" if pseudo else "")
    out=[f"{sq}\ttRNAscan-SE\tgene\t{lo}\t{hi}\t.\t{st}\t.\tID={gid};gene_biotype={bt}",
         f"{sq}\ttRNAscan-SE\ttRNA\t{lo}\t{hi}\t.\t{st}\t.\tID={tx};Parent={gid};product={prod}"]
    out+=[f"{sq}\ttRNAscan-SE\texon\t{s}\t{e}\t.\t{st}\t.\tID={tx}.exon{j};Parent={tx}"
          for j,(s,e) in enumerate(ex,1)]
    return "\n".join(out)+"\n"

def gtf_block(rec, idx):
    sq,lo,hi,st,ex,iso,ac,pseudo=rec
    gid=f"tRNA_{idx:05d}"; tx=f"{gid}-T1"
    bt="tRNA_pseudogene" if pseudo else "tRNA"
    a=f'gene_id "{gid}"; transcript_id "{tx}"; gene_biotype "{bt}";'
    out=[f"{sq}\ttRNAscan-SE\ttranscript\t{lo}\t{hi}\t.\t{st}\t.\t{a}"]
    out+=[f"{sq}\ttRNAscan-SE\texon\t{s}\t{e}\t.\t{st}\t.\t{a}" for (s,e) in ex]
    return "\n".join(out)+"\n"

func =[r for r in kept if not r[7]]
pse  =[r for r in kept if r[7]]

# main final = protein-coding + FUNCTIONAL tRNAs
shutil.copyfile(PC_GFF, OUT_GFF); shutil.copyfile(PC_GTF, OUT_GTF)
with open(OUT_GFF,'a') as g, open(OUT_GTF,'a') as t:
    for i,r in enumerate(func,1): g.write(gff_block(r,i)); t.write(gtf_block(r,i))
# separate pseudogene-tRNA files
with open(PSE_GFF,'w') as g, open(PSE_GTF,'w') as t:
    g.write("##gff-version 3\n")
    for i,r in enumerate(pse,1): g.write(gff_block(r,i)); t.write(gtf_block(r,i))

print(f"tRNA loci parsed: {len(loci)}  kept: {len(kept)}")
print(f"  functional -> main final : {len(func)}")
print(f"  pseudogene -> separate    : {len(pse)}")
print(f"  dropped (CDS overlap)     : {drop_overlap}")
print(f"wrote {OUT_GFF}\nwrote {OUT_GTF}\nwrote {PSE_GFF}\nwrote {PSE_GTF}")
