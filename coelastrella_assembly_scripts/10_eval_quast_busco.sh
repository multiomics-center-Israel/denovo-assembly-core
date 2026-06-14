#!/bin/bash
#$ -S /bin/bash
#$ -N eval_assemblies
#$ -cwd
#$ -j y
#$ -e /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/05.Assembly/03.evaluation/eval.err
#$ -o /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/05.Assembly/03.evaluation/eval.log
#$ -q bioinfo.q
#$ -pe shared 16

# =============================================
# Paths Setup
# =============================================
ASSEMBLY_BASE=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/05.Assembly

HIFIASM_PRIMARY=${ASSEMBLY_BASE}/01.hifiasm/Coelastrella_hifiasm.bp.p_ctg.fa
HIFIASM_HAP1=${ASSEMBLY_BASE}/01.hifiasm/Coelastrella_hifiasm.bp.hap1.p_ctg.fa
HIFIASM_HAP2=${ASSEMBLY_BASE}/01.hifiasm/Coelastrella_hifiasm.bp.hap2.p_ctg.fa
FLYE_ASSEMBLY=${ASSEMBLY_BASE}/02.flye/flye_output/assembly.fasta

WORK_DIR=${ASSEMBLY_BASE}/03.evaluation
QUAST_OUT=${WORK_DIR}/01.quast_compare
BUSCO_OUT=${WORK_DIR}/02.busco
BUSCO_LINEAGE=chlorophyta_odb10

THREADS=16
GENOME_SIZE=105000000   # ~105 Mb, from GenomeScope2

mkdir -p ${WORK_DIR} ${BUSCO_OUT}
cd ${WORK_DIR}

# =============================================
# Verify input files exist
# =============================================
echo "=== Input files check ==="
date
for f in ${HIFIASM_PRIMARY} ${HIFIASM_HAP1} ${HIFIASM_HAP2} ${FLYE_ASSEMBLY}; do
  if [ -f ${f} ]; then
    echo "OK: ${f} ($(du -h ${f} | cut -f1))"
  else
    echo "MISSING: ${f}"
  fi
done
echo ""

# =============================================
# Environment - QUAST + BUSCO both in Omics_QC
# =============================================
source /gpfs0/system/conda/miniconda2/etc/profile.d/conda.sh
conda activate /gpfs0/system/conda/miniconda2/envs/Omics_QC

echo "=== Environment ==="
echo "Hostname: $(hostname)"
quast.py --version 2>&1 | head -1
busco --version 2>&1 | head -1
echo ""

# =============================================
# Step 1: QUAST - compare all assemblies
# =============================================
echo "=== Step 1: QUAST comparison ==="
date

quast.py \
  ${HIFIASM_PRIMARY} \
  ${HIFIASM_HAP1} \
  ${HIFIASM_HAP2} \
  ${FLYE_ASSEMBLY} \
  --labels "Hifiasm_primary,Hifiasm_hap1,Hifiasm_hap2,Flye" \
  --est-ref-size ${GENOME_SIZE} \
  --threads ${THREADS} \
  --output-dir ${QUAST_OUT}

echo ""
echo "QUAST report (text):"
cat ${QUAST_OUT}/report.txt
echo ""

# =============================================
# Step 2: BUSCO on each assembly (sequentially)
# =============================================
echo "=== Step 2: BUSCO completeness analysis ==="
echo "Lineage: ${BUSCO_LINEAGE}"
date

# Helper function
run_busco() {
  local input=$1
  local outname=$2
  echo ""
  echo "--- BUSCO: ${outname} ---"
  date
  cd ${BUSCO_OUT}
  busco \
    -i ${input} \
    -o ${outname} \
    -l ${BUSCO_LINEAGE} \
    -m genome \
    -c ${THREADS} \
    --offline=false 2>&1 || \
  busco \
    -i ${input} \
    -o ${outname} \
    -l ${BUSCO_LINEAGE} \
    -m genome \
    -c ${THREADS}
}

# Run BUSCO on each assembly
run_busco ${HIFIASM_PRIMARY} hifiasm_primary
run_busco ${HIFIASM_HAP1}    hifiasm_hap1
run_busco ${HIFIASM_HAP2}    hifiasm_hap2
run_busco ${FLYE_ASSEMBLY}   flye

# =============================================
# Step 3: BUSCO summary comparison
# =============================================
echo ""
echo "=== Step 3: BUSCO summary ==="
date

for outname in hifiasm_primary hifiasm_hap1 hifiasm_hap2 flye; do
  summary=${BUSCO_OUT}/${outname}/short_summary*.txt
  if ls ${summary} >/dev/null 2>&1; then
    echo ""
    echo "----- ${outname} -----"
    grep -E "C:|S:|D:|F:|M:|n:" $(ls ${summary} | head -1) | head -10
  fi
done

# =============================================
# Combine BUSCO summaries with generate_plot.py
# =============================================
echo ""
echo "=== Step 4: Generate BUSCO comparison plot ==="
date

mkdir -p ${BUSCO_OUT}/summaries
for outname in hifiasm_primary hifiasm_hap1 hifiasm_hap2 flye; do
  src=$(ls ${BUSCO_OUT}/${outname}/short_summary*.txt 2>/dev/null | head -1)
  if [ -f "${src}" ]; then
    cp ${src} ${BUSCO_OUT}/summaries/
  fi
done

if [ -d ${BUSCO_OUT}/summaries ] && [ "$(ls ${BUSCO_OUT}/summaries)" ]; then
  cd ${BUSCO_OUT}/summaries
  generate_plot.py -wd . 2>&1 || python3 $(which generate_plot.py) -wd . 2>&1 || echo "generate_plot.py not available, skipping plot"
fi

echo ""
echo "=== Done! ==="
date
echo ""
echo "Key output files:"
echo "  QUAST report:         ${QUAST_OUT}/report.html  (open in browser)"
echo "  QUAST txt:            ${QUAST_OUT}/report.txt"
echo "  BUSCO summaries:      ${BUSCO_OUT}/summaries/"
echo "  BUSCO comparison plot: ${BUSCO_OUT}/summaries/busco_figure.png"

