#!/usr/bin/env bash
# run_annotation_pipeline.sh — unified, modular, resumable annotation pipeline for
# Spalangia cameroni. One umbrella over every annotation step (done + upcoming).
#
# Usage:
#   ./run_annotation_pipeline.sh                 # resume from first PENDING step to end
#   ./run_annotation_pipeline.sh status          # every step + the CURRENT NEXT pointer
#   ./run_annotation_pipeline.sh --step E11      # run a single step
#   ./run_annotation_pipeline.sh --from E11 --to E14   # run a contiguous range
#   ./run_annotation_pipeline.sh --all           # run all PENDING steps in order
#   FORCE=1 ./run_annotation_pipeline.sh --step E11    # force re-run
#
# LONG steps auto-detach (nohup+setsid) and survive SSH drop; SHORT run inline.
# Each step appends to annotation/REPORT.md. catalogue.tsv drives the NeatSeq-Flow
# version too (annotation/steps/gen_nsf.py). Plan: ~/.claude/plans/mutable-hopping-dahl.md
set -euo pipefail
export PIPE_DOMAIN="annotation"
export PROJECT_ROOT="/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly"
source "${PROJECT_ROOT}/annotation/steps/_lib.sh"

# domain-specific NEXT hint (current parallel-track design)
next_hint() {
  echo ">>> NEXT: [parallel] D00_busco_diagnostic (local ~1h)  ||  E11->E14 evidence group (detached, all 11 libs)"
}

source "${PROJECT_ROOT}/bin/pipeline_core.sh"
pipeline_cli "$@"
