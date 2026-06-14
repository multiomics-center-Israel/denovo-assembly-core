#!/bin/bash
#$ -S /bin/bash
#$ -N fcsgx_dl
#$ -cwd
#$ -j y
#$ -e fcsgx_dl.err
#$ -o fcsgx_dl.log
#$ -q bioinfo.q
#$ -pe shared 4

cd $(pwd)

source /gpfs0/system/conda/miniconda2/etc/profile.d/conda.sh
conda activate /gpfs0/system/conda/miniconda2/envs/Mamba/envs/fcsgx

DB_DIR=/gpfs0/bioinfo/databases/fcs_gxdb
MANIFEST=https://ftp.ncbi.nlm.nih.gov/genomes/TOOLS/FCS/database/latest/all.manifest

echo "=== Start ==="
date
echo "DB dir: $DB_DIR"
df -h $(dirname $DB_DIR) | tail -2
echo ""
which sync_files.py
echo ""

# הורדה - command syntax לפי --help
sync_files.py get \
  --mft $MANIFEST \
  --dir $DB_DIR

echo ""
echo "=== Files downloaded ==="
ls -lh $DB_DIR | head -30
du -sh $DB_DIR

echo ""
echo "=== Done ==="
date
