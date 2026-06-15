#!/usr/bin/env bash
# Q42_compare — build the candidate comparison table: PASA-update vs full-reannot vs
# current canonical (BUSCO C/S/D/F/M + protein counts). Decision input for Q43.
export PIPE_DOMAIN="annotation"; STEP_ID="Q42_compare"
source "$(dirname "$0")/_lib.sh"

OUTDIR="${PROJECT_ROOT}/analysis/comparison"; mkdir -p "$OUTDIR"
OUT="${OUTDIR}/rna_update_vs_full.tsv"
BUSCODIR="${PROJECT_ROOT}/analysis/busco"
LIN="hymenoptera_odb10"

# candidate label -> (busco short_summary json) | (proteome for counts)
declare -A SUMMARY=(
  [canonical]="${PROJECT_ROOT}/annotation/funannotate_final_out/annotate_misc/run_busco/short_summary*.json"
  [rna_update]="${BUSCODIR}/rna_update/short_summary.specific.${LIN}.rna_update.json"
  [braker_all11]="${BUSCODIR}/braker_all11/short_summary.specific.${LIN}.braker_all11.json"
)
declare -A PROTEOME=(
  [canonical]="${PROJECT_ROOT}/annotation/canonical_annotation/Spalangia_cameroni.proteins.fa"
  [rna_update]="${PROJECT_ROOT}/annotation/funannotate_rna_out/annotate_results/Spalangia_cameroni.proteins.fa"
  [braker_all11]="${PROJECT_ROOT}/annotation/braker_all11/braker.aa"
)

step_check() { [[ -s "$OUT" ]]; }

step_run() {
  { printf 'candidate\tproteins\tBUSCO_C\tBUSCO_S\tBUSCO_D\tBUSCO_F\tBUSCO_M\n'
    local k js prot n c s d f m
    for k in canonical rna_update braker_all11; do
      js=$(ls ${SUMMARY[$k]} 2>/dev/null | head -1 || true)
      prot="${PROTEOME[$k]}"
      n=$([[ -s "$prot" ]] && grep -c '^>' "$prot" || echo NA)
      if [[ -n "$js" && -s "$js" ]]; then
        c=$(grep -oP '"Complete":\s*\K[0-9.]+' "$js" | head -1)
        s=$(grep -oP '"Single copy":\s*\K[0-9.]+' "$js" | head -1)
        d=$(grep -oP '"Multi copy":\s*\K[0-9.]+' "$js" | head -1)
        f=$(grep -oP '"Fragmented":\s*\K[0-9.]+' "$js" | head -1)
        m=$(grep -oP '"Missing":\s*\K[0-9.]+' "$js" | head -1)
      else c=NA; s=NA; d=NA; f=NA; m=NA; fi
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$k" "$n" "${c:-NA}" "${s:-NA}" "${d:-NA}" "${f:-NA}" "${m:-NA}"
    done
  } > "$OUT"
  say "comparison table:"; column -t "$OUT" || cat "$OUT"
  emit_report "$STEP_ID" "DONE" "table=${OUT}"
  return 0
}
step_main "$@"
