#!/bin/bash
#$ -S /bin/bash
#$ -N blobtools_fast
#$ -cwd
#$ -j y
#$ -e /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/05.Assembly/06.decontamination/blobtools_fast.err
#$ -o /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/05.Assembly/06.decontamination/blobtools_fast.log
#$ -q bioinfo.q
#$ -pe shared 32

# =============================================
# Paths Setup
# =============================================
ASSEMBLY_BASE=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/05.Assembly

ASSEMBLY=${ASSEMBLY_BASE}/04.polishing/02.pilon/Coelastrella_pilon.fasta

# Pre-existing BAM files from the previous (sensitive) run - REUSE these!
WORK_DIR=${ASSEMBLY_BASE}/06.decontamination
ONT_BAM=${WORK_DIR}/Coelastrella_ont.bam
ILL_BAM=${WORK_DIR}/Coelastrella_illumina.bam

# Pre-computed BUSCO from final evaluation
BUSCO_FULL_TABLE=${ASSEMBLY_BASE}/05.final_evaluation/02.busco/pilon_polished/run_chlorophyta_odb10/full_table.tsv

SAMPLE=Coelastrella
BLOBDIR=${WORK_DIR}/${SAMPLE}_BlobDir

# Databases
DIAMOND_DB=/gpfs0/system/conda/DataBases/Blast/NR/DIAMOND/NR.dmnd
TAXDUMP=/gpfs0/system/conda/DataBases/Blast/NR/Taxonomy

THREADS=32

cd ${WORK_DIR}

# =============================================
# Input verification - all files should already exist!
# =============================================
echo "=== Input files check ==="
date
for f in ${ASSEMBLY} ${ONT_BAM} ${ILL_BAM} ${DIAMOND_DB} ${TAXDUMP}/nodes.dmp ${TAXDUMP}/names.dmp; do
  if [ -e ${f} ]; then
    echo "OK: ${f}  ($(du -h ${f} 2>/dev/null | cut -f1))"
  else
    echo "MISSING: ${f}"
    exit 1
  fi
done

# =============================================================
# STEP 1: Diamond blastx in FAST mode
# (Reusing existing BAM files - skipping read mapping!)
# =============================================================
echo ""
echo "==============================================="
echo "STEP 1: Diamond blastx in --fast mode"
echo "(estimated time: 4-8 hours instead of 2-3 days)"
echo "==============================================="
date

source /gpfs0/system/conda/miniconda2/etc/profile.d/conda.sh
conda activate /gpfs0/system/conda/miniconda2/envs/Blast

DIAMOND_OUT=${WORK_DIR}/${SAMPLE}_diamond_fast.out
if [ -f ${DIAMOND_OUT} ] && [ -s ${DIAMOND_OUT} ]; then
  echo "Diamond fast output already exists, skipping"
else
  # Remove any leftover empty file from previous attempt
  rm -f ${WORK_DIR}/${SAMPLE}_diamond.out

  diamond blastx \
    --db ${DIAMOND_DB} \
    --query ${ASSEMBLY} \
    --outfmt 6 qseqid staxids bitscore qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue \
    --fast \
    --max-target-seqs 1 \
    --evalue 1e-25 \
    --threads ${THREADS} \
    --out ${DIAMOND_OUT}
fi

echo ""
echo "Diamond hits: $(wc -l < ${DIAMOND_OUT})"
echo "Diamond output size: $(du -h ${DIAMOND_OUT} | cut -f1)"

# =============================================================
# STEP 2: Build BlobToolKit dataset
# =============================================================
echo ""
echo "==============================================="
echo "STEP 2: Build BlobToolKit dataset"
echo "==============================================="
date

conda deactivate
conda activate /gpfs0/system/conda/miniconda2/envs/btk

# Create the BlobDir (skip if exists from before)
if [ ! -d ${BLOBDIR} ]; then
  blobtools create --fasta ${ASSEMBLY} ${BLOBDIR}
else
  echo "BlobDir exists, will only add data"
fi

# Add coverage data (ONT)
echo ""
echo "--- Adding ONT coverage ---"
date
blobtools add --cov ${ONT_BAM} --threads ${THREADS} ${BLOBDIR}

# Add coverage data (Illumina)
echo ""
echo "--- Adding Illumina coverage ---"
date
blobtools add --cov ${ILL_BAM} --threads ${THREADS} ${BLOBDIR}

# Add taxonomy hits
echo ""
echo "--- Adding Diamond hits + taxonomy ---"
date
blobtools add \
  --hits ${DIAMOND_OUT} \
  --taxrule bestsumorder \
  --taxdump ${TAXDUMP} \
  --threads ${THREADS} \
  ${BLOBDIR}

# Add BUSCO results
if [ -f ${BUSCO_FULL_TABLE} ]; then
  echo ""
  echo "--- Adding BUSCO results ---"
  date
  blobtools add --busco ${BUSCO_FULL_TABLE} ${BLOBDIR}
fi

# =============================================================
# STEP 3: Generate plots
# =============================================================
echo ""
echo "==============================================="
echo "STEP 3: Generate plots"
echo "==============================================="
date

blobtools view --plot --view blob --out ${WORK_DIR}/${SAMPLE}_blob_plot ${BLOBDIR}
blobtools view --plot --view cumulative --out ${WORK_DIR}/${SAMPLE}_cumulative ${BLOBDIR}
blobtools view --plot --view snail --out ${WORK_DIR}/${SAMPLE}_snail ${BLOBDIR}

# =============================================================
# STEP 4: Summary
# =============================================================
echo ""
echo "==============================================="
echo "STEP 4: Summary"
echo "==============================================="
date

echo ""
echo "--- Per-taxon summary ---"
blobtools filter --table ${WORK_DIR}/${SAMPLE}_summary.tsv ${BLOBDIR}
if [ -f ${WORK_DIR}/${SAMPLE}_summary.tsv ]; then
  head -30 ${WORK_DIR}/${SAMPLE}_summary.tsv
fi

echo ""
echo "=== Done! ==="
date
echo ""
echo "BlobDir:        ${BLOBDIR}"
echo "Static plots:   ${WORK_DIR}/${SAMPLE}_blob_plot*.png"
echo "Interactive:    blobtools host ${BLOBDIR}  (run separately - opens web UI)"

