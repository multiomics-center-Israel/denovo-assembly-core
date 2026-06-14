#!/bin/bash
#$ -S /bin/bash
#$ -N fcsgx_run
#$ -cwd
#$ -j y
#$ -e fcsgx_run.err
#$ -o fcsgx_run.log
#$ -q bioinfo.q
#$ -pe shared 48

cd $(pwd)

source /gpfs0/system/conda/miniconda2/etc/profile.d/conda.sh
conda activate /gpfs0/system/conda/miniconda2/envs/Mamba/envs/fcsgx

ASSEMBLY=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/09.polypolish/Coelastrella_FINAL.fa
TAX_ID=75800     # Coelastrella sp.
GX_DB=/gpfs0/bioinfo/databases/fcs_gxdb/all   # prefix path, not just dir
OUT_DIR=fcs_output

mkdir -p $OUT_DIR

echo "=== Environment ==="
echo "Host: $(hostname)"
which gx run_gx.py
gx --help | head -3
echo ""

echo "=== Inputs ==="
ls -lh $ASSEMBLY
echo "DB prefix: $GX_DB"
ls -lh /gpfs0/bioinfo/databases/fcs_gxdb/all.* | head -5
echo ""

date
echo "=== Running FCS-GX ==="
run_gx.py \
  --fasta $ASSEMBLY \
  --tax-id $TAX_ID \
  --gx-db $GX_DB \
  --out-dir $OUT_DIR \
  --generate-logfile True

date
echo ""
echo "=== Output files ==="
ls -la $OUT_DIR/

echo ""
echo "=== Taxonomy report ==="
cat $OUT_DIR/*.taxonomy.rpt 2>/dev/null

echo ""
echo "=== Contamination summary ==="
grep -E "^#|EXCLUDE|TRIM|FIX|REVIEW" $OUT_DIR/*.taxonomy.rpt 2>/dev/null | head -50

date
echo "=== DONE ==="
