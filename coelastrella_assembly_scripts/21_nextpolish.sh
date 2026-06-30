#!/bin/bash
#$ -S /bin/bash
#$ -N nextpolish
#$ -cwd
#$ -j y
#$ -e nextpolish.err
#$ -o nextpolish.log
#$ -q bioinfo.q
#$ -pe shared 32

source /gpfs0/system/conda/miniconda2/etc/profile.d/conda.sh
conda activate /gpfs0/system/conda/miniconda2/envs/Mamba/envs/nextpolish

echo "=== Environment ==="
echo "Hostname: $(hostname)"
echo "Working dir: $(pwd)"
which nextPolish
nextPolish --version

GENOME=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/07.purge_dups/Coelastrella_purged_final.fa
echo "=== Genome check ==="
ls -lh $GENOME

date
echo "=== Running NextPolish ==="
nextPolish run.cfg
NP_EXIT=$?
date
echo "=== NextPolish exit: $NP_EXIT ==="

echo ""
echo "=== Output files ==="
find ./01_polish_rundir -name "*.fasta" -o -name "*.fa" 2>/dev/null

FINAL=$(find ./01_polish_rundir -name "genome.nextpolish.fasta" | head -1)
if [ -f "$FINAL" ]; then
  cp "$FINAL" Coelastrella_nextpolish_final.fa
  echo ""
  echo "=== Final stats ==="
  source activate /gpfs0/system/conda/miniconda2/envs/Mamba/envs/seqkit
  seqkit stats -a Coelastrella_nextpolish_final.fa
fi
date
