#!/usr/bin/env bash
# A14_fcs_adaptor — FCS-Adaptor (clean). Frozen assembly record/verifier (logic in legacy pipeline.py).
export PIPE_DOMAIN="assembly"; STEP_ID="A14_fcs_adaptor"
source "${PROJECT_ROOT:-/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly}/annotation/steps/_lib.sh"
OUT="${PROJECT_ROOT}/NCBI_FCS_Adaptor_datase_1.Adaptor_report.txt"
step_check() { [[ -e "$OUT" ]]; }
step_run() {
  if step_check; then emit_report "$STEP_ID" "DONE (frozen)" "sentinel=$OUT"; say "verified: $OUT"; return 0; fi
  say "ERROR: sentinel missing ($OUT) — assembly is frozen; re-run legacy pipeline.py if truly needed"; return 1
}
step_main "$@"
