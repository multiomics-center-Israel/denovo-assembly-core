#!/bin/bash
#$ -S /bin/bash
#$ -N blobtools_decon
#$ -cwd
#$ -j y
#$ -e /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/05.Assembly/06.decontamination/blobtools.err
#$ -o /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/05.Assembly/06.decontamination/blobtools.log
#$ -q bioinfo.q
#$ -pe shared 32

# =============================================
# Paths Setup
# =============================================
ASSEMBLY_BASE=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/05.Assembly

ASSEMBLY=${ASSEMBLY_BASE}/04.polishing/02.pilon/Coelastrella_pilon.fasta

ONT_READS=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/03.Raw_reads_QC/01.ONT/02.Kaiju/02.kaiju_2nd_run/data/Fillout_Generic/Chopper/Q2H9QN/Q2H9QN_filtered_chopper.fastq
R1=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/03.Raw_reads_QC/02.Illumina/01.fastp/fastp_output/Coelastrella_R1.clean.fastq.gz
R2=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/03.Raw_reads_QC/02.Illumina/01.fastp/fastp_output/Coelastrella_R2.clean.fastq.gz

# Pre-computed BUSCO (from step 06)
BUSCO_FULL_TABLE=${ASSEMBLY_BASE}/05.final_evaluation/02.busco/pilon_polished/run_chlorophyta_odb10/full_table.tsv

WORK_DIR=${ASSEMBLY_BASE}/06.decontamination
SAMPLE=Coelastrella
BLOBDIR=${WORK_DIR}/${SAMPLE}_BlobDir

# Databases
DIAMOND_DB=/gpfs0/system/conda/DataBases/Blast/NR/DIAMOND/NR.dmnd
TAXDUMP=/gpfs0/system/conda/DataBases/Blast/NR/Taxonomy

THREADS=32

mkdir -p ${WORK_DIR}
cd ${WORK_DIR}

# =============================================
# Input verification
# =============================================
echo "=== Input files check ==="
date
for f in ${ASSEMBLY} ${ONT_READS} ${R1} ${R2} ${DIAMOND_DB} ${TAXDUMP}/nodes.dmp ${TAXDUMP}/names.dmp; do
  if [ -e ${f} ]; then
    echo "OK: ${f}"
  else
    echo "MISSING: ${f}"
    exit 1
  fi
done
echo ""

# =============================================================
# STEP 1: Map ONT reads to polished assembly (minimap2)
# =============================================================
echo "==============================================="
echo "STEP 1: Map ONT reads (minimap2)"
echo "==============================================="
date

source /gpfs0/system/conda/miniconda2/etc/profile.d/conda.sh
conda activate /gpfs0/system/conda/miniconda2/envs/Omics_QC

ONT_BAM=${WORK_DIR}/${SAMPLE}_ont.bam
if [ ! -f ${ONT_BAM} ]; then
  minimap2 -ax map-ont -t ${THREADS} ${ASSEMBLY} ${ONT_READS} | \
    samtools sort -@ ${THREADS} -o ${ONT_BAM} -
  samtools index ${ONT_BAM}
else
  echo "ONT BAM already exists, skipping"
fi
echo ""

# =============================================================
# STEP 2: Map Illumina reads to polished assembly (bwa)
# =============================================================
echo "==============================================="
echo "STEP 2: Map Illumina reads (bwa)"
echo "==============================================="
date

ILL_BAM=${WORK_DIR}/${SAMPLE}_illumina.bam
if [ ! -f ${ILL_BAM} ]; then
  # Use bwa (in Omics_QC) for simplicity
  bwa index ${ASSEMBLY}
  bwa mem -t ${THREADS} ${ASSEMBLY} ${R1} ${R2} | \
    samtools sort -@ ${THREADS} -o ${ILL_BAM} -
  samtools index ${ILL_BAM}
else
  echo "Illumina BAM already exists, skipping"
fi
echo ""

# Quick mapping stats
echo "ONT mapping stats:"
samtools flagstat ${ONT_BAM} | head -5
echo ""
echo "Illumina mapping stats:"
samtools flagstat ${ILL_BAM} | head -5
echo ""

