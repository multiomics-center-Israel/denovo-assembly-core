#!/bin/bash
# ============================================================
# Step 26b: BLAST verification of small "organelle" contigs
# ============================================================
# AFTER Tiara classifies small contigs as plastid/organelle, this script
# verifies the classification by BLAST against the known main chloroplast
# contig.
#
# RATIONALE:
#   Small contigs (<5 kb) with low GC may be either:
#     (a) Plastid IR (Inverted Repeat) fragments that failed to merge with main chloroplast
#     (b) Mitochondrial fragments
#   Tiara cannot reliably distinguish between (a) and (b).
#   BLAST against the known main chloroplast resolves this:
#     - If 100% identity → (a) plastid fragment
#     - If no hit       → (b) likely mitochondrial
#
# Inputs:
#   - Coelastrella_FINAL.fa (final assembly)
#   - List of small organelle-classified contigs to test
# Outputs:
#   - blast_vs_chloroplast.tsv
#   - organelle_verification_log.txt
# ============================================================
set -e

WORK_DIR=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/10.tiara/blast_organelle
ASSEMBLY=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/09.polypolish/Coelastrella_FINAL.fa

# Main chloroplast contig (the largest organelle-classified contig, verified earlier by Boris's BLAST)
MAIN_CHLOROPLAST=ptg000024l_pilon_np1212

# Small contigs to verify (Tiara flagged as plastid/organelle, < 5 kb)
SUSPECT_CONTIGS=(
  ptg000031l_pilon_np1212
  ptg000037l_pilon_np1212
)

mkdir -p $WORK_DIR
cd $WORK_DIR

source /gpfs0/system/conda/miniconda2/etc/profile.d/conda.sh

# ====================
# Step 1: Extract reference (main chloroplast)
# ====================
echo "=== Extracting main chloroplast as BLAST reference ==="
conda activate /gpfs0/system/conda/miniconda2/envs/Mamba/envs/seqkit

echo "$MAIN_CHLOROPLAST" > chloroplast_id.txt
seqkit grep -f chloroplast_id.txt $ASSEMBLY > known_chloroplast.fa
seqkit stats known_chloroplast.fa

# ====================
# Step 2: Extract suspect contigs as queries
# ====================
echo ""
echo "=== Extracting suspect contigs as queries ==="
printf "%s\n" "${SUSPECT_CONTIGS[@]}" > suspected_ids.txt
seqkit grep -f suspected_ids.txt $ASSEMBLY > query_small.fa
seqkit stats query_small.fa

# ====================
# Step 3: BLAST
# ====================
echo ""
echo "=== Running BLASTn ==="
conda deactivate
conda activate /gpfs0/system/conda/miniconda2/envs/Omics_QC

makeblastdb -in known_chloroplast.fa -dbtype nucl -out chloroplast_db

blastn -query query_small.fa -db chloroplast_db \
  -outfmt "6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore" \
  -evalue 1e-5 \
  -out blast_vs_chloroplast.tsv

# ====================
# Summary
# ====================
echo ""
echo "=== Per-query verdict ==="
for contig in "${SUSPECT_CONTIGS[@]}"; do
  hits=$(grep -c "^$contig" blast_vs_chloroplast.tsv 2>/dev/null || echo 0)
  best=$(grep "^$contig" blast_vs_chloroplast.tsv | sort -k4 -rn | head -1)
  echo "$contig:"
  echo "  Total hits: $hits"
  if [ -n "$best" ]; then
    pident=$(echo $best | awk '{print $3}')
    length=$(echo $best | awk '{print $4}')
    echo "  Best hit: $pident% identity, $length bp aligned"
    if (( $(echo "$pident >= 95" | bc -l 2>/dev/null || echo 0) )); then
      echo "  ✓ VERDICT: PLASTID FRAGMENT (high identity to main chloroplast)"
    fi
  else
    echo "  ✗ VERDICT: NO MATCH — likely mitochondrial or unknown"
  fi
done | tee organelle_verification_log.txt

echo ""
echo "=== Full BLAST output: blast_vs_chloroplast.tsv ==="
