#!/bin/bash
#$ -S /bin/bash
#$ -N busco_np
#$ -cwd
#$ -j y
#$ -e busco_polished.err
#$ -o busco_polished.log
#$ -q bioinfo.q
#$ -pe shared 16

WORK_DIR=$(pwd)
ASSEMBLY=${WORK_DIR}/Coelastrella_nextpolish_final.fa
BUSCO_LINEAGE=chlorophyta_odb10
THREADS=16

cd ${WORK_DIR}

source /gpfs0/system/conda/miniconda2/etc/profile.d/conda.sh
conda activate /gpfs0/system/conda/miniconda2/envs/Omics_QC

echo "=== Environment ==="
echo "Hostname: $(hostname)"
busco --version
ls -lh ${ASSEMBLY}

date
echo "=== Running BUSCO ==="
busco -i ${ASSEMBLY} -o BUSCO_nextpolish_final -l ${BUSCO_LINEAGE} -m genome -c ${THREADS} -f

echo ""
echo "=== Summary ==="
cat BUSCO_nextpolish_final/short_summary*.txt 2>/dev/null

date
echo "=== DONE ==="
