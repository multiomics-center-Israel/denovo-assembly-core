#!/usr/bin/env bash
# E14_stringtie_merge — StringTie assemble per library then --merge all into one GTF.
# The merged_all11.gtf is the shared transcript evidence for BOTH candidate paths
# (P25 PASA-update and P20 full re-annotation).
export PIPE_DOMAIN="annotation"; STEP_ID="E14_stringtie_merge"
source "$(dirname "$0")/_lib.sh"

LIBS="${STEPS_DIR}/rna_libs.tsv"
OUT="${PROJECT_ROOT}/rnaseq/new"; mkdir -p "$OUT"
MERGED="${OUT}/merged_all11.gtf"
THREADS=16

read_ids() { awk -F'\t' '!/^#/ && NF>=5 {print $1}' "$LIBS"; }

step_check() { [[ -s "$MERGED" ]]; }

step_run() {
  local id bam gtf gtflist=()
  while read -r id; do
    bam="${OUT}/${id}.bam"; gtf="${OUT}/${id}.stringtie.gtf"
    [[ -s "$bam" ]] || { say "ERROR: ${bam} missing (run E13 first)"; return 1; }
    if [[ ! -s "$gtf" ]]; then
      say "${id}: StringTie assemble"
      crun funannotate stringtie -p "$THREADS" -o "$gtf" "$bam" || return 1
    else
      say "${id}: stringtie gtf present, skip"
    fi
    gtflist+=("$gtf")
  done < <(read_ids)
  say "merging ${#gtflist[@]} per-lib GTFs -> $(basename "$MERGED")"
  crun funannotate stringtie --merge -p "$THREADS" -o "$MERGED" "${gtflist[@]}" || return 1
  local nloci ntx
  ntx=$(grep -cP '\ttranscript\t' "$MERGED" || echo 0)
  nloci=$(awk -F'\t' '$3=="transcript"{match($9,/gene_id "([^"]+)"/,a); print a[1]}' "$MERGED" | sort -u | wc -l)
  say "merged: ${ntx} transcripts / ${nloci} loci"
  emit_report "$STEP_ID" "DONE" "merged_gtf=${MERGED}" "transcripts=${ntx}" "loci=${nloci}"
  return 0
}
step_main "$@"
