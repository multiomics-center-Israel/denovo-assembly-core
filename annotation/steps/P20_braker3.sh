#!/usr/bin/env bash
# P20_braker3 — full re-annotation track: BRAKER3 on the masked genome with the
# all-11 RNA-Seq BAM set + Hymenoptera protein hints. This is the long pole.
export PIPE_DOMAIN="annotation"; STEP_ID="P20_braker3"
source "$(dirname "$0")/_lib.sh"

GENOME="${PROJECT_ROOT}/annotation/repeats/final_assembly.fa.masked"
PROT="${PROJECT_ROOT}/annotation/hymenoptera_proteins.fa"
NEWBAMS="${PROJECT_ROOT}/rnaseq/new"
WORK="${PROJECT_ROOT}/annotation/braker_all11"
OUT="${WORK}/braker.aa"
GENEMARK="${PROJECT_ROOT}/tools/GeneMark-ETP"
THREADS=24
LIBS="${STEPS_DIR}/rna_libs.tsv"

step_check() { [[ -s "$OUT" ]]; }

step_run() {
  [[ -s "$GENOME" ]] || { say "ERROR: masked genome missing"; return 1; }
  [[ -s "$PROT" ]]   || { say "ERROR: protein evidence missing (run E16)"; return 1; }
  # collect all per-lib BAMs (depends on E13)
  local bams=() id
  while read -r id; do
    [[ -s "${NEWBAMS}/${id}.bam" ]] && bams+=("${NEWBAMS}/${id}.bam")
  done < <(awk -F'\t' '!/^#/ && NF>=5 {print $1}' "$LIBS")
  [[ ${#bams[@]} -ge 1 ]] || { say "ERROR: no RNA BAMs found in ${NEWBAMS} (run E13 first)"; return 1; }
  local bamlist; bamlist=$(IFS=,; echo "${bams[*]}")
  say "BRAKER3 with ${#bams[@]} BAMs + proteins; genemark=${GENEMARK}"
  mkdir -p "$WORK"
  export GENEMARK_PATH="${GENEMARK}"
  # discover the gmes dir if present (key-free GeneMark-ETP layout)
  [[ -d "${GENEMARK}/bin/gmes" ]] && export GENEMARK_PATH="${GENEMARK}/bin/gmes"
  crun genome_assembly braker.pl \
      --genome="$GENOME" --softmasking \
      --bam="$bamlist" \
      --prot_seq="$PROT" \
      --workingdir="$WORK" \
      --threads="$THREADS" --gff3 \
    || { say "BRAKER3 failed (check GeneMark-ETP setup)"; return 1; }
  [[ -s "$OUT" ]] || { say "ERROR: braker.aa not produced"; return 1; }
  local ngenes; ngenes=$(grep -c '^>' "$OUT" || echo 0)
  emit_report "$STEP_ID" "DONE" "braker_aa=${OUT}" "proteins=${ngenes}" "bams=${#bams[@]}"
  return 0
}
step_main "$@"
