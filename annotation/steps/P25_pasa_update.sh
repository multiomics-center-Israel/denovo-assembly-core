#!/usr/bin/env bash
# P25_pasa_update — fast/non-destructive candidate path: PASA annotation-compare on the
# canonical set using the all-11 merged StringTie GTF (UTRs/isoforms, IDs preserved).
# Delegates to the tested legacy driver run_rnaseq_annotation_update.sh (idempotent),
# which is fed the merged_all11 evidence produced by E14.
export PIPE_DOMAIN="annotation"; STEP_ID="P25_pasa_update"
source "$(dirname "$0")/_lib.sh"

DRIVER="${PROJECT_ROOT}/run_rnaseq_annotation_update.sh"
MERGED="${PROJECT_ROOT}/rnaseq/new/merged_all11.gtf"
OUT="${PROJECT_ROOT}/annotation/funannotate_rna_out"

step_check() { [[ -e "$OUT" ]]; }

step_run() {
  [[ -s "$MERGED" ]] || { say "ERROR: merged_all11.gtf missing (run E14 first)"; return 1; }
  [[ -x "$DRIVER" || -f "$DRIVER" ]] || { say "ERROR: legacy driver missing: $DRIVER"; return 1; }
  say "running PASA-update via legacy driver (consumes merged_all11 evidence)"
  # The driver is idempotent and manifest-driven; STRINGTIE_MERGED lets it reuse E14 output.
  STRINGTIE_MERGED="$MERGED" bash "$DRIVER" || { say "PASA-update driver failed"; return 1; }
  [[ -e "$OUT" ]] || { say "ERROR: ${OUT} not produced"; return 1; }
  emit_report "$STEP_ID" "DONE" "candidate=${OUT}" "evidence=${MERGED}"
  return 0
}
step_main "$@"
