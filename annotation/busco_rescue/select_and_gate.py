#!/usr/bin/env python3
"""Select one rescue model per target BUSCO (Nasonia-first, ancestral fallback),
gate against the canonical annotation, and emit a graftable GFF3.

Logic per target BUSCO:
  - anchor   = best miniprot model of the BUSCO ancestral consensus (defines the locus).
  - nasonia  = best Nasonia miniprot model overlapping the anchor CDS (same gene, realistic structure).
  - choose Nasonia if it overlaps the anchor well AND is clean (no frameshift / no internal stop);
    else fall back to the ancestral model.
Gate: drop if CDS overlaps an existing canonical gene (we only ADD at novel loci);
      drop frameshifted/internal-stop-only models; dedup loci across BUSCOs.
Seqids: miniprot uses ptg..._np####; canonical uses stripped ptg...; we compare on the
stripped form and WRITE stripped seqids so the graft matches the canonical genome/GFF3.
"""
import re
from collections import defaultdict
P="/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly"
RES=f"{P}/annotation/busco_rescue"
CANON=f"{P}/annotation/funannotate_merged_out/annotate_results/Spalangia_cameroni.gff3"

def norm(s): return re.sub(r'_np\d+$','',s)
def overlap(a1,a2,b1,b2): return max(0, min(a2,b2)-max(a1,b1)+1)

def parse_miniprot(path):
    """id -> dict(seqid,strand,score,cds=[(s,e)],frameshift,stopc,ident,target)"""
    M={}
    for ln in open(path):
        if ln.startswith('#') or '\t' not in ln: continue
        c=ln.rstrip('\n').split('\t')
        if len(c)<9: continue
        seqid,_,ft,s,e,score,strand,_,attr=c[:9]; s,e=int(s),int(e)
        if ft=='mRNA':
            mid=re.search(r'ID=([^;]+)',attr).group(1)
            tgt=re.search(r'Target=([^\s;]+)',attr)
            M[mid]=dict(seqid=norm(seqid),strand=strand,score=float(score),cds=[],
                        fs='Frameshift=' in attr, stopc='StopCodon=' in attr,
                        ident=float((re.search(r'Identity=([\d.]+)',attr) or [0,'0'])[1]),
                        target=tgt.group(1) if tgt else None)
        elif ft=='CDS':
            pid=re.search(r'Parent=([^;]+)',attr).group(1)
            ph=c[7] if c[7] in ('0','1','2') else '0'
            if pid in M: M[pid]['cds'].append((s,e,ph))
    for v in M.values(): v['cds'].sort()
    return M

# anchors: best ancestral model per BUSCO (highest score, rank1)
anc=parse_miniprot(f"{RES}/ancestral.miniprot.gff")
anchor={}
for mid,v in anc.items():
    b=v['target']
    if not v['cds']: continue
    if b not in anchor or v['score']>anchor[b]['score']:
        anchor[b]=v

# nasonia models indexed by contig
nas=parse_miniprot(f"{RES}/nasonia.miniprot.gff")
nas_by_ctg=defaultdict(list)
for mid,v in nas.items():
    if v['cds']: nas_by_ctg[v['seqid']].append(v)

# canonical CDS index by contig (stripped seqid)
canon_cds=defaultdict(list)
for ln in open(CANON):
    if ln.startswith('#') or '\t' not in ln: continue
    c=ln.rstrip('\n').split('\t')
    if len(c)<9 or c[2]!='CDS': continue
    canon_cds[norm(c[0])].append((int(c[3]),int(c[4])))
for k in canon_cds: canon_cds[k].sort()

# contig lengths (stripped seqid) to drop off-the-end models
clen={}
for ln in open(f"{P}/annotation/funannotate_in/genome.fa.fai"):
    c=ln.split('\t'); clen[norm(c[0])]=int(c[1])

def cds_span(cds): return cds[0][0], cds[-1][1]
def hits_canon(seqid,cds):
    lo,hi=cds_span(cds)
    for (s,e) in canon_cds.get(seqid,[]):
        if s>hi: break
        if overlap(lo,hi,s,e): return True
    return False
def clean(v):  # complete-ish model
    return (not v['fs']) and (not v['stopc'])

targets=[l.rstrip('\n').split('\t') for l in open(f"{RES}/targets.tsv")][1:]
chosen=[]; used_loci=[]
stats=defaultdict(int)
for b,contig,start,end,strand in targets:
    sctg=norm(contig)
    a=anchor.get(b)
    if not a:
        stats['no_anchor']+=1; continue
    alo,ahi=cds_span(a['cds'])
    # best nasonia overlapping anchor CDS span by >=30%
    best_n=None
    for v in nas_by_ctg.get(sctg,[]):
        nlo,nhi=cds_span(v['cds'])
        ov=overlap(alo,ahi,nlo,nhi)
        if ov>0 and ov/max(1,(ahi-alo+1))>=0.30 and clean(v):
            if best_n is None or v['score']>best_n['score']: best_n=v
    pick = best_n if best_n else a
    src  = 'nasonia' if best_n else 'ancestral'
    if not clean(pick):
        stats['drop_frameshift_or_stop']+=1; continue
    plo,phi=cds_span(pick['cds'])
    if sctg not in clen or phi>clen[sctg] or plo<1:
        stats['drop_off_contig']+=1; continue
    if hits_canon(sctg, pick['cds']):
        stats['drop_overlaps_canonical']+=1; continue
    lo,hi=cds_span(pick['cds'])
    if any(nc==sctg and overlap(lo,hi,pl,ph) for nc,pl,ph in used_loci):
        stats['drop_dup_locus']+=1; continue
    used_loci.append((sctg,lo,hi))
    chosen.append(dict(busco=b,seqid=sctg,strand=pick['strand'],cds=pick['cds'],
                       src=src,ident=pick['ident']))
    stats[f'kept_{src}']+=1

# write graft gff3 (CDS-only models: exon==CDS)
out=open(f"{RES}/busco_graft.gff3","w"); out.write("##gff-version 3\n")
for i,m in enumerate(sorted(chosen,key=lambda x:(x['seqid'],x['cds'][0][0])),1):
    gid=f"BUSCOr_{i:04d}"; mid=f"{gid}-T1"
    lo,hi=cds_span(m['cds']); st=m['strand']; sq=m['seqid']
    note=f"BUSCO-rescue {m['busco']} ({m['src']} homology, evidence-light)"
    out.write(f"{sq}\tminiprot_busco_rescue\tgene\t{lo}\t{hi}\t.\t{st}\t.\tID={gid};note={note}\n")
    out.write(f"{sq}\tminiprot_busco_rescue\tmRNA\t{lo}\t{hi}\t.\t{st}\t.\tID={mid};Parent={gid};note={note}\n")
    # CDS-only models: exon == CDS span; CDS phase taken VERBATIM from miniprot
    for j,(s,e,ph) in enumerate(m['cds'],1):
        out.write(f"{sq}\tminiprot_busco_rescue\texon\t{s}\t{e}\t.\t{st}\t.\tID={mid}.exon{j};Parent={mid}\n")
    for (s,e,ph) in m['cds']:
        out.write(f"{sq}\tminiprot_busco_rescue\tCDS\t{s}\t{e}\t.\t{st}\t{ph}\tID={mid}.cds;Parent={mid}\n")
out.close()
print("=== gating stats ==="); [print(f"  {k}: {v}") for k,v in sorted(stats.items())]
print(f"TOTAL grafted: {len(chosen)}  (nasonia={stats['kept_nasonia']}, ancestral={stats['kept_ancestral']})")
print(f"wrote {RES}/busco_graft.gff3")
