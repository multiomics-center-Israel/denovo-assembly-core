#!/bin/bash
#$ -S /bin/bash
#$ -N busco_FINAL
#$ -cwd
#$ -j y
#$ -e busco_FINAL.err
#$ -o busco_FINAL.log
#$ -q bioinfo.q
#$ -pe shared 16

cd $(pwd)
source /gpfs0/system/conda/miniconda2/etc/profile.d/conda.sh
conda activate /gpfs0/system/conda/miniconda2/envs/Omics_QC

ASSEMBLY=Coelastrella_FINAL.fa

date
echo "=== miniprot ==="
busco -i $ASSEMBLY -o BUSCO_FINAL_miniprot -l chlorophyta_odb10 -m genome -c 16 -f

echo ""
echo "=== metaeuk ==="
busco -i $ASSEMBLY -o BUSCO_FINAL_metaeuk -l chlorophyta_odb10 -m genome -c 16 --metaeuk -f

echo ""
echo "============================================"
echo "=== FINAL SUMMARIES ==="
echo "============================================"
echo "--- miniprot ---"
cat BUSCO_FINAL_miniprot/short_summary*.txt 2>/dev/null
echo ""
echo "--- metaeuk ---"
cat BUSCO_FINAL_metaeuk/short_summary*.txt 2>/dev/null

date
