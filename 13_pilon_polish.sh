#!/bin/bash
#$ -S /bin/bash
#$ -N pilon_polish
#$ -cwd
#$ -j y
#$ -e /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/05.Assembly/04.polishing/02.pilon/pilon.err
#$ -o /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/05.Assembly/04.polishing/02.pilon/pilon.log
#$ -q bioinfo.q
#$ -pe shared 32

# =============================================
# Paths Setup
# =============================================
ASSEMBLY_BASE=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/05.Assembly

# Input - the Medaka-polished assembly (output of step 04)
MEDAKA_ASSEMBLY=${ASSEMBLY_BASE}/04.polishing/01.medaka/Coelastrella_hifiasm_medaka.fa
# Fallback name if rename didn't happen
[ ! -f ${MEDAKA_ASSEMBLY} ] && MEDAKA_ASSEMBLY=${ASSEMBLY_BASE}/04.polishing/01.medaka/consensus.fasta

# Illumina reads
R1=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/03.Raw_reads_QC/02.Illumina/01.fastp/fastp_output/Coelastrella_R1.clean.fastq.gz
R2=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/03.Raw_reads_QC/02.Illumina/01.fastp/fastp_output/Coelastrella_R2.clean.fastq.gz

WORK_DIR=${ASSEMBLY_BASE}/04.polishing/02.pilon
SAMPLE_NAME=Coelastrella

THREADS=32
JAVA_MEM=64G

mkdir -p ${WORK_DIR}
cd ${WORK_DIR}

# =============================================
# Environment - Long_short_assembly has bwa + samtools + Pilon together
# =============================================
source /gpfs0/system/conda/miniconda2/etc/profile.d/conda.sh
conda activate /gpfs0/system/conda/miniconda2/envs/Long_short_assembly

echo "=== Environment ==="
echo "Hostname: $(hostname)"
date
bwa 2>&1 | grep -i "Version:" | head -1
samtools --version | head -1
pilon --version 2>&1 || java -jar $(which pilon | xargs dirname)/../share/pilon-*/pilon.jar --version 2>&1 | head -1
echo ""

# =============================================
# Verify input files
# =============================================
echo "=== Input check ==="
for f in ${MEDAKA_ASSEMBLY} ${R1} ${R2}; do
  if [ -f ${f} ]; then
    echo "OK: ${f}  ($(du -h ${f} | cut -f1))"
  else
    echo "MISSING: ${f}"
    exit 1
  fi
done
echo ""

# =============================================
# Step 1: Copy draft assembly to working dir
# =============================================
echo "=== Step 1: Prepare draft assembly ==="
date
cp ${MEDAKA_ASSEMBLY} ${WORK_DIR}/draft.fa
DRAFT=${WORK_DIR}/draft.fa

# =============================================
# Step 2: Index draft with bwa
# =============================================
echo ""
echo "=== Step 2: BWA index ==="
date
bwa index ${DRAFT}

# =============================================
# Step 3: Map Illumina reads to draft
# =============================================
echo ""
echo "=== Step 3: BWA mem mapping (paired-end) ==="
date

bwa mem -t ${THREADS} ${DRAFT} ${R1} ${R2} | \
  samtools sort -@ ${THREADS} -o ${SAMPLE_NAME}_illumina.bam -

samtools index ${SAMPLE_NAME}_illumina.bam

# Quick mapping stats
echo ""
echo "=== Mapping stats ==="
samtools flagstat ${SAMPLE_NAME}_illumina.bam

# =============================================
# Step 4: Run Pilon
# =============================================
# --genome     : input draft assembly
# --frags      : paired-end BAM file
# --output     : output prefix
# --outdir     : output directory
# --threads    : threads
# --changes    : write changes file
# --vcf        : write VCF of corrections
# =============================================
echo ""
echo "=== Step 4: Pilon polishing ==="
date

pilon -Xmx${JAVA_MEM} \
  --genome ${DRAFT} \
  --frags ${SAMPLE_NAME}_illumina.bam \
  --output ${SAMPLE_NAME}_pilon \
  --outdir ${WORK_DIR} \
  --threads ${THREADS} \
  --changes \
  --vcf

# =============================================
# Step 5: Report results
# =============================================
echo ""
echo "=== Output files ==="
date
ls -lah ${WORK_DIR}/

POLISHED=${WORK_DIR}/${SAMPLE_NAME}_pilon.fasta
if [ -f ${POLISHED} ]; then
  echo ""
  echo "=== Quick stats on Pilon-polished assembly ==="
  num_contigs=$(grep -c "^>" ${POLISHED})
  total_len=$(awk '!/^>/{sum+=length($0)}END{print sum}' ${POLISHED})
  total_mb=$(awk "BEGIN{printf \"%.2f\", $total_len/1000000}")
  echo "Number of contigs: ${num_contigs}"
  echo "Total length:      ${total_len} bp  (${total_mb} Mb)"

  echo ""
  echo "=== Number of corrections made ==="
  if [ -f ${WORK_DIR}/${SAMPLE_NAME}_pilon.changes ]; then
    num_changes=$(wc -l < ${WORK_DIR}/${SAMPLE_NAME}_pilon.changes)
    echo "Pilon corrections: ${num_changes}"
    echo "(first 10 lines of changes file:)"
    head -10 ${WORK_DIR}/${SAMPLE_NAME}_pilon.changes
  fi

  # Cleanup intermediate files (optional - comment out to keep)
  # rm -f ${WORK_DIR}/draft.fa.*
  # rm -f ${WORK_DIR}/${SAMPLE_NAME}_illumina.bam*

else
  echo "WARNING: Pilon output not found!"
fi

echo ""
echo "=== Done! ==="
date
echo ""
echo "Final polished assembly:"
echo "  ${POLISHED}"
echo ""
echo "Next steps:"
echo "  1. Re-run BUSCO + QUAST on the polished assembly to verify improvement"
echo "  2. Optional: another iteration of Pilon"
echo "  3. BlobTools2 decontamination on final polished assembly"

