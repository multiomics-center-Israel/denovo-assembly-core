#!/usr/bin/env python3
"""Flag the 300 sole-isoform internal-stop genes as pseudogenes (NCBI-safe).

For each affected gene:
  gene line   -> add gene_biotype=pseudogene;pseudo=true;Note=internal stop codon(s)
  mRNA line   -> retype to pseudogenic_transcript, add pseudo=true
  exon lines  -> kept (coordinates preserved)
  CDS  lines  -> dropped  (no translation => no internal-stop error)
Proteome      -> the 300 sequences removed (protein-coding set only).
GTF           -> CDS rows for the 300 transcripts dropped; transcript/exon kept.

Inputs are the authoritative canonical files; backups are written alongside.
"""
import re, sys, os

CAN = "annotation/canonical_annotation"
GFF = f"{CAN}/Spalangia_cameroni.final.gff3"
GTF = f"{CAN}/Spalangia_cameroni.final.gtf"
PROT = f"{CAN}/Spalangia_cameroni.proteins.fa"
IDS = sys.argv[1]  # internal_stop_ids.txt (mRNA ids)
STAMP = "20260630"

bad_mrna = set(l.strip() for l in open(IDS) if l.strip())

def attr(s, k):
    m = re.search(k + r'=([^;]+)', s)
    return m.group(1) if m else None

# ---- pass 1: resolve gene ids for the bad mRNAs ----
bad_genes = set()
for line in open(GFF):
    if line.startswith("#"):
        continue
    p = line.rstrip("\n").split("\t")
    if len(p) < 9 or p[2] not in ("mRNA", "transcript"):
        continue
    mid = attr(p[8], "ID")
    if mid in bad_mrna:
        par = attr(p[8], "Parent")
        if par:
            bad_genes.add(par)

# ---- pass 2: rewrite gff3 ----
def backup(path, tag):
    bak = path.replace(".gff3", f".pre_pseudo_{tag}.gff3").replace(".gtf", f".pre_pseudo_{tag}.gtf").replace(".fa", f".pre_pseudo_{tag}.fa")
    if not os.path.exists(bak):
        os.replace(path, bak)
        return bak
    # path already moved on rerun; recover from bak
    return bak

bak_gff = backup(GFF, STAMP)
out = open(GFF, "w")
n_gene = n_mrna = n_cds_dropped = 0
for line in open(bak_gff):
    if line.startswith("#"):
        out.write(line); continue
    p = line.rstrip("\n").split("\t")
    if len(p) < 9:
        out.write(line); continue
    typ = p[2]
    gid = attr(p[8], "ID")
    par = attr(p[8], "Parent")
    if typ == "gene" and gid in bad_genes:
        a = p[8].rstrip(";")
        a += ";gene_biotype=pseudogene;pseudo=true;Note=internal stop codon(s)%3B flagged pseudogene"
        p[8] = a
        out.write("\t".join(p) + "\n"); n_gene += 1
    elif typ in ("mRNA", "transcript") and gid in bad_mrna:
        p[2] = "pseudogenic_transcript"
        p[8] = p[8].rstrip(";") + ";pseudo=true"
        out.write("\t".join(p) + "\n"); n_mrna += 1
    elif typ == "CDS" and par in bad_mrna:
        n_cds_dropped += 1  # drop
    else:
        out.write(line)
out.close()

# ---- pass 3: rewrite gtf (drop CDS rows for bad transcripts) ----
bak_gtf = backup(GTF, STAMP)
outg = open(GTF, "w")
g_cds_dropped = 0
for line in open(bak_gtf):
    if line.startswith("#"):
        outg.write(line); continue
    p = line.split("\t")
    if len(p) < 9:
        outg.write(line); continue
    m = re.search(r'transcript_id "([^"]+)"', p[8])
    tid = m.group(1) if m else None
    if p[2] == "CDS" and tid in bad_mrna:
        g_cds_dropped += 1; continue
    if p[2] == "transcript" and tid in bad_mrna:
        # annotate as pseudogene-derived transcript
        p[8] = p[8].rstrip("\n").rstrip(";") + '; gene_biotype "pseudogene";\n'
    outg.write("\t".join(p) if isinstance(p, list) else line)
outg.close()

# ---- pass 4: clean proteome (remove the 300) ----
bak_prot = backup(PROT, STAMP)
outp = open(PROT, "w")
keep = True; removed = 0; kept = 0
for line in open(bak_prot):
    if line.startswith(">"):
        hid = line[1:].split()[0]
        keep = hid not in bad_mrna
        if keep: kept += 1
        else: removed += 1
    if keep:
        outp.write(line)
outp.close()

print(f"bad mRNAs            : {len(bad_mrna)}")
print(f"bad genes            : {len(bad_genes)}")
print(f"gff: genes flagged   : {n_gene}")
print(f"gff: mRNA retyped     : {n_mrna}")
print(f"gff: CDS dropped     : {n_cds_dropped}")
print(f"gtf: CDS dropped     : {g_cds_dropped}")
print(f"proteome: removed    : {removed}  kept: {kept}")
print(f"backups: {bak_gff}\n         {bak_gtf}\n         {bak_prot}")
