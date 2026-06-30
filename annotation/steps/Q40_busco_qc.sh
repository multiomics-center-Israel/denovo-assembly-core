#!/usr/bin/env bash
# Q40_busco_qc — BUSCO(prot, hymenoptera_odb10) on each new candidate proteome.
#
# HARDENED (2026-06-16): the old version trusted "proteome present?" + "busco exit 0?"
# and emitted DONE regardless. That let two silent failures through:
#   (a) a candidate whose proteome was ABSENT was skipped silently -> DONE with no output;
#   (b) BUSCO can exit 0 yet write an EMPTY/garbage run dir.
# Either way Track B then waited HOURS for a full_table.tsv that never appeared, then
# aborted. New contract, enforced for every candidate:
#   * proteome PRESENT  -> BUSCO MUST produce a non-empty run_<lin>/full_table.tsv AND a
#                          short_summary with a real C:% line, else this step FAILS loudly.
#   * proteome ABSENT   -> PENDING (logged, not fatal — e.g. P25 still running).
#   * DONE requires >=1 candidate with a VALID BUSCO; otherwise FAIL (so no downstream
#     waiter ever sees a DONE Q40 that produced nothing).
export PIPE_DOMAIN="annotation"; STEP_ID="Q40_busco_qc"
source "$(dirname "$0")/_lib.sh"

BUSCODIR="${PROJECT_ROOT}/analysis/busco"
LIN="hymenoptera_odb10"
THREADS=24
# candidate proteomes: id -> path (only those that exist are BUSCO'd)
declare -A CAND=(
  [rna_update]="${PROJECT_ROOT}/annotation/update_rna_all11/canonical_rna_updated.proteins.fa"
  [braker_all11]="${PROJECT_ROOT}/annotation/braker_all11/braker.aa"
)

# ---- validation helpers: the downstream artifacts must actually exist ----
# full_table.tsv (Track B / Q42 consume THIS) must exist with >=1 non-comment data row,
# and the summary must carry a completeness line. BUSCO exit code alone is NOT trusted.
busco_valid() {
  local tag="$1"
  local ft="${BUSCODIR}/${tag}/run_${LIN}/full_table.tsv"
  local ss="${BUSCODIR}/${tag}/short_summary.specific.${LIN}.${tag}.txt"
  [[ -s "$ft" ]] || return 1
  grep -qvE '^#' "$ft" || return 1            # at least one real data row
  [[ -s "$ss" ]] && grep -q 'C:' "$ss"
}
busco_cscore() {  # echo the C:..% completeness line for reports (or "n/a")
  local ss="${BUSCODIR}/$1/short_summary.specific.${LIN}.$1.txt"
  grep -oE 'C:[0-9.]+%\[[^]]*\]' "$ss" 2>/dev/null | head -1 || true
}

# Done only when every PRESENT proteome has a valid BUSCO and >=1 candidate is valid.
step_check() {
  local tag p valid=0
  for tag in "${!CAND[@]}"; do
    p="${CAND[$tag]}"
    [[ -s "$p" ]] || continue
    busco_valid "$tag" || return 1            # present but not valid -> not done
    valid=$((valid+1))
  done
  (( valid >= 1 ))
}

step_run() {
  mkdir -p "$BUSCODIR"
  local ran=0 valid=0 tag p blog
  local -a fails=() pend=()
  for tag in "${!CAND[@]}"; do
    p="${CAND[$tag]}"
    if [[ ! -s "$p" ]]; then
      say "${tag}: proteome not present yet (${p}) — PENDING (skipping, not a failure)"
      pend+=("$tag"); continue
    fi
    if busco_valid "$tag"; then
      say "${tag}: BUSCO already valid $(busco_cscore "$tag")"
      valid=$((valid+1)); continue
    fi
    say "${tag}: running BUSCO (proteins, ${LIN}, ${THREADS}t)"
    blog="${BUSCODIR}/${tag}.busco.log"
    if ! ( cd "$BUSCODIR" && crun genome_assembly busco -f -i "$p" -l "$LIN" -m proteins -c "$THREADS" -o "$tag" ) >"$blog" 2>&1; then
      say "ERROR: ${tag}: BUSCO exited nonzero — tail of ${blog}:"
      tail -n 15 "$blog" | sed 's/^/    /'
      fails+=("${tag}:busco-nonzero"); continue
    fi
    # exit 0 is NOT enough — the run dir must hold a real full_table.tsv
    if ! busco_valid "$tag"; then
      say "ERROR: ${tag}: BUSCO exited 0 but produced NO valid full_table.tsv/summary — tail of ${blog}:"
      tail -n 15 "$blog" | sed 's/^/    /'
      fails+=("${tag}:no-artifacts"); continue
    fi
    say "${tag}: BUSCO OK $(busco_cscore "$tag")"
    ran=$((ran+1)); valid=$((valid+1))
  done

  if (( ${#fails[@]} )); then
    emit_report "$STEP_ID" "FAILED" "failed=${fails[*]}" "ran=${ran}" "pending=${pend[*]:-none}"
    say "FAILED: ${#fails[@]} candidate(s) produced no valid BUSCO: ${fails[*]}"
    return 1
  fi
  if (( valid == 0 )); then
    emit_report "$STEP_ID" "FAILED" "reason=no-candidate-produced-valid-busco" "pending=${pend[*]:-none}"
    say "FAILED: no candidate produced a valid BUSCO (all pending: ${pend[*]:-none}) — refusing to report DONE"
    return 1
  fi
  emit_report "$STEP_ID" "DONE" "candidates_run=${ran}" "valid=${valid}" "pending=${pend[*]:-none}" \
    "braker_all11=$(busco_cscore braker_all11)" "rna_update=$(busco_cscore rna_update)" "busco_dir=${BUSCODIR}"
  return 0
}
step_main "$@"
