#!/bin/bash
#$ -S /bin/bash
#$ -N fastp_qc
#$ -cwd
#$ -j y
#$ -e /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/01.Raw_data/fastp_qc.err
#$ -o /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/01.Raw_data/fastp_qc.log
#$ -q bioinfo.q
#$ -pe shared 16

# =============================================
# =============================================
WORK_DIR=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/03.Raw_reads_QC/02.Illumina
R1=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/01.Raw_data/03.Illumina/WT-2_R1_001.fastq.gz
R2=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/01.Raw_data/03.Illumina/WT-2_R2_001.fastq.gz
SAMPLE_NAME=Coelastrella

# =============================================
# =============================================
source /gpfs0/system/conda/miniconda2/etc/profile.d/conda.sh
conda activate /gpfs0/system/conda/miniconda2/envs/Mamba/envs/fastp
# =============================================
echo "=== Environment ==="
echo "Hostname: $(hostname)"
fastqc --version
fastp --version
multiqc --version

# =============================================
cd ${WORK_DIR}
mkdir -p qc_raw qc_clean fastp_output multiqc_report

# =============================================
# =============================================
echo "=== Running FastQC on raw reads ==="
date
fastqc -t 16 -o qc_raw ${R1} ${R2}

# =============================================
# =============================================
echo "=== Running fastp ==="
date
fastp \
  -i ${R1} -I ${R2} \
  -o fastp_output/${SAMPLE_NAME}_R1.clean.fastq.gz \
  -O fastp_output/${SAMPLE_NAME}_R2.clean.fastq.gz \
  --detect_adapter_for_pe \
  --qualified_quality_phred 20 \
  --length_required 50 \
  --cut_tail --cut_tail_window_size 4 --cut_tail_mean_quality 20 \
  --thread 16 \
  --html fastp_output/${SAMPLE_NAME}_fastp.html \
  --json fastp_output/${SAMPLE_NAME}_fastp.json

# =============================================
# =============================================
echo "=== Running FastQC on clean reads ==="
date
fastqc -t 16 -o qc_clean \
  fastp_output/${SAMPLE_NAME}_R1.clean.fastq.gz \
  fastp_output/${SAMPLE_NAME}_R2.clean.fastq.gz

# =============================================
# שלב 4: MultiQC - איחוד דוחות
# =============================================
echo "=== Running MultiQC ==="
date
multiqc qc_raw qc_clean fastp_output \
  -o multiqc_report \
  --title "Coelastrella Illumina QC - before/after fastp"

echo "=== Done! ==="
date
