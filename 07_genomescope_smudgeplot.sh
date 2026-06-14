#!/bin/bash
#$ -S /bin/bash
#$ -N genomescope_smudgeplot
#$ -cwd
#$ -j y
#$ -e /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/04.Genome_size/genomescope.err
#$ -o /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/04.Genome_size/genomescope.log
#$ -q bioinfo.q
#$ -pe shared 16

# =============================================
# Paths Setup
# =============================================
R1=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/03.Raw_reads_QC/02.Illumina/01.fastp/fastp_output/Coelastrella_R1.clean.fastq.gz
R2=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/03.Raw_reads_QC/02.Illumina/01.fastp/fastp_output/Coelastrella_R2.clean.fastq.gz

WORK_DIR=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/04.Genome_size
SAMPLE_NAME=Coelastrella

KMER_LEN=21          # standard k for genome size estimation
PLOIDY=2             # initial guess (smudgeplot will confirm)
THREADS=16
MEMORY_GB=64         # KMC memory limit

# =============================================
# Environment Activation
# =============================================
source /gpfs0/system/conda/miniconda2/etc/profile.d/conda.sh
conda activate /gpfs0/system/conda/miniconda2/envs/Mamba/envs/genomescope || conda activate genomescope

echo "=== Environment ==="
echo "Hostname: $(hostname)"
date
kmc --version 2>&1 | head -1
genomescope2 --help 2>&1 | head -1 || echo "genomescope2 ready"
smudgeplot.py --version

# =============================================
# Create output directories
# =============================================
mkdir -p ${WORK_DIR}/kmc_tmp ${WORK_DIR}/genomescope_out ${WORK_DIR}/smudgeplot_out
cd ${WORK_DIR}

# =============================================
# Step 1: KMC k-mer counting
# =============================================
echo ""
echo "=== Step 1: KMC k-mer counting (k=${KMER_LEN}) ==="
date

# Build input file list
echo "${R1}" > FILES_${SAMPLE_NAME}.txt
echo "${R2}" >> FILES_${SAMPLE_NAME}.txt

kmc \
  -k${KMER_LEN} \
  -t${THREADS} \
  -m${MEMORY_GB} \
  -ci1 \
  -cs10000 \
  @FILES_${SAMPLE_NAME}.txt \
  ${SAMPLE_NAME}_kmcdb \
  ${WORK_DIR}/kmc_tmp

# =============================================
# Step 2: Generate histogram
# =============================================
echo ""
echo "=== Step 2: Generate k-mer histogram ==="
date

kmc_tools transform ${SAMPLE_NAME}_kmcdb histogram ${SAMPLE_NAME}_k${KMER_LEN}.hist -cx10000

echo "Histogram preview (first 20 lines):"
head -20 ${SAMPLE_NAME}_k${KMER_LEN}.hist

# =============================================
# Step 3: GenomeScope2 analysis
# =============================================
echo ""
echo "=== Step 3: GenomeScope2 analysis ==="
date

genomescope2 \
  -i ${SAMPLE_NAME}_k${KMER_LEN}.hist \
  -o genomescope_out \
  -k ${KMER_LEN} \
  -p ${PLOIDY} \
  -n ${SAMPLE_NAME}

echo "GenomeScope2 output files:"
ls -la genomescope_out/

# =============================================
# Step 4: Smudgeplot - ploidy detection
# =============================================
echo ""
echo "=== Step 4: Smudgeplot - ploidy detection ==="
date

# Compute coverage cutoffs from histogram
L=$(smudgeplot.py cutoff ${SAMPLE_NAME}_k${KMER_LEN}.hist L)
U=$(smudgeplot.py cutoff ${SAMPLE_NAME}_k${KMER_LEN}.hist U)
echo "Coverage cutoffs: L=${L}, U=${U}"

# Save cutoffs for documentation
echo "L=${L}" > smudgeplot_out/cutoffs.txt
echo "U=${U}" >> smudgeplot_out/cutoffs.txt

# Smudgeplot v0.4 - hetmers directly from KMC database
smudgeplot.py hetmers \
  -L ${L} \
  -t ${THREADS} \
  -o smudgeplot_out/${SAMPLE_NAME}_pairs \
  ${SAMPLE_NAME}_kmcdb

# Generate the plot
smudgeplot.py plot \
  -o smudgeplot_out/${SAMPLE_NAME} \
  smudgeplot_out/${SAMPLE_NAME}_pairs_text.smu

echo "Smudgeplot output files:"
ls -la smudgeplot_out/

# =============================================
# Cleanup temporary files
# =============================================
echo ""
echo "=== Cleanup ==="
rm -rf ${WORK_DIR}/kmc_tmp
rm -f FILES_${SAMPLE_NAME}.txt

echo ""
echo "=== Done! ==="
date
echo ""
echo "Key output files to review:"
echo "  GenomeScope2 plots:    ${WORK_DIR}/genomescope_out/${SAMPLE_NAME}_linear_plot.png"
echo "  GenomeScope2 summary:  ${WORK_DIR}/genomescope_out/${SAMPLE_NAME}_summary.txt"
echo "  Smudgeplot:            ${WORK_DIR}/smudgeplot_out/${SAMPLE_NAME}_smudgeplot.png"

