#!/bin/bash
# Run NextDenovo + redo purging & comparison with all 4 assemblers
# Usage: nohup bash run_nextdenovo_and_compare.sh > logs/nextdenovo_and_compare.log 2>&1 &

set -e
cd /mnt/data/Projects/Elad_Chiel/wasp_genome_assembly

echo "=== NextDenovo + full comparison — started $(date) ==="
echo "PID: $$"

# Phase 2.1d: NextDenovo
echo ""
echo "=== Phase 2.1d: NextDenovo HiFi — $(date) ==="
python genome_assembly_pipeline.py --phase 2.1d --no-report --skip-if-done
echo "=== NextDenovo finished — $(date) ==="

# Re-run purge_dups (will only purge NextDenovo, others already done)
echo ""
echo "=== Phase 2.2: Purge duplicates (NextDenovo) — $(date) ==="
python genome_assembly_pipeline.py --phase 2.2 --no-report
echo "=== Purge dups finished — $(date) ==="

# Re-run comparison with all 4 assemblies + MUMmer
echo ""
echo "=== Phase 2.3: Compare all assemblies (QUAST + BUSCO + MUMmer) — $(date) ==="
python genome_assembly_pipeline.py --phase 2.3 --no-report
echo "=== Comparison finished — $(date) ==="

echo ""
echo "=== All done — $(date) ==="
python genome_assembly_pipeline.py --status
