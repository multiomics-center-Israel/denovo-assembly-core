#!/bin/bash
# ============================================================
# Step 19a: purge_dups post-processing — organelle/rDNA rescue
# ============================================================
# AFTER purge_dups (Step 19) produces purged.fa (kept) and hap.fa (removed),
# this script identifies organelle and rDNA contigs incorrectly classified
# as HIGHCOV (high-coverage haplotigs) and restores them.
#
# RATIONALE:
#   purge_dups uses coverage cutoffs to identify haplotigs:
#     - haploid peak ~28x, diploid peak ~57x, upper bound 129x
#   Anything ABOVE 129x is flagged as HIGHCOV (assumed to be collapsed repeats).
#   But organelles have very high coverage (chloroplast ~1000x) — purge_dups
#   incorrectly removes them.
#
#   We rescue:
#     - HIGHCOV contigs whose size matches expected organelles (>50 kb chloroplast,
#       >50 kb rDNA arrays)
#     - JUNK contigs that are small mito fragments (manual identification)
#
# Inputs:
#   - purged.fa  (kept by purge_dups)
#   - hap.fa     (removed by purge_dups, contains the "haplotigs")
# Outputs:
#   - rescue_contigs.txt
#   - rescued.fa
#   - Coelastrella_purged_final.fa
# ============================================================
set -e

WORK_DIR=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/07.purge_dups
cd $WORK_DIR

source /gpfs0/system/conda/miniconda2/etc/profile.d/conda.sh
conda activate /gpfs0/system/conda/miniconda2/envs/Mamba/envs/seqkit

# ====================
# Identify contigs to rescue
# ====================
# Strategy: get all HIGHCOV contigs >= 5 kb (chloroplast + rDNA arrays)
# PLUS small JUNK contigs known to be mitochondrial fragments (manual list)
#
# In our case, the contigs to rescue are:
#   hap_ptg000024l_pilon_1 — Chloroplast (225 kb, HIGHCOV)
#   hap_ptg000032l_pilon_1 — rDNA array (68 kb, HIGHCOV)
#   hap_ptg000042l_pilon_1 — rDNA array (67 kb, HIGHCOV)
#   hap_ptg000037l_pilon_1 — mito fragment (2.4 kb, JUNK) → later reclassified as plastid by Tiara/BLAST

echo "=== HIGHCOV contigs in hap.fa (auto-detected ≥ 5kb) ==="
seqkit fx2tab -nl hap.fa | awk '$1 ~ /HIGHCOV/ && $NF >= 5000 {print $1}' \
  | awk '{print $1}' > rescue_contigs_auto.txt
cat rescue_contigs_auto.txt
echo ""

# Manual additions (small mito-like fragments labelled JUNK)
echo "=== Manual additions (small organelle fragments) ==="
cat > rescue_contigs_manual.txt << MANUAL
hap_ptg000037l_pilon_1
MANUAL
cat rescue_contigs_manual.txt
echo ""

# Combine
cat rescue_contigs_auto.txt rescue_contigs_manual.txt | sort -u > rescue_contigs.txt
echo "=== Final rescue list ==="
cat rescue_contigs.txt
echo ""

# ====================
# Extract rescued contigs
# ====================
seqkit grep -f rescue_contigs.txt hap.fa > rescued.fa
echo "=== Rescued contigs ==="
seqkit fx2tab -nl rescued.fa
echo ""

# ====================
# Combine purged + rescued
# ====================
cat purged.fa rescued.fa > Coelastrella_purged_final.fa

# Clean naming: remove 'hap_' prefix and '_1' suffix added by purge_dups
sed -i -E 's/^>hap_(ptg[0-9]+l_pilon)_1.*$/>\1/; s/^>(ptg[0-9]+l_pilon)_1$/>\1/' \
  Coelastrella_purged_final.fa

# ====================
# Stats + log
# ====================
echo "=== Final stats ==="
seqkit stats -a Coelastrella_purged_final.fa
echo ""
echo "=== All contigs in final assembly ==="
grep "^>" Coelastrella_purged_final.fa | sort

cat > rescue_log.txt << LOG
=== purge_dups rescue log ===
Date: $(date)
Input: $WORK_DIR/purged.fa + rescued contigs from $WORK_DIR/hap.fa
Output: $WORK_DIR/Coelastrella_purged_final.fa

Rationale:
  purge_dups labels organelles as HIGHCOV (collapsed repeats) due to their
  high copy number (chloroplast ~1000x coverage). These must be restored.

Rescued contigs:
$(cat rescue_contigs.txt | sed 's/^/  /')

Counts:
  purged.fa: $(grep -c "^>" purged.fa) contigs
  rescued.fa: $(grep -c "^>" rescued.fa) contigs
  FINAL: $(grep -c "^>" Coelastrella_purged_final.fa) contigs
LOG
cat rescue_log.txt
