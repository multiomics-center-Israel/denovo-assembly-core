#!/bin/bash
#$ -S /bin/bash
#$ -N centrifuge_ont
#$ -cwd
#$ -j y
#$ -e /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/03.Raw_reads_QC/01.ONT/04.Centrifuge/centrifuge_ont.err
#$ -o /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/03.Raw_reads_QC/01.ONT/04.Centrifuge/centrifuge_ont.log
#$ -q bioinfo.q
#$ -pe shared 16

# =============================================
# Paths Setup
# =============================================
ONT_FASTQ=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/03.Raw_reads_QC/01.ONT/03.Kaiju/02.kaiju_2nd_run/data/Fillout_Generic/Chopper/Q2H9QN/Q2H9QN_filtered_chopper.fastq

WORK_DIR=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/03.Raw_reads_QC/01.ONT/04.Centrifuge
SAMPLE_NAME=Coelastrella_ont

CENTRIFUGE_DB_DIR=/gpfs0/bioinfo/databases/Centrifuge/db_arch_bact_vir_2018
CENTRIFUGE_INDEX=${CENTRIFUGE_DB_DIR}/abv

# =============================================
# Environment Activation
# =============================================
source /gpfs0/system/conda/miniconda2/etc/profile.d/conda.sh
conda activate /gpfs0/system/conda/miniconda2/envs/Metagenomics

mkdir -p ${WORK_DIR}
cd ${WORK_DIR}

echo "=== Step 1: Centrifuge Run (ONT Mode) ==="
date

centrifuge \
  -x ${CENTRIFUGE_INDEX} \
  -U ${ONT_FASTQ} \
  --min-hitlen 100 \
  -S ${SAMPLE_NAME}_centrifuge.out \
  --report-file ${SAMPLE_NAME}_centrifuge_report.tsv \
  -p 16 \
  --time

echo "=== Step 2: Kraken-style report ==="
date

centrifuge-kreport \
  -x ${CENTRIFUGE_INDEX} \
  ${SAMPLE_NAME}_centrifuge.out \
  > ${SAMPLE_NAME}_centrifuge_kreport.txt

echo "=== Step 3: Krona plot (Via Text) ==="
date

ktImportText \
  -o ${SAMPLE_NAME}_centrifuge_krona.html \
  ${SAMPLE_NAME}_centrifuge_kreport.txt

echo "=== Done! ==="
date
