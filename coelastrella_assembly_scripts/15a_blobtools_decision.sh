#!/bin/bash
# ============================================================
# Step 15a: BlobTools post-processing — decontamination decision
# ============================================================
# AFTER BlobTools (Step 15-16) produces taxonomic classification per contig,
# this script applies explicit criteria to decide which contigs to remove.
#
# DECISION CRITERIA:
#   REMOVE if:
#     - Phylum is Aphelidiomycota (algal parasite, real exogenous DNA)
#     - Phylum is Bacillota (bacterial, low GC=0.44 + Illumina/ONT ratio >5x)
#     - Any other clearly exogenous prokaryotic phylum
#   KEEP if:
#     - Phylum is Chlorophyta (the algal genome)
#     - Phylum is "no-hit" (small contigs with no DIAMOND hit; GC/cov match host)
#     - Phylum is Ciliophora (Stylonychia cross-hits to conserved genes; GC=0.49 matches host)
#     - Phylum is Streptophyta (plant cross-hits to chloroplast/housekeeping genes)
#
# Inputs:
#   - summary_full.tsv  (from `blobtools filter --table` of the BlobDir)
#   - Coelastrella_pilon.fasta (polished input assembly)
# Outputs:
#   - contigs_to_remove.txt  (list of contigs flagged for removal)
#   - Coelastrella_decontaminated.fasta  (clean assembly)
#   - decontamination_log.txt
# ============================================================
set -e

WORK_DIR=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/05.Assembly/06.decontamination
INPUT_FASTA=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/05.Assembly/04.polishing/02.pilon/Coelastrella_pilon.fasta
SUMMARY=$WORK_DIR/summary_full.tsv   # produced by `blobtools filter --table`

cd $WORK_DIR

source /gpfs0/system/conda/miniconda2/etc/profile.d/conda.sh
conda activate /gpfs0/system/conda/miniconda2/envs/Mamba/envs/seqkit

# ====================
# Apply removal criteria
# ====================
# Column layout of summary_full.tsv:
#   $1=index $2=identifier $3=gc $4=length $5=ont_cov $6=ill_cov
#   $7=phylum $8=superkingdom $9=genus $10=species
echo "=== Applying removal criteria ==="
awk -F'\t' 'NR>1 {
  phylum=$7
  if (phylum == "Aphelidiomycota" || phylum == "Bacillota") {
    print $2
  }
}' $SUMMARY > contigs_to_remove.txt

echo "Contigs to remove:"
cat contigs_to_remove.txt
echo ""

# ====================
# Generate decontaminated assembly
# ====================
echo "=== Removing contaminant contigs ==="
seqkit grep -v -f contigs_to_remove.txt $INPUT_FASTA \
  > Coelastrella_decontaminated.fasta

# ====================
# Stats + log
# ====================
echo ""
echo "=== Before ==="
seqkit stats -a $INPUT_FASTA
echo ""
echo "=== After ==="
seqkit stats -a Coelastrella_decontaminated.fasta

# Detailed log
cat > decontamination_log.txt << LOG
=== Decontamination log ===
Date: $(date)
Input: $INPUT_FASTA
Output: $WORK_DIR/Coelastrella_decontaminated.fasta

Criteria applied:
  REMOVE Phylum == Aphelidiomycota (algal parasite)
  REMOVE Phylum == Bacillota (bacterial contaminant)
  KEEP all other Phyla (Chlorophyta, no-hit, Ciliophora cross-hits, Streptophyta cross-hits)

Removed contigs:
$(cat contigs_to_remove.txt | sed 's/^/  /')

Total removed: $(wc -l < contigs_to_remove.txt) contigs
LOG

cat decontamination_log.txt
