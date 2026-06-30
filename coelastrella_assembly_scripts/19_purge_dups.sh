#!/bin/bash
#$ -S /bin/bash
#$ -N purge_dups
#$ -cwd
#$ -j y
#$ -e purge_dups.err
#$ -o purge_dups.log
#$ -q bioinfo.q
#$ -pe shared 16

ASSEMBLY=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/05.Assembly/06.decontamination/Coelastrella_decontaminated.fasta
ONT_READS=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/03.Raw_reads_QC/01.ONT/02.Kaiju/02.kaiju_2nd_run/data/Fillout_Generic/Chopper/Q2H9QN/Q2H9QN_filtered_chopper.fastq
THREADS=16
PREFIX=Coelastrella

source /gpfs0/system/conda/miniconda2/etc/profile.d/conda.sh
conda activate /gpfs0/system/conda/miniconda2/envs/Mamba/envs/purge_dups

echo "=== Tools check ==="
which minimap2
which pbcstat
which calcuts
which split_fa
which purge_dups
which get_seqs
echo "=== Input check ==="
ls -lh $ASSEMBLY
ls -lh $ONT_READS
echo "==================="

set -e
set -x
date

# Step 1: Map ONT reads → PAF
echo ">>> Step 1: minimap2 ONT mapping"
minimap2 -xmap-ont -t $THREADS $ASSEMBLY $ONT_READS \
  | gzip -c > ${PREFIX}.paf.gz

# Step 2: Coverage stats
echo ">>> Step 2: pbcstat + calcuts"
pbcstat ${PREFIX}.paf.gz   # → PB.base.cov, PB.stat
calcuts PB.stat > cutoffs 2> calcuts.log
echo "Cutoffs computed:"
cat cutoffs

# Step 3: Self-alignment
echo ">>> Step 3: split + self-align"
split_fa $ASSEMBLY > ${PREFIX}.split
minimap2 -xasm5 -DP -t $THREADS ${PREFIX}.split ${PREFIX}.split \
  | gzip -c > ${PREFIX}.split.self.paf.gz

# Step 4: Purge
echo ">>> Step 4: purge_dups"
purge_dups -2 -T cutoffs -c PB.base.cov ${PREFIX}.split.self.paf.gz \
  > dups.bed 2> purge_dups.log

# Step 5: Extract sequences
echo ">>> Step 5: get_seqs"
get_seqs -e dups.bed $ASSEMBLY
# Outputs: purged.fa + hap.fa in current dir

date
echo "=== DONE ==="
