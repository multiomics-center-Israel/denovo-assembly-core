#!/usr/bin/env bash
# run_assembly_pipeline.sh — assembly + decontam + FCS pipeline. This work is DONE and
# FROZEN: final_assembly.fa (4,980 contigs) passed NCBI FCS-GX/Adaptor clean, zero edits.
# This runner is a record + verifier: `status` confirms every step COMPLETE; it does not
# recompute unless you force a specific step. It documents the substrate the annotation
# pipeline builds on. Same engine/flags as run_annotation_pipeline.sh.
set -euo pipefail
export PIPE_DOMAIN="assembly"
export PROJECT_ROOT="/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly"
source "${PROJECT_ROOT}/annotation/steps/_lib.sh"   # shared lib lives under annotation/steps/

next_hint() { echo ">>> Assembly is FROZEN (FCS-clean, submission-ready). Nothing to run."; }

source "${PROJECT_ROOT}/bin/pipeline_core.sh"
pipeline_cli "$@"
