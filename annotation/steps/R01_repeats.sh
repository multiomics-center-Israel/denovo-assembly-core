#!/usr/bin/env bash
# R01_repeats — RepeatModeler2 + RepeatMasker. [DONE] verify-and-report wrapper.
export PIPE_DOMAIN="annotation"; STEP_ID="R01_repeats"
source "$(dirname "$0")/_lib.sh"
MASKED="${PROJECT_ROOT}/annotation/repeats/final_assembly.fa.masked"

step_check() { [[ -s "$MASKED" ]]; }
step_run() {
  if step_check; then
    local sz; sz=$(du -h "$MASKED" | cut -f1)
    say "masked genome present (${sz}); repeats already done — recording only"
    emit_report "$STEP_ID" "DONE (pre-existing)" "masked_genome=${MASKED}" "size=${sz}"
    return 0
  fi
  say "ERROR: masked genome missing and re-running RepeatModeler is out of scope of this wrapper"
  return 1
}
step_main "$@"
