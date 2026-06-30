#!/bin/bash
#$ -S /bin/bash
#$ -N blast_validate
#$ -cwd
#$ -j y
#$ -e /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/05.Assembly/07.reference_validation/blast.err
#$ -o /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/05.Assembly/07.reference_validation/blast.log
#$ -q bioinfo.q
#$ -pe shared 8

# =============================================
# Paths Setup
# =============================================
ASSEMBLY=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/05.Assembly/04.polishing/02.pilon/Coelastrella_pilon.fasta

# Reference files (in PROJECT_DOC folder)
REF_NUC=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/05.Assembly/07.reference_validation/Coelastrella_reference_nucleotide.fa
REF_PEP=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/05.Assembly/07.reference_validation/Coelastrella_reference_peptide.fa

WORK_DIR=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/05.Assembly/07.reference_validation
THREADS=8

mkdir -p ${WORK_DIR}
cd ${WORK_DIR}

# =============================================
# Environment
# =============================================
source /gpfs0/system/conda/miniconda2/etc/profile.d/conda.sh
conda activate /gpfs0/system/conda/miniconda2/envs/Omics_QC

echo "=== Environment ==="
echo "Hostname: $(hostname)"
date
blastn -version
tblastn -version 2>&1 | head -1

# =============================================
# Input check
# =============================================
echo ""
echo "=== Input check ==="
for f in ${ASSEMBLY} ${REF_NUC} ${REF_PEP}; do
  if [ -f ${f} ]; then
    echo "OK: ${f} ($(du -h ${f} | cut -f1))"
  else
    echo "MISSING: ${f}"
    exit 1
  fi
done

echo ""
echo "Nucleotide references:"
grep "^>" ${REF_NUC}
echo ""
echo "Peptide references:"
grep "^>" ${REF_PEP}

# =============================================
# Step 1: Build BLAST DB from assembly
# =============================================
echo ""
echo "==============================================="
echo "STEP 1: Build BLAST DB from assembly"
echo "==============================================="
date

ASSEMBLY_DB=${WORK_DIR}/assembly_db
if [ ! -f ${ASSEMBLY_DB}.nhr ]; then
  makeblastdb -in ${ASSEMBLY} -dbtype nucl -out ${ASSEMBLY_DB} -title Coelastrella_polished
else
  echo "DB already exists, skipping"
fi

# =============================================
# Step 2: blastn (nucleotide vs nucleotide)
# =============================================
echo ""
echo "==============================================="
echo "STEP 2: blastn - nucleotide references"
echo "==============================================="
date

BLASTN_OUT=${WORK_DIR}/blastn_results.tsv

# -dust yes uses soft-masking (lowercase regions = repeats/low-complexity, masked from seeding)
# This gives more biologically meaningful results when case is preserved
blastn \
  -query ${REF_NUC} \
  -db ${ASSEMBLY_DB} \
  -outfmt "6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore qlen slen qcovs" \
  -evalue 1e-50 \
  -max_target_seqs 5 \
  -dust yes \
  -num_threads ${THREADS} \
  -out ${BLASTN_OUT}

# Add header
HEADER=$(echo -e "query\tcontig\tpident\tlength\tmismatch\tgapopen\tqstart\tqend\tsstart\tsend\tevalue\tbitscore\tqlen\tslen\tqcovs")
echo "${HEADER}" > ${WORK_DIR}/blastn_results_with_header.tsv
cat ${BLASTN_OUT} >> ${WORK_DIR}/blastn_results_with_header.tsv

# =============================================
# Step 3: tblastn (peptide vs nucleotide assembly)
# =============================================
echo ""
echo "==============================================="
echo "STEP 3: tblastn - peptide references"
echo "==============================================="
date

TBLASTN_OUT=${WORK_DIR}/tblastn_results.tsv

tblastn \
  -query ${REF_PEP} \
  -db ${ASSEMBLY_DB} \
  -outfmt "6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore qlen slen qcovs" \
  -evalue 1e-30 \
  -max_target_seqs 5 \
  -num_threads ${THREADS} \
  -out ${TBLASTN_OUT}

echo "${HEADER}" > ${WORK_DIR}/tblastn_results_with_header.tsv
cat ${TBLASTN_OUT} >> ${WORK_DIR}/tblastn_results_with_header.tsv

# =============================================
# Step 4: Summary report
# =============================================
echo ""
echo "================================================"
echo "STEP 4: Validation Summary"
echo "================================================"
date

echo ""
echo "--- BLASTN best hits (nucleotide vs nucleotide) ---"
printf "%-22s | %-25s | %8s | %8s | %10s\n" "Reference" "Contig" "%Identity" "Coverage" "Length"
echo "------------------------------------------------------------------------------"
awk -F'\t' '!seen[$1]++ {
  qcov = ($4 / $13) * 100
  printf "%-22s | %-25s | %7.2f%% | %7.1f%% | %10d\n", $1, $2, $3, qcov, $4
}' ${BLASTN_OUT} | sort
echo "------------------------------------------------------------------------------"

echo ""
echo "--- TBLASTN best hits (protein vs nucleotide assembly) ---"
printf "%-22s | %-25s | %8s | %8s | %10s\n" "Peptide" "Contig" "%Identity" "Coverage" "Length"
echo "------------------------------------------------------------------------------"
awk -F'\t' '!seen[$1]++ {
  qcov = ($4 / $13) * 100
  printf "%-22s | %-25s | %7.2f%% | %7.1f%% | %10d\n", $1, $2, $3, qcov, $4
}' ${TBLASTN_OUT} | sort
echo "------------------------------------------------------------------------------"

echo ""
echo "=== Identify CHLOROPLAST contigs (combined from blastn + tblastn) ==="
echo "(contigs that contain rbcs, psbA, or psbD2 genes)"
(
  grep -iE "^(rbcs|psba|psbd2|pbsd2)" ${BLASTN_OUT} 2>/dev/null
  grep -iE "^(rbcs|psba|psbd2|pbsd2)" ${TBLASTN_OUT} 2>/dev/null
) | awk -F'\t' '{print $2}' | sort -u | while read contig; do
  if [ -n "${contig}" ]; then
    len=$(awk -v c="${contig}" 'BEGIN{RS=">"} $1==c {gsub(/\n/,"",$0); print length($0)-length($1)}' ${ASSEMBLY})
    echo "  ${contig}  (length: ${len} bp)"
  fi
done

echo ""
echo "=== Identify NUCLEAR ribosomal contig ==="
grep -i "^WT2_18S_ITS" ${BLASTN_OUT} | awk -F'\t' '!seen[$2]++ {print "  " $2 "  (identity: " $3 "%, length: " $4 " bp)"}'

echo ""
echo "=== Hits per reference ==="
echo "BLASTN:"
awk -F'\t' '{print $1}' ${BLASTN_OUT} | sort | uniq -c | sort -rn
echo ""
echo "TBLASTN:"
awk -F'\t' '{print $1}' ${TBLASTN_OUT} | sort | uniq -c | sort -rn

echo ""
echo "=== Done! ==="
date
echo ""
echo "Outputs:"
echo "  ${WORK_DIR}/blastn_results_with_header.tsv   <- nucleotide BLAST hits"
echo "  ${WORK_DIR}/tblastn_results_with_header.tsv  <- protein BLAST hits"

