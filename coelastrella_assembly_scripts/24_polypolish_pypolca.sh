#!/bin/bash
#$ -S /bin/bash
#$ -N polypolish
#$ -cwd
#$ -j y
#$ -e polypolish.err
#$ -o polypolish.log
#$ -q bioinfo.q
#$ -pe shared 16

cd $(pwd)

source /gpfs0/system/conda/miniconda2/etc/profile.d/conda.sh
conda activate /gpfs0/system/conda/miniconda2/envs/Mamba/envs/polypolish

# Paths
INPUT_ASSEMBLY=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/08.nextpolish/Coelastrella_nextpolish_final.fa
R1=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/03.Raw_reads_QC/02.Illumina/01.fastp/fastp_output/Coelastrella_R1.clean.fastq.gz
R2=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/03.Raw_reads_QC/02.Illumina/01.fastp/fastp_output/Coelastrella_R2.clean.fastq.gz
THREADS=16

echo "=== Environment ==="
echo "Host: $(hostname)"
which polypolish pypolca bwa samtools
polypolish --version
pypolca --version
echo ""
ls -lh $INPUT_ASSEMBLY $R1 $R2

set -e
set -x
date

# Step 1: Copy and index assembly
echo ">>> Step 1: BWA index"
cp $INPUT_ASSEMBLY assembly.fa
bwa index assembly.fa

# Step 2: Map R1 and R2 SEPARATELY (Polypolish requirement)
echo ">>> Step 2: BWA mem (R1 and R2 separately, -a for all alignments)"
bwa mem -t $THREADS -a assembly.fa $R1 > alignments_1.sam 2> bwa_R1.log
bwa mem -t $THREADS -a assembly.fa $R2 > alignments_2.sam 2> bwa_R2.log
ls -lh alignments_*.sam

# Step 3: Polypolish filter (handle insert sizes)
echo ">>> Step 3: Polypolish filter"
polypolish filter \
  --in1 alignments_1.sam \
  --in2 alignments_2.sam \
  --out1 filtered_1.sam \
  --out2 filtered_2.sam 2> polypolish_filter.log

# Step 4: Polypolish polish
echo ">>> Step 4: Polypolish polish"
polypolish polish assembly.fa filtered_1.sam filtered_2.sam \
  > polypolish.fasta 2> polypolish_polish.log

ls -lh polypolish.fasta

# Cleanup intermediate heavy files
rm -f alignments_1.sam alignments_2.sam filtered_1.sam filtered_2.sam
rm -f assembly.fa.*  # bwa index files (.amb .ann .bwt .pac .sa)

date

# Step 5: Pypolca (conservative paired-end based)
echo ">>> Step 5: Pypolca"
pypolca run \
  -a polypolish.fasta \
  -1 $R1 \
  -2 $R2 \
  -t $THREADS \
  -o pypolca_out

# Final output
if [ -f pypolca_out/pypolca_corrected.fasta ]; then
  cp pypolca_out/pypolca_corrected.fasta Coelastrella_polypolish_pypolca_final.fa
fi

# Stats
echo ""
echo "=== Final stats ==="
conda deactivate
conda activate /gpfs0/system/conda/miniconda2/envs/Mamba/envs/seqkit

echo "--- Input (NextPolish) ---"
seqkit stats -a $INPUT_ASSEMBLY

echo ""
echo "--- After Polypolish only ---"
seqkit stats -a polypolish.fasta

echo ""
echo "--- After Polypolish + Pypolca (final) ---"
seqkit stats -a Coelastrella_polypolish_pypolca_final.fa 2>/dev/null

date
echo "=== DONE ==="
