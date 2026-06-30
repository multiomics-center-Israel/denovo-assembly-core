#!/usr/bin/env bash
# tblastn (Nasonia proteome) + pblat (Spalangia TSA transcripts) vs revised 4,980-contig assembly
set -uo pipefail
PROJECT=/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly
cd "$PROJECT"
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate genome_assembly

GENOME=$PROJECT/final_assembly.fa
DB=$PROJECT/comparison_to_nasonia/tblastn/spalangia_4980
NAS=/mnt/data/genomes/wasp_nasonia/GCF_009193385.2_Nvit_psr_1.1_protein.faa
TSA=$PROJECT/short_reads_contem_index/GBVV01.transcripts.one_line.fasta
TB_OUT=$PROJECT/comparison_to_nasonia/tblastn
BL_OUT=$PROJECT/comparison_to_nasonia/blat
THREADS=20
mkdir -p "$TB_OUT" "$BL_OUT"

echo "==== driver started $(date -Iseconds) ===="

# 1) Wait for the two CPU-heavy jobs to finish so we don't oversubscribe 24 cores
echo "[wait] for RepeatMasker + BUSCO/QUAST to free CPUs..."
while pgrep -f "bin/RepeatMasker" >/dev/null 2>&1 \
   || pgrep -f "busco -i final_assembly.fa" >/dev/null 2>&1 \
   || pgrep -f "quast final_assembly.fa" >/dev/null 2>&1; do
  sleep 60
done
echo "[wait] cores free at $(date -Iseconds)"

# 2) tblastn: Nasonia proteome (query) vs revised Spalangia genome (nucl db)
echo "==== tblastn Nasonia proteome vs spalangia_4980 $(date -Iseconds) ===="
tblastn -query "$NAS" -db "$DB" \
  -evalue 1e-5 -num_threads $THREADS -max_target_seqs 5 \
  -outfmt "6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore qcovhsp qlen" \
  -out "$TB_OUT/nasonia_proteome_vs_spalangia4980.tsv" 2> "$TB_OUT/tblastn.log"
echo "tblastn rc=$? lines=$(wc -l < "$TB_OUT/nasonia_proteome_vs_spalangia4980.tsv")"

# tblastn summary: best hit per Nasonia protein, count proteins with a hit
python3 - "$TB_OUT/nasonia_proteome_vs_spalangia4980.tsv" "$NAS" > "$TB_OUT/tblastn_summary.txt" <<'PY'
import sys
tsv, faa = sys.argv[1], sys.argv[2]
total = sum(1 for l in open(faa) if l.startswith('>'))
best = {}
for line in open(tsv):
    f = line.rstrip('\n').split('\t')
    if len(f) < 14: continue
    q = f[0]; bit = float(f[11]); qcov = float(f[12])
    if q not in best or bit > best[q][0]:
        best[q] = (bit, float(f[2]), qcov)
hit = len(best)
cov50 = sum(1 for v in best.values() if v[2] >= 50)
cov80 = sum(1 for v in best.values() if v[2] >= 80)
print(f"Nasonia proteins (query) total : {total}")
print(f"Proteins with >=1 hit (e<1e-5) : {hit}  ({100*hit/total:.1f}%)")
print(f"  best-hit qcov >=50%          : {cov50}  ({100*cov50/total:.1f}%)")
print(f"  best-hit qcov >=80%          : {cov80}  ({100*cov80/total:.1f}%)")
PY
echo "--- tblastn_summary ---"; cat "$TB_OUT/tblastn_summary.txt"

# 3) pblat: Spalangia TSA transcripts (assembled transcriptome) vs revised genome
#    Output as BLAST tabular WITH comment lines (blat 'blast9' == BLAST -outfmt 7)
echo "==== pblat TSA transcripts vs revised genome (BLAST fmt 7 / blast9) $(date -Iseconds) ===="
pblat "$GENOME" "$TSA" -threads=$THREADS -out=blast9 -minIdentity=90 \
  "$BL_OUT/tsa_GBVV01_vs_spalangia4980.fmt7.tsv" 2> "$BL_OUT/pblat.log"
echo "pblat rc=$? out_lines=$(wc -l < "$BL_OUT/tsa_GBVV01_vs_spalangia4980.fmt7.tsv")"

# pblat summary: best hit per transcript, fraction of transcripts mapped, coverage/identity.
# blast9 cols (std 12): qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore
# Coverage fraction needs transcript length -> read it from the TSA FASTA.
python3 - "$BL_OUT/tsa_GBVV01_vs_spalangia4980.fmt7.tsv" "$TSA" > "$BL_OUT/blat_summary.txt" <<'PY'
import sys
tab, tsa = sys.argv[1], sys.argv[2]
# transcript lengths from FASTA
qlen = {}; name=None; n=0
for line in open(tsa):
    if line.startswith('>'):
        name = line[1:].split()[0]; qlen[name]=0
    elif name:
        qlen[name]+=len(line.strip())
total = len(qlen)
best = {}  # qname -> (best_coverage_fraction, identity)
for line in open(tab):
    if line.startswith('#'): continue
    f = line.rstrip('\n').split('\t')
    if len(f) < 12: continue
    q=f[0]; pident=float(f[2]); qs=int(f[6]); qe=int(f[7])
    span = abs(qe-qs)+1
    cov = span/qlen.get(q,0) if qlen.get(q,0) else 0
    if q not in best or cov > best[q][0]:
        best[q] = (cov, pident)
mapped = len(best)
c50 = sum(1 for v in best.values() if v[0] >= 0.50)
c90 = sum(1 for v in best.values() if v[0] >= 0.90)
print(f"TSA transcripts (query) total  : {total}")
print(f"Transcripts with >=1 alignment : {mapped}  ({100*mapped/total:.1f}%)")
print(f"  best HSP covers >=50% of tx  : {c50}  ({100*c50/total:.1f}%)")
print(f"  best HSP covers >=90% of tx  : {c90}  ({100*c90/total:.1f}%)")
print("(coverage = single best HSP span / transcript length; multi-exon transcripts split across HSPs read lower here)")
PY
echo "--- blat_summary ---"; cat "$BL_OUT/blat_summary.txt"

echo "==== driver finished $(date -Iseconds) ===="
