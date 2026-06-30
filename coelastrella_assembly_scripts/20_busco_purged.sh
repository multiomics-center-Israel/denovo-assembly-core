#!/bin/bash
#$ -S /bin/bash
#$ -N busco_purged
#$ -cwd
#$ -j y
#$ -e busco_purged.err
#$ -o busco_purged.log
#$ -q bioinfo.q
#$ -pe shared 16

WORK_DIR=$(pwd)
ASSEMBLY=${WORK_DIR}/Coelastrella_purged_final.fa
BUSCO_LINEAGE=chlorophyta_odb10
THREADS=16

cd ${WORK_DIR}

source /gpfs0/system/conda/miniconda2/etc/profile.d/conda.sh
conda activate /gpfs0/system/conda/miniconda2/envs/Omics_QC

echo "=== Environment ==="
echo "Hostname: $(hostname)"
busco --version 2>&1 | head -1
ls -lh ${ASSEMBLY}

echo ""
echo "=== Running BUSCO ==="
date
busco \
  -i ${ASSEMBLY} \
  -o BUSCO_purged_final \
  -l ${BUSCO_LINEAGE} \
  -m genome \
  -c ${THREADS} \
  --offline=false 2>&1 || \
busco \
  -i ${ASSEMBLY} \
  -o BUSCO_purged_final \
  -l ${BUSCO_LINEAGE} \
  -m genome \
  -c ${THREADS}

echo ""
echo "=== BUSCO summary ==="
date
summary=${WORK_DIR}/BUSCO_purged_final/short_summary*.txt
if ls ${summary} >/dev/null 2>&1; then
  cat $(ls ${summary} | head -1)
fi

date
echo "=== Done! ==="
