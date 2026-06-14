#!/bin/bash
#$ -S /bin/bash
#$ -N tiara
#$ -cwd
#$ -j y
#$ -e tiara.err
#$ -o tiara.log
#$ -q bioinfo.q
#$ -pe shared 16

cd $(pwd)

source /gpfs0/system/conda/miniconda2/etc/profile.d/conda.sh
conda activate /gpfs0/system/conda/miniconda2/envs/Mamba/envs/tiara

ASSEMBLY=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/09.polypolish/Coelastrella_polypolish_pypolca_final.fa

echo "=== Environment ==="
echo "Host: $(hostname)"
python --version
ls -lh $ASSEMBLY

date
echo "=== Running Tiara ==="

# Tiara correct flags:
#   -i input fasta
#   -o output classification table
#   -m 1000 : min contig length (default 5000 - our smallest is 1623)
#   -t 16 threads
#   --to_fasta all : split assembly into separate FASTA per class
#   --probabilities : also output per-contig probabilities

tiara \
  -i $ASSEMBLY \
  -o classification.txt \
  -m 1000 \
  -t 16 \
  --to_fasta all \
  --probabilities

echo ""
echo "=== Output files ==="
ls -la

echo ""
echo "=== Classification table (full) ==="
column -t classification.txt

echo ""
echo "=== Class counts (primary classification, column 2) ==="
awk -F'\t' 'NR>1 {print $2}' classification.txt | sort | uniq -c | sort -rn

echo ""
echo "=== Eukaryote sub-classification (column 3 - organelle vs nuclear) ==="
awk -F'\t' 'NR>1 && $3!="n/a" {print $3}' classification.txt | sort | uniq -c | sort -rn

echo ""
echo "=== Class lengths ==="
conda deactivate
conda activate /gpfs0/system/conda/miniconda2/envs/Mamba/envs/seqkit
seqkit fx2tab -nl $ASSEMBLY | awk '{print $1"\t"$2}' > contig_lengths.tsv

awk -F'\t' 'NR==FNR {len[$1]=$2; next} NR>1 {if($1 in len){print $2"\t"len[$1]}}' \
  contig_lengths.tsv classification.txt | \
  awk -F'\t' '{sum[$1]+=$2; cnt[$1]++} END {for (c in sum) printf "%-25s %3d contigs  %12s bp\n", c, cnt[c], sum[c]}' | \
  sort -k4 -rn

date
echo "=== DONE ==="