# =============================================================
# STEP 3: Diamond blastx against NCBI NR
# =============================================================
echo "==============================================="
echo "STEP 3: Diamond blastx against NR (long step!)"
echo "==============================================="
date

conda deactivate
conda activate /gpfs0/system/conda/miniconda2/envs/Blast

DIAMOND_OUT=${WORK_DIR}/${SAMPLE}_diamond.out
if [ ! -f ${DIAMOND_OUT} ]; then
  diamond blastx \
    --db ${DIAMOND_DB} \
    --query ${ASSEMBLY} \
    --outfmt 6 qseqid staxids bitscore qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue \
    --sensitive \
    --max-target-seqs 1 \
    --evalue 1e-25 \
    --threads ${THREADS} \
    --out ${DIAMOND_OUT}
else
  echo "Diamond output already exists, skipping"
fi
echo ""
echo "Diamond hits: $(wc -l < ${DIAMOND_OUT})"
echo ""

# =============================================================
# STEP 4: Build BlobToolKit dataset
# =============================================================
echo "==============================================="
echo "STEP 4: Build BlobToolKit dataset"
echo "==============================================="
date

conda deactivate
conda activate /gpfs0/system/conda/miniconda2/envs/btk

# Create the BlobDir
if [ ! -d ${BLOBDIR} ]; then
  blobtools create --fasta ${ASSEMBLY} ${BLOBDIR}
else
  echo "BlobDir exists, will only add data"
fi

# Add coverage data (ONT)
echo ""
echo "--- Adding ONT coverage ---"
blobtools add --cov ${ONT_BAM} --threads ${THREADS} ${BLOBDIR}

# Add coverage data (Illumina)
echo ""
echo "--- Adding Illumina coverage ---"
blobtools add --cov ${ILL_BAM} --threads ${THREADS} ${BLOBDIR}

# Add taxonomy hits
echo ""
echo "--- Adding Diamond hits + taxonomy ---"
blobtools add \
  --hits ${DIAMOND_OUT} \
  --taxrule bestsumorder \
  --taxdump ${TAXDUMP} \
  --threads ${THREADS} \
  ${BLOBDIR}

# Add BUSCO results (if available)
if [ -f ${BUSCO_FULL_TABLE} ]; then
  echo ""
  echo "--- Adding BUSCO results ---"
  blobtools add --busco ${BUSCO_FULL_TABLE} ${BLOBDIR}
fi

# =============================================================
# STEP 5: Generate plots
# =============================================================
echo ""
echo "==============================================="
echo "STEP 5: Generate plots"
echo "==============================================="
date

# Static blob plot (PNG)
blobtools view --plot --view blob --out ${WORK_DIR}/${SAMPLE}_blob_plot ${BLOBDIR}
blobtools view --plot --view cumulative --out ${WORK_DIR}/${SAMPLE}_cumulative ${BLOBDIR}
blobtools view --plot --view snail --out ${WORK_DIR}/${SAMPLE}_snail ${BLOBDIR}

# =============================================================
# STEP 6: Summary report
# =============================================================
echo ""
echo "==============================================="
echo "STEP 6: Summary"
echo "==============================================="
date

# Show top phyla detected in the assembly
echo ""
echo "--- Top phyla in assembly ---"
blobtools filter --table ${WORK_DIR}/${SAMPLE}_summary.tsv ${BLOBDIR}
if [ -f ${WORK_DIR}/${SAMPLE}_summary.tsv ]; then
  head -20 ${WORK_DIR}/${SAMPLE}_summary.tsv
fi

echo ""
echo "=== Done! ==="
date
echo ""
echo "BlobDir:        ${BLOBDIR}"
echo "Static plots:   ${WORK_DIR}/${SAMPLE}_blob_plot*.png"
echo "Interactive:    blobtools host ${BLOBDIR}  (run separately - opens web UI)"
echo ""
echo "Next step: inspect the blob plot, identify contigs to remove (anomalous GC/coverage/taxonomy),"
echo "and apply blobtools filter to produce final clean assembly."

