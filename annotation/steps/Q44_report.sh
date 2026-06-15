#!/usr/bin/env bash
# Q44_report — assemble the master annotation report from per-step fragments.
export PIPE_DOMAIN="annotation"; STEP_ID="Q44_report"
source "$(dirname "$0")/_lib.sh"

MASTER="${DOMAIN_DIR}/REPORT.md"

step_check() { return 1; }   # always refreshable

step_run() {
  {
    echo "# Spalangia cameroni — Annotation pipeline report"
    echo "_assembled $(now_iso)_"
    echo ""
    echo "Per-step fragments (annotation/reports/):"
    echo ""
    local f
    for f in $(ls "${REPORTS_DIR}"/*.md 2>/dev/null | sort); do
      echo "---"
      cat "$f"
      echo ""
    done
  } > "${MASTER}.tmp"
  mv "${MASTER}.tmp" "$MASTER"
  say "master report -> $MASTER"
  # also trigger pipeline.py report refresh if available (best-effort)
  emit_report "$STEP_ID" "DONE" "master=${MASTER}"
  return 0
}
step_main "$@"
