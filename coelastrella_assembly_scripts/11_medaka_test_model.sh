#!/bin/bash
#$ -S /bin/bash
#$ -N test_medaka
#$ -cwd
#$ -j y
#$ -o test_medaka.log
#$ -q bioinfo.q
#$ -pe shared 1

source /gpfs0/system/conda/miniconda2/etc/profile.d/conda.sh
conda activate /gpfs0/system/conda/miniconda2/envs/Mamba/envs/medaka

echo "Available models containing 'sup':"
medaka tools list_models 2>&1 | grep -E "sup|^Available" | head -30

