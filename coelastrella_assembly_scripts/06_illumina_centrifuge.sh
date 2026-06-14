#!/bin/bash
#$ -S /bin/bash
#$ -N centrifuge_illumina
#$ -cwd
#$ -j y
#$ -e /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/03.Raw_reads_QC/02.Illumina/03.Centrifuge/centrifuge_illumina.err
#$ -o /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/03.Raw_reads_QC/02.Illumina/03.Centrifuge/centrifuge_illumina.log
#$ -q bioinfo.q
#$ -pe shared 16

# =============================================
# Paths Setup
# =============================================
ILLUMINA_DIR=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/03.Raw_reads_QC/02.Illumina/01.fastp
R1=${ILLUMINA_DIR}/fastp_output/Coelastrella_R1.clean.fastq.gz
R2=${ILLUMINA_DIR}/fastp_output/Coelastrella_R2.clean.fastq.gz

WORK_DIR=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/03.Raw_reads_QC/02.Illumina/03.Centrifuge
SAMPLE_NAME=Coelastrella_illumina

CENTRIFUGE_DB_DIR=/gpfs0/bioinfo/databases/Centrifuge/db_arch_bact_vir_2018
CENTRIFUGE_INDEX=${CENTRIFUGE_DB_DIR}/abv

TAXONOMY_DIR=${CENTRIFUGE_DB_DIR}/taxonomy

# =============================================
# Environment Activation
# =============================================
source /gpfs0/system/conda/miniconda2/etc/profile.d/conda.sh
conda activate /gpfs0/system/conda/miniconda2/envs/Metagenomics

echo "=== Environment ==="
echo "Hostname: $(hostname)"
date
centrifuge --version | head -1 || echo "centrifuge NOT FOUND"
ktImportTaxonomy 2>&1 | head -2 || echo "Krona NOT FOUND"

mkdir -p ${WORK_DIR}
cd ${WORK_DIR}

# =============================================
# Step 1: Centrifuge classification (paired-end)
# =============================================
echo ""
echo "=== Step 1: Centrifuge classification ==="
date

centrifuge \
  -x ${CENTRIFUGE_INDEX} \
  -1 ${R1} \
  -2 ${R2} \
  -S ${SAMPLE_NAME}_centrifuge.out \
  --report-file ${SAMPLE_NAME}_centrifuge_report.tsv \
  -p 16 \
  --time

# =============================================
# Step 2: Kraken-style hierarchical report
# =============================================
echo ""
echo "=== Step 2: Kraken-style report ==="
date

centrifuge-kreport \
  -x ${CENTRIFUGE_INDEX} \
  ${SAMPLE_NAME}_centrifuge.out \
  > ${SAMPLE_NAME}_centrifuge_kreport.txt

# =============================================
# Step 3: Krona plot (FIXED column order: readID first, taxID second)
# =============================================
echo ""
echo "=== Step 3: Krona plot ==="
date

# Centrifuge -S output columns: readID, seqID, taxID, score, ...
# ktImportTaxonomy expects: readID <TAB> taxID
awk -F"\t" 'NR>1 {print $1"\t"$3}' ${SAMPLE_NAME}_centrifuge.out > ${SAMPLE_NAME}_for_krona.txt

ktImportTaxonomy \
  -o ${SAMPLE_NAME}_centrifuge_krona.html \
  -tax ${TAXONOMY_DIR} \
  ${SAMPLE_NAME}_for_krona.txt

# =============================================
# Summary
# =============================================
echo ""
echo "=== Summary ==="
date

echo ""
echo "Report file header:"
head -1 ${SAMPLE_NAME}_centrifuge_report.tsv
echo ""

# Centrifuge report.tsv columns:
# 1: name | 2: taxID | 3: taxRank | 4: genomeSize | 5: numReads | 6: numUniqueReads | 7: abundance
echo "Top 20 taxa by abundance (name | numReads | numUniqueReads | abundance):"
tail -n +2 ${SAMPLE_NAME}_centrifuge_report.tsv | \
  sort -t$'\t' -k7,7 -nr | \
  head -20 | \
  awk -F"\t" '{printf "%-50s\t%s\t%s\t%s\n", $1, $5, $6, $7}'

echo ""
echo "Total classified reads:"
awk -F"\t" 'NR>1 && $3 != "0" {count++} END {print count}' ${SAMPLE_NAME}_centrifuge.out

echo ""
echo "Total unclassified reads:"
awk -F"\t" 'NR>1 && $3 == "0" {count++} END {print count}' ${SAMPLE_NAME}_centrifuge.out

echo ""
echo "=== Done! ==="
date

