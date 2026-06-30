#!/bin/bash
#$ -S /bin/bash
#$ -N busco_final
#$ -cwd
#$ -j y
#$ -e busco_final.err
#$ -o busco_final.log
#$ -q bioinfo.q
#$ -pe shared 16

cd $(pwd)

source /gpfs0/system/conda/miniconda2/etc/profile.d/conda.sh
conda activate /gpfs0/system/conda/miniconda2/envs/Omics_QC

ASSEMBLY=Coelastrella_polypolish_pypolca_final.fa

date
echo "=== BUSCO miniprot (default v6) ==="
busco -i $ASSEMBLY -o BUSCO_final_miniprot \
  -l chlorophyta_odb10 -m genome -c 16 -f

echo ""
echo "=== BUSCO metaeuk ==="
busco -i $ASSEMBLY -o BUSCO_final_metaeuk \
  -l chlorophyta_odb10 -m genome -c 16 --metaeuk -f

echo ""
echo "============================================"
echo "=== FINAL COMPARISON ==="
echo "============================================"
echo ""
echo "--- miniprot ---"
cat BUSCO_final_miniprot/short_summary*.txt 2>/dev/null | head -20
echo ""
echo "--- metaeuk ---"
cat BUSCO_final_metaeuk/short_summary*.txt 2>/dev/null | head -20

date
echo "=== DONE ==="
