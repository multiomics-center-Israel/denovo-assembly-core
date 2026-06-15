#!/usr/bin/env bash
# Q41_expression — featureCounts matrix over the 11 RNA BAMs vs the canonical gene set.
# Provides venom/body + Elad NS-vs-S contrasts for the multiomics/DE side.
export PIPE_DOMAIN="annotation"; STEP_ID="Q41_expression"
source "$(dirname "$0")/_lib.sh"

NEWBAMS="${PROJECT_ROOT}/rnaseq/new"
GTF="${PROJECT_ROOT}/annotation/canonical_annotation/Spalangia_cameroni.final.gtf"
OUTDIR="${PROJECT_ROOT}/analysis/expression"; mkdir -p "$OUTDIR"
OUT="${OUTDIR}/featurecounts_all11.txt"
LIBS="${STEPS_DIR}/rna_libs.tsv"
THREADS=16

step_check() { [[ -s "$OUT" ]]; }

step_run() {
  [[ -s "$GTF" ]] || { say "ERROR: canonical GTF missing: $GTF"; return 1; }
  local bams=() id
  while read -r id; do [[ -s "${NEWBAMS}/${id}.bam" ]] && bams+=("${NEWBAMS}/${id}.bam"); done \
    < <(awk -F'\t' '!/^#/ && NF>=5 {print $1}' "$LIBS")
  [[ ${#bams[@]} -ge 1 ]] || { say "ERROR: no BAMs (run E13)"; return 1; }
  say "featureCounts over ${#bams[@]} BAMs"
  crun genome_assembly featureCounts -T "$THREADS" -t exon -g gene_id \
      -a "$GTF" -o "$OUT" "${bams[@]}" || return 1
  emit_report "$STEP_ID" "DONE" "matrix=${OUT}" "samples=${#bams[@]}"
  return 0
}
step_main "$@"
