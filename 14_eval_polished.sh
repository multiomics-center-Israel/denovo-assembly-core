#!/bin/bash
#$ -S /bin/bash
#$ -N eval_polished
#$ -cwd
#$ -j y
#$ -e /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/05.Assembly/05.final_evaluation/eval.err
#$ -o /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/05.Assembly/05.final_evaluation/eval.log
#$ -q bioinfo.q
#$ -pe shared 16

# =============================================
# Paths Setup
# =============================================
ASSEMBLY_BASE=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/05.Assembly

# Three assemblies to compare (showing the polishing trajectory)
HIFIASM_RAW=${ASSEMBLY_BASE}/01.hifiasm/Coelastrella_hifiasm.bp.p_ctg.fa
MEDAKA_POLISHED=${ASSEMBLY_BASE}/04.polishing/01.medaka/Coelastrella_hifiasm_medaka.fa
PILON_POLISHED=${ASSEMBLY_BASE}/04.polishing/02.pilon/Coelastrella_pilon.fasta

WORK_DIR=${ASSEMBLY_BASE}/05.final_evaluation
QUAST_OUT=${WORK_DIR}/01.quast_trajectory
BUSCO_OUT=${WORK_DIR}/02.busco
BUSCO_LINEAGE=chlorophyta_odb10

THREADS=16
GENOME_SIZE=105000000   # ~105 Mb, from GenomeScope2

mkdir -p ${WORK_DIR} ${BUSCO_OUT}
cd ${WORK_DIR}

# =============================================
# Verify inputs
# =============================================
echo "=== Input files check ==="
date
for f in ${HIFIASM_RAW} ${MEDAKA_POLISHED} ${PILON_POLISHED}; do
  if [ -f ${f} ]; then
    echo "OK: ${f} ($(du -h ${f} | cut -f1))"
  else
    echo "MISSING: ${f}"
    exit 1
  fi
done
echo ""

# =============================================
# Environment - Omics_QC has QUAST + BUSCO
# =============================================
source /gpfs0/system/conda/miniconda2/etc/profile.d/conda.sh
conda activate /gpfs0/system/conda/miniconda2/envs/Omics_QC

echo "=== Environment ==="
echo "Hostname: $(hostname)"
quast.py --version 2>&1 | head -1
busco --version 2>&1 | head -1
echo ""

# =============================================
# Step 1: QUAST - polishing trajectory
# =============================================
echo "=== Step 1: QUAST - polishing trajectory ==="
date

quast.py \
  ${HIFIASM_RAW} \
  ${MEDAKA_POLISHED} \
  ${PILON_POLISHED} \
  --labels "1_Hifiasm_raw,2_Medaka,3_Pilon" \
  --est-ref-size ${GENOME_SIZE} \
  --threads ${THREADS} \
  --output-dir ${QUAST_OUT}

echo ""
echo "=== QUAST report (txt) ==="
cat ${QUAST_OUT}/report.txt

# =============================================
# Step 2: BUSCO on Pilon-polished (the FINAL assembly)
# =============================================
echo ""
echo "=== Step 2: BUSCO on Pilon-polished assembly ==="
date

cd ${BUSCO_OUT}
busco \
  -i ${PILON_POLISHED} \
  -o pilon_polished \
  -l ${BUSCO_LINEAGE} \
  -m genome \
  -c ${THREADS}

# =============================================
# Step 3: Print BUSCO summary
# =============================================
echo ""
echo "=== BUSCO summary - polished assembly ==="
date
summary=${BUSCO_OUT}/pilon_polished/short_summary*.txt
if ls ${summary} >/dev/null 2>&1; then
  cat $(ls ${summary} | head -1)
fi

echo ""
echo "=== Comparison vs previous (raw Hifiasm BUSCO) ==="
# Previous BUSCO results from 03.evaluation
PREV_BUSCO=${ASSEMBLY_BASE}/03.evaluation/02.busco/hifiasm_primary/short_summary*.txt
if ls ${PREV_BUSCO} >/dev/null 2>&1; then
  echo "Previous (Hifiasm raw, before polishing):"
  grep -E "C:|n:|miniprot" $(ls ${PREV_BUSCO} | head -1) | head -3
  echo ""
  echo "Now (Pilon-polished):"
  grep -E "C:|n:|miniprot" $(ls ${summary} | head -1) | head -3
fi

echo ""
echo "=== Done! ==="
date
echo ""
echo "Outputs:"
echo "  QUAST report:   ${QUAST_OUT}/report.html  (open in browser)"
echo "  QUAST text:     ${QUAST_OUT}/report.txt"
echo "  BUSCO results:  ${BUSCO_OUT}/pilon_polished/"

