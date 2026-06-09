#!/bin/bash
# Run all Phase 2 assemblies sequentially (nohup-safe)
# Usage: nohup bash run_phase2_assemblies.sh > logs/phase2_assembly.log 2>&1 &

set -e
cd /mnt/data/Projects/Elad_Chiel/wasp_genome_assembly

echo "=== Phase 2 Assembly — started $(date) ==="
echo "PID: $$"

# Phase 2.1: hifiasm (low-memory)
echo ""
echo "=== Phase 2.1: hifiasm (low-memory -f 0) — $(date) ==="
python genome_assembly_pipeline.py --phase 2.1 --no-report --skip-if-done
echo "=== hifiasm finished — $(date) ==="

# Phase 2.1c: Flye
echo ""
echo "=== Phase 2.1c: Flye HiFi — $(date) ==="
python genome_assembly_pipeline.py --phase 2.1c --no-report --skip-if-done
echo "=== Flye finished — $(date) ==="

# Phase 2.1d: NextDenovo
echo ""
echo "=== Phase 2.1d: NextDenovo HiFi — $(date) ==="
python genome_assembly_pipeline.py --phase 2.1d --no-report --skip-if-done
echo "=== NextDenovo finished — $(date) ==="

# Phase 2.1b: MaSuRCA (most memory-hungry, run last)
echo ""
echo "=== Phase 2.1b: MaSuRCA hybrid — $(date) ==="
python genome_assembly_pipeline.py --phase 2.1b --no-report --skip-if-done
echo "=== MaSuRCA finished — $(date) ==="

# Phase 2.2: Purge haplotigs on all assemblies
echo ""
echo "=== Phase 2.2: Purge duplicates — $(date) ==="
python genome_assembly_pipeline.py --phase 2.2 --no-report --skip-if-done
echo "=== Purge dups finished — $(date) ==="

# Phase 2.3: Compare all assemblies
echo ""
echo "=== Phase 2.3: Compare assemblies — $(date) ==="
python genome_assembly_pipeline.py --phase 2.3 --no-report --skip-if-done
echo "=== Comparison finished — $(date) ==="

echo ""
echo "=== All Phase 2 steps complete — $(date) ==="
python genome_assembly_pipeline.py --status
