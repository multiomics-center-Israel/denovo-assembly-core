#!/bin/bash
#$ -S /bin/bash
#$ -N busco_clean
#$ -cwd
#$ -j y
#$ -e busco_clean.err
#$ -o busco_clean.log
#$ -q bioinfo.q
#$ -pe shared 16

# Paths
WORK_DIR=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/05.Assembly/06.decontamination
ASSEMBLY=${WORK_DIR}/Coelastrella_decontaminated.fasta
BUSCO_OUT=${WORK_DIR}/BUSCO_decontaminated
BUSCO_LINEAGE=chlorophyta_odb10
THREADS=16

cd ${WORK_DIR}

# Check input
echo "=== Input check ==="
date
ls -lh ${ASSEMBLY}

# Activate — full path to env (as in working script)
source /gpfs0/system/conda/miniconda2/etc/profile.d/conda.sh
conda activate /gpfs0/system/conda/miniconda2/envs/Omics_QC

echo "=== Environment ==="
echo "Hostname: $(hostname)"
busco --version 2>&1 | head -1

# Run BUSCO (note: -c not --cpu, --offline=false as in working script)
echo ""
echo "=== Running BUSCO ==="
date
busco \
  -i ${ASSEMBLY} \
  -o BUSCO_decontaminated \
  -l ${BUSCO_LINEAGE} \
  -m genome \
  -c ${THREADS} \
  --offline=false 2>&1 || \
busco \
  -i ${ASSEMBLY} \
  -o BUSCO_decontaminated \
  -l ${BUSCO_LINEAGE} \
  -m genome \
  -c ${THREADS}

# Summary
echo ""
echo "=== BUSCO summary ==="
date
summary=${WORK_DIR}/BUSCO_decontaminated/short_summary*.txt
if ls ${summary} >/dev/null 2>&1; then
  cat $(ls ${summary} | head -1)
fi

echo ""
echo "=== Done! ==="
date
