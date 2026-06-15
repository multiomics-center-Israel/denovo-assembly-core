#!/usr/bin/env bash
# Q43_promote — HUMAN-GATED promotion of a candidate to canonical. Repoints the
# annotation/canonical_annotation symlink and writes CANONICAL.md. Refuses to run
# without explicit operator confirmation:
#   PROMOTE=<rna_update|braker_all11|...>  CONFIRM=1  ./run_annotation_pipeline.sh --step Q43_promote
export PIPE_DOMAIN="annotation"; STEP_ID="Q43_promote"
source "$(dirname "$0")/_lib.sh"

LINK="${PROJECT_ROOT}/annotation/canonical_annotation"
declare -A SRC=(
  [rna_update]="${PROJECT_ROOT}/annotation/funannotate_rna_out/annotate_results"
  [braker_all11]="${PROJECT_ROOT}/annotation/braker_all11"
)

step_check() { return 1; }   # never auto-DONE; promotion is always an explicit human action

step_run() {
  if [[ -z "${PROMOTE:-}" || "${CONFIRM:-0}" != "1" ]]; then
    say "REFUSED: promotion is human-gated. Re-run with PROMOTE=<candidate> CONFIRM=1."
    say "current canonical -> $(readlink -f "$LINK" 2>/dev/null || echo '?')"
    say "candidates: ${!SRC[*]}"
    return 2
  fi
  local target="${SRC[$PROMOTE]:-}"
  [[ -n "$target" && -e "$target" ]] || { say "ERROR: candidate '$PROMOTE' not found ($target)"; return 1; }
  local prev; prev=$(readlink -f "$LINK" 2>/dev/null || echo none)
  ln -sfn "$target" "$LINK"
  {
    echo "# CANONICAL annotation"
    echo "- promoted: $(now_iso)"
    echo "- candidate: ${PROMOTE}"
    echo "- target: ${target}"
    echo "- previous: ${prev}"
  } > "${target}/CANONICAL.md"
  say "PROMOTED ${PROMOTE}: canonical_annotation -> ${target} (was ${prev})"
  emit_report "$STEP_ID" "DONE" "promoted=${PROMOTE}" "target=${target}" "previous=${prev}"
  return 0
}
step_main "$@"
