#!/bin/bash
#$ -S /bin/bash
#$ -N medaka_polish
#$ -cwd
#$ -j y
#$ -e /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/05.Assembly/04.polishing/01.medaka/medaka.err
#$ -o /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/05.Assembly/04.polishing/01.medaka/medaka.log
#$ -q bioinfo.q
#$ -pe shared 16

# =============================================
# Paths Setup
# =============================================
ASSEMBLY_BASE=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/05.Assembly

DRAFT=${ASSEMBLY_BASE}/01.hifiasm/Coelastrella_hifiasm.bp.p_ctg.fa
ONT_READS=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/03.Raw_reads_QC/01.ONT/03.Kaiju/02.kaiju_2nd_run/data/Fillout_Generic/Chopper/Q2H9QN/Q2H9QN_filtered_chopper.fastq

WORK_DIR=${ASSEMBLY_BASE}/04.polishing/01.medaka
SAMPLE_NAME=Coelastrella

THREADS=16

# =============================================
# Medaka model selection
# =============================================
# For ONT R10.4.1 + SUP basecalling with Dorado v5.2:
# Recommended: r1041_e82_400bps_sup_v5.2.0  (EXACT match to Dorado v5.2 SUP - default consensus model)
# Fallback:    r1041_e82_400bps_sup_v4.3.0  (more universal, safer)
# To check available models on this system after activating env:
#   medaka tools list_models
MODEL=r1041_e82_400bps_sup_v5.2.0

# =============================================
# Environment
# =============================================
source /gpfs0/system/conda/miniconda2/etc/profile.d/conda.sh
conda activate /gpfs0/system/conda/miniconda2/envs/Mamba/envs/medaka

echo "=== Environment ==="
echo "Hostname: $(hostname)"
echo "Date: $(date)"
medaka --version
echo ""
echo "Checking CPU AVX support (required for Medaka):"
grep -o 'avx[0-9_]*' /proc/cpuinfo | sort -u | head
echo ""

# =============================================
# Verify input files
# =============================================
echo "=== Input check ==="
for f in ${DRAFT} ${ONT_READS}; do
  if [ -f ${f} ]; then
    echo "OK: ${f}  ($(du -h ${f} | cut -f1))"
  else
    echo "MISSING: ${f}"
    exit 1
  fi
done
echo ""

# =============================================
# Create output directory
# =============================================
mkdir -p ${WORK_DIR}
cd ${WORK_DIR}

# =============================================
# Run medaka_consensus
# =============================================
# -i  : input reads (ONT)
# -d  : draft assembly
# -o  : output directory
# -t  : threads
# -m  : model
# medaka_consensus wraps:
#    minimap2 (map reads to draft) → medaka inference → stitch consensus
# =============================================
echo "=== Running medaka_consensus ==="
echo "Draft:   ${DRAFT}"
echo "Reads:   ${ONT_READS}"
echo "Model:   ${MODEL}"
echo "Threads: ${THREADS}"
date

medaka_consensus \
  -i ${ONT_READS} \
  -d ${DRAFT} \
  -o ${WORK_DIR} \
  -t ${THREADS} \
  -m ${MODEL}

# =============================================
# Rename and report
# =============================================
echo ""
echo "=== Output files ==="
date
ls -lah ${WORK_DIR}/

POLISHED=${WORK_DIR}/consensus.fasta
if [ -f ${POLISHED} ]; then
  # Copy to a clearer name
  cp ${POLISHED} ${WORK_DIR}/${SAMPLE_NAME}_hifiasm_medaka.fa
  echo ""
  echo "=== Quick stats on polished assembly ==="
  num_contigs=$(grep -c "^>" ${WORK_DIR}/${SAMPLE_NAME}_hifiasm_medaka.fa)
  total_len=$(awk '!/^>/{sum+=length($0)}END{print sum}' ${WORK_DIR}/${SAMPLE_NAME}_hifiasm_medaka.fa)
  total_mb=$(awk "BEGIN{printf \"%.2f\", $total_len/1000000}")
  echo "Number of contigs: ${num_contigs}"
  echo "Total length:      ${total_len} bp  (${total_mb} Mb)"
else
  echo "WARNING: consensus.fasta not found!"
fi

echo ""
echo "=== Done! ==="
date
echo ""
echo "Polished assembly: ${WORK_DIR}/${SAMPLE_NAME}_hifiasm_medaka.fa"
echo ""
echo "Next step: Pilon polishing using Illumina reads"

