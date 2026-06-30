#!/usr/bin/env bash
# P21_tiberius — Tiberius ab-initio. [DONE] verify-and-record wrapper (logic in existing drivers).
export PIPE_DOMAIN="annotation"; STEP_ID="P21_tiberius"
source "$(dirname "$0")/_lib.sh"
OUT="${PROJECT_ROOT}/analysis/busco/tiberius_prot/run_hymenoptera_odb10/full_table.tsv"
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
