#!/usr/bin/env bash
# A06_masurca — frozen assembly step. Frozen assembly record/verifier (logic in legacy pipeline.py).
export PIPE_DOMAIN="assembly"; STEP_ID="A06_masurca"
source "${PROJECT_ROOT:-/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly}/annotation/steps/_lib.sh"
OUT="${PROJECT_ROOT}/final_assembly.fa"
step_check() { [[ -e "$OUT" ]]; }
step_run() {
  if step_check; then emit_report "$STEP_ID" "DONE (frozen)" "sentinel=$OUT"; say "verified: $OUT"; return 0; fi
  say "ERROR: sentinel missing ($OUT) — assembly is frozen; re-run legacy pipeline.py if truly needed"; return 1
}
step_main "$@"
