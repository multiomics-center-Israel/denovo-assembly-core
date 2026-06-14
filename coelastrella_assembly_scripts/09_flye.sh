#!/bin/bash
#$ -S /bin/bash
#$ -N flye
#$ -cwd
#$ -j y
#$ -e /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/05.Assembly/flye.err
#$ -o /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/05.Assembly/flye.log
#$ -q bioinfo.q
#$ -pe shared 32

# =============================================
# Paths Setup
# =============================================
ONT_READS=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/03.Raw_reads_QC/01.ONT/03.Kaiju/02.kaiju_2nd_run/data/Fillout_Generic/Chopper/Q2H9QN/Q2H9QN_filtered_chopper.fastq

WORK_DIR=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/05.Assembly/02.flye
SAMPLE_NAME=Coelastrella

THREADS=32
GENOME_SIZE=105m   # Based on GenomeScope2 estimate (~104.6 Mb)

# =============================================
# Environment
# =============================================
source /gpfs0/system/conda/miniconda2/etc/profile.d/conda.sh
conda activate /gpfs0/system/conda/miniconda2/envs/Long_short_assembly

echo "=== Environment ==="
echo "Hostname: $(hostname)"
date
flye --version 2>&1 | head -1
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
# Run Flye
# =============================================
# --nano-hq         : SUP basecalled reads (Q20+)
# --genome-size     : helps Flye allocate memory; from GenomeScope2 estimate
# -t                : threads
# --out-dir         : output directory
# =============================================
echo "=== Running Flye ==="
date

flye \
  --nano-hq ${ONT_READS} \
  --genome-size ${GENOME_SIZE} \
  --out-dir ${WORK_DIR}/flye_output \
  --threads ${THREADS}

echo ""
echo "=== Output files ==="
date
ls -lah ${WORK_DIR}/flye_output/

# =============================================
# Quick assembly stats
# =============================================
echo ""
echo "=== Quick stats ==="
ASM=${WORK_DIR}/flye_output/assembly.fasta
if [ -f ${ASM} ]; then
  num_contigs=$(grep -c "^>" ${ASM})
  echo "Number of contigs: ${num_contigs}"
  total_len=$(awk '!/^>/{sum+=length($0)}END{print sum}' ${ASM})
  echo "Total length: ${total_len} bp"
else
  echo "WARNING: assembly.fasta not found!"
fi

echo ""
echo "=== Done! ==="
date
echo ""
echo "Key output files:"
echo "  ${WORK_DIR}/flye_output/assembly.fasta        <- final assembly"
echo "  ${WORK_DIR}/flye_output/assembly_info.txt     <- contig stats"
echo "  ${WORK_DIR}/flye_output/assembly_graph.gfa    <- assembly graph"

