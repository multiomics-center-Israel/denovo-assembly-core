#!/bin/bash
#$ -S /bin/bash
#$ -N kaiju_illumina
#$ -cwd
#$ -j y
#$ -e /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/03.Raw_reads_QC/02.Illumina/02.kaiju/kaiju_illumina.err
#$ -o /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/03.Raw_reads_QC/02.Illumina/02.kaiju/kaiju_illumina.log
#$ -q bioinfo.q
#$ -pe shared 16

# =============================================
# =============================================
ILLUMINA_DIR=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/03.Raw_reads_QC/02.Illumina/01.fastp/fastp_output
R1=${ILLUMINA_DIR}/Coelastrella_R1.clean.fastq.gz
R2=${ILLUMINA_DIR}/Coelastrella_R2.clean.fastq.gz

WORK_DIR=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/03.Raw_reads_QC/02.Illumina/02.kaiju
SAMPLE_NAME=Coelastrella_illumina

KAIJU_DB_DIR=/gpfs0/system/conda/DataBases/Kaiju/2025
NODES=${KAIJU_DB_DIR}/nodes.dmp
NAMES=${KAIJU_DB_DIR}/names.dmp
FMI=${KAIJU_DB_DIR}/nr_euk/kaiju_db_nr_euk.fmi

# =============================================
# =============================================
source /gpfs0/system/conda/miniconda2/etc/profile.d/conda.sh
conda activate /gpfs0/system/conda/miniconda2/envs/Metagenomics

echo "=== Environment ==="
echo "Hostname: $(hostname)"
date
kaiju -h 2>&1 | head -2 || true
ktImportText 2>&1 | head -2 || true

# =============================================
# =============================================
mkdir -p ${WORK_DIR}
cd ${WORK_DIR}

# =============================================
# =============================================
echo ""
echo "=== Step 1: Kaiju (paired-end classification) ==="
date

kaiju \
  -t ${NODES} \
  -f ${FMI} \
  -i ${R1} \
  -j ${R2} \
  -o ${SAMPLE_NAME}_kaiju.out \
  -z 16 \
  -v

# =============================================
# =============================================
# echo ""
# echo "=== Step 2: Run kaiju table ==="
# date

#kaiju2table \
#  -t ${NODES} \
#  -n ${NAMES} \
#  -r s
#  -p \
#  -i ${SAMPLE_NAME}_kaiju.out \
#  -o ${SAMPLE_NAME}_kaiju_genus_summary.txt \

# =============================================
# =============================================
kaiju2table \
  -t ${NODES} \
  -n ${NAMES} \
  -r genus \
  -p \
  -o ${SAMPLE_NAME}_kaiju_genus.tsv \
   ${SAMPLE_NAME}_kaiju.out


# =============================================
# =============================================
echo ""
echo "=== Step 4: Convert to Krona format ==="
date

kaiju2krona \
  -t ${NODES} \
  -n ${NAMES} \
  -i ${SAMPLE_NAME}_kaiju.out \
  -o ${SAMPLE_NAME}_kaiju_krona.txt

# =============================================
# =============================================
echo ""
echo "=== Step 5: Generate Krona HTML plot ==="
date

ktImportText \
   ${SAMPLE_NAME}_kaiju_krona.txt \  
   -o ${SAMPLE_NAME}_krona_plot.html 

# =============================================
# =============================================
echo ""
echo "=== Summary ==="
date
echo "Total reads classified:"
grep -c "^C" ${SAMPLE_NAME}_kaiju.out
echo "Total reads unclassified:"
grep -c "^U" ${SAMPLE_NAME}_kaiju.out

echo ""
echo "=== Done! ==="
date
