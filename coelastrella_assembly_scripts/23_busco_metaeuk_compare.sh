#!/bin/bash
#$ -S /bin/bash
#$ -N busco_meta
#$ -cwd
#$ -j y
#$ -e busco_metaeuk.err
#$ -o busco_metaeuk.log
#$ -q bioinfo.q
#$ -pe shared 16

cd $(pwd)

source /gpfs0/system/conda/miniconda2/etc/profile.d/conda.sh
conda activate /gpfs0/system/conda/miniconda2/envs/Omics_QC

ASSEMBLY=Coelastrella_nextpolish_final.fa

echo "=== Environment ==="
busco --version
busco --list-datasets 2>&1 | head -3

date
echo "=== Running BUSCO with metaeuk ==="
# Use --metaeuk flag to force metaeuk instead of miniprot
busco -i ${ASSEMBLY} \
  -o BUSCO_nextpolish_metaeuk \
  -l chlorophyta_odb10 \
  -m genome \
  -c 16 \
  --metaeuk \
  -f

echo ""
echo "=== Summary (metaeuk) ==="
cat BUSCO_nextpolish_metaeuk/short_summary*.txt 2>/dev/null

date
echo "=== DONE ==="
