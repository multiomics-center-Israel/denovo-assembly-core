#!/bin/bash
#$ -S /bin/bash
#$ -N hifiasm_ont
#$ -cwd
#$ -j y
#$ -e /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/05.Assembly/hifiasm_ont.err
#$ -o /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/05.Assembly/hifiasm_ont.log
#$ -q bioinfo.q
#$ -pe shared 32

# =============================================
# Paths Setup
# =============================================
ONT_READS=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/03.Raw_reads_QC/01.ONT/03.Kaiju/02.kaiju_2nd_run/data/Fillout_Generic/Chopper/Q2H9QN/Q2H9QN_filtered_chopper.fastq

WORK_DIR=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/05.Assembly/01.hifiasm
SAMPLE_NAME=Coelastrella

THREADS=32

# =============================================
# Environment
# =============================================
source /gpfs0/system/conda/miniconda2/etc/profile.d/conda.sh
conda activate /gpfs0/system/conda/miniconda2/envs/Mamba/envs/hifiasm || conda activate hifiasm

echo "=== Environment ==="
echo "Hostname: $(hostname)"
date
hifiasm --version 2>&1 | head -1
echo ""
echo "Input reads:"
ls -lah ${ONT_READS}
echo ""

# =============================================
# Create output directory
# =============================================
mkdir -p ${WORK_DIR}
cd ${WORK_DIR}

# =============================================
# Run Hifiasm in ONT mode
# =============================================
# --ont       : ONT R10.4+ SUP basecalled reads mode
# -o          : output prefix
# -t          : threads
# Output files (key ones):
#   ${SAMPLE_NAME}_hifiasm.bp.hap1.p_ctg.gfa  - haplotype 1 primary contigs
#   ${SAMPLE_NAME}_hifiasm.bp.hap2.p_ctg.gfa  - haplotype 2 primary contigs
#   ${SAMPLE_NAME}_hifiasm.bp.p_ctg.gfa       - primary contigs (collapsed-ish)
# =============================================
echo "=== Running Hifiasm (ONT mode) ==="
date

hifiasm \
  -o ${SAMPLE_NAME}_hifiasm \
  --ont \
  -t ${THREADS} \
  ${ONT_READS}

echo ""
echo "=== Convert GFA → FASTA ==="
date

# Convert all main GFA outputs to FASTA
for gfa in ${SAMPLE_NAME}_hifiasm.bp.hap1.p_ctg.gfa \
          ${SAMPLE_NAME}_hifiasm.bp.hap2.p_ctg.gfa \
          ${SAMPLE_NAME}_hifiasm.bp.p_ctg.gfa; do
  if [ -f ${gfa} ]; then
    out=${gfa%.gfa}.fa
    awk '/^S/{print ">"$2;print $3}' ${gfa} > ${out}
    echo "  Created: ${out}"
  fi
done

# =============================================
# Quick assembly stats
# =============================================
echo ""
echo "=== Quick assembly stats ==="
date

for fa in *.fa; do
  echo ""
  echo "--- $fa ---"
  # Count contigs
  num_contigs=$(grep -c "^>" ${fa})
  echo "Number of contigs: ${num_contigs}"
  # Total length
  total_len=$(awk '!/^>/{sum+=length($0)}END{print sum}' ${fa})
  echo "Total length: ${total_len} bp"
done

echo ""
echo "=== Done! ==="
date
echo ""
echo "Key output files for downstream evaluation:"
echo "  ${WORK_DIR}/${SAMPLE_NAME}_hifiasm.bp.p_ctg.fa     <- primary assembly"
echo "  ${WORK_DIR}/${SAMPLE_NAME}_hifiasm.bp.hap1.p_ctg.fa <- haplotype 1"
echo "  ${WORK_DIR}/${SAMPLE_NAME}_hifiasm.bp.hap2.p_ctg.fa <- haplotype 2"

