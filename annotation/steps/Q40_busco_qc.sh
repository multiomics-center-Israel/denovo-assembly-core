#!/usr/bin/env bash
# Q40_busco_qc — BUSCO(prot, hymenoptera_odb10) on each new candidate proteome.
export PIPE_DOMAIN="annotation"; STEP_ID="Q40_busco_qc"
source "$(dirname "$0")/_lib.sh"

BUSCODIR="${PROJECT_ROOT}/analysis/busco"
LIN="hymenoptera_odb10"
THREADS=24
# candidate proteomes: id -> path (only those that exist are run)
declare -A CAND=(
  [rna_update]="${PROJECT_ROOT}/annotation/funannotate_rna_out/annotate_results/Spalangia_cameroni.proteins.fa"
  [braker_all11]="${PROJECT_ROOT}/annotation/braker_all11/braker.aa"
)
OUT_SENTINEL="${BUSCODIR}/rna_update/short_summary.specific.${LIN}.rna_update.txt"

step_check() { [[ -s "$OUT_SENTINEL" ]]; }

step_run() {
  mkdir -p "$BUSCODIR"
  local ran=0 tag p
  for tag in "${!CAND[@]}"; do
    p="${CAND[$tag]}"
    [[ -s "$p" ]] || { say "${tag}: proteome not present yet (${p}), skipping"; continue; }
    [[ -s "${BUSCODIR}/${tag}/short_summary.specific.${LIN}.${tag}.txt" ]] && { say "${tag}: BUSCO done"; continue; }
    say "${tag}: running BUSCO"
    ( cd "$BUSCODIR" && crun genome_assembly busco -f -i "$p" -l "$LIN" -m proteins -c "$THREADS" -o "$tag" ) || return 1
    ran=$((ran+1))
  done
  emit_report "$STEP_ID" "DONE" "candidates_run=${ran}" "busco_dir=${BUSCODIR}"
  return 0
}
step_main "$@"
