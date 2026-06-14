#!/bin/bash
# ============================================================
# Step 26a: Tiara post-processing — remove bacterial contigs
# ============================================================
# AFTER Tiara (Step 26) classifies all contigs, this script identifies
# bacterial contigs that BlobTools missed (due to small contig size).
#
# DECISION CRITERIA:
#   REMOVE if:
#     - Tiara class_fst_stage == "bacteria"  (high confidence)
#   KEEP if:
#     - eukarya (real Coelastrella genome)
#     - organelle (chloroplast, mito)
#     - prokarya/unknown WITH GC matching host (rDNA arrays - false positive due
#       to conserved rRNA genes between eukaryotes and prokaryotes)
#
# Inputs:
#   - classification.txt (from Tiara)
#   - Coelastrella_polypolish_pypolca_final.fa (input assembly)
# Outputs:
#   - contigs_to_remove_tiara.txt
#   - Coelastrella_FINAL.fa  (final clean assembly)
# ============================================================
set -e

WORK_DIR=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/10.tiara
INPUT=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/09.polypolish/Coelastrella_polypolish_pypolca_final.fa
OUTPUT=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/09.polypolish/Coelastrella_FINAL.fa

cd $WORK_DIR

source /gpfs0/system/conda/miniconda2/etc/profile.d/conda.sh
conda activate /gpfs0/system/conda/miniconda2/envs/Mamba/envs/seqkit

# ====================
# Apply removal criteria
# ====================
# classification.txt format:
#   col 1: sequence_id
#   col 2: class_fst_stage (bacteria/archaea/eukarya/organelle/prokarya/unknown)
echo "=== Identifying bacterial contigs ==="
awk -F'\t' 'NR>1 && $2=="bacteria" {print $1}' classification.txt \
  > contigs_to_remove_tiara.txt

echo "Contigs flagged as bacteria by Tiara:"
cat contigs_to_remove_tiara.txt
echo ""

# ====================
# Generate final clean assembly
# ====================
echo "=== Removing bacterial contigs ==="
seqkit grep -v -f contigs_to_remove_tiara.txt $INPUT > $OUTPUT

# ====================
# Stats + log
# ====================
echo ""
echo "=== Before ==="
seqkit stats -a $INPUT
echo ""
echo "=== After (FINAL) ==="
seqkit stats -a $OUTPUT

cat > tiara_decision_log.txt << LOG
=== Tiara decision log ===
Date: $(date)
Input: $INPUT
Output: $OUTPUT

Criteria applied:
  REMOVE Tiara class_fst_stage == "bacteria"
  KEEP eukarya / organelle / prokarya (rDNA cross-hits) / unknown

Rationale:
  Tiara uses k-mer composition deep learning, complementary to BlobTools (DIAMOND
  homology). Tiara catches bacterial contigs too small for reliable BLAST hits.
  prokarya/unknown classifications on large rDNA arrays are FALSE POSITIVES
  (conserved rRNA between kingdoms confuses k-mer classifier).

Removed contigs:
$(cat contigs_to_remove_tiara.txt | sed 's/^/  /')

Total removed: $(wc -l < contigs_to_remove_tiara.txt) contigs
LOG
cat tiara_decision_log.txt
