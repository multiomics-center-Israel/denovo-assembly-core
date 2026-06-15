#!/usr/bin/env bash
# P23_tiberius_integrate — Tiberius graft (gated). [DONE] verify-and-record wrapper (logic in existing drivers).
export PIPE_DOMAIN="annotation"; STEP_ID="P23_tiberius_integrate"
source "$(dirname "$0")/_lib.sh"
OUT="${PROJECT_ROOT}/analysis/merge_tiberius/Spalangia_cameroni.merged.gff3"
step_check() { [[ -e "$OUT" ]]; }
step_run() {
  if step_check; then
    say "output present: $OUT — recording"
    emit_report "$STEP_ID" "DONE (pre-existing)" "output=$OUT"
    return 0
  fi
  say "ERROR: expected output missing ($OUT). This step's heavy logic lives in the legacy driver; re-run that or implement here."
  return 1
}
step_main "$@"
