#!/usr/bin/env bash
# D00_busco_diagnostic — evidence-first lever diagnosis (lit-review 2026-06-15).
# Compares the RAW BRAKER3 protein set vs the funannotate CANONICAL set at the
# single-BUSCO level, and classifies the 82->89 gap into actionable levers:
#   - recoverable : Missing/Fragmented in canonical but Complete in raw BRAKER3
#                   -> cheap win by switching/merging models (no new data needed)
#   - hard_tail   : Missing in BOTH -> genome gap / over-masking / true divergence
#   - regression  : Complete in canonical but Missing in BRAKER3 (funannotate added it)
# Uses existing BUSCO full_table.tsv files; only runs BUSCO if one is absent.
export PIPE_DOMAIN="annotation"; STEP_ID="D00_busco_diagnostic"
source "$(dirname "$0")/_lib.sh"

OUTDIR="${PROJECT_ROOT}/annotation/diagnostic"; mkdir -p "$OUTDIR"
REPORT="${OUTDIR}/busco_lever_report.md"
# IMPORTANT: both tables MUST be the same lineage (hymenoptera_odb10, 5991, "at7399" ids).
# The funannotate-internal table is odb9 (EOG ids) and is NOT comparable — use the
# dedicated odb10 BUSCO run of the canonical proteome instead.
BRAKER_FT="${PROJECT_ROOT}/analysis/busco/braker_prot/run_hymenoptera_odb10/full_table.tsv"
CANON_FT="${PROJECT_ROOT}/analysis/busco/final_canonical_prot/run_hymenoptera_odb10/full_table.tsv"

step_check() { [[ -s "$REPORT" ]]; }

step_run() {
  [[ -s "$BRAKER_FT" ]] || { say "ERROR: BRAKER BUSCO full_table missing: $BRAKER_FT"; return 1; }
  [[ -s "$CANON_FT" ]]  || { say "ERROR: canonical BUSCO full_table missing: $CANON_FT"; return 1; }
  say "comparing BRAKER raw vs canonical BUSCO at single-gene level"
  crun genome_assembly python3 "${STEPS_DIR}/d00_diagnostic.py" \
      --braker "$BRAKER_FT" --canonical "$CANON_FT" --out "$REPORT" || return 1
  say "wrote $REPORT"
  # surface the headline lever line in the pipeline report
  local verdict; verdict=$(grep -m1 '^VERDICT:' "$REPORT" | sed 's/^VERDICT: //')
  emit_report "$STEP_ID" "DONE" "report=${REPORT}" "verdict=${verdict:-see report}"
  return 0
}
step_main "$@"
