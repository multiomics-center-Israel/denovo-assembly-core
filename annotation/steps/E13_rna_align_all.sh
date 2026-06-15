#!/usr/bin/env bash
# E13_rna_align_all — HISAT2 --dta align every trimmed library to the masked genome.
# PE libs use -1/-2; Elad SE libs use -U. Sorted+indexed BAM + flagstat per lib.
export PIPE_DOMAIN="annotation"; STEP_ID="E13_rna_align_all"
source "$(dirname "$0")/_lib.sh"

LIBS="${STEPS_DIR}/rna_libs.tsv"
OUT="${PROJECT_ROOT}/rnaseq/new"; mkdir -p "$OUT"
IDX="${PROJECT_ROOT}/rnaseq/hisat2_index/spalangia"
THREADS=16

read_libs() { awk -F'\t' '!/^#/ && NF>=5 {print $1"\t"$3}' "$LIBS"; }

step_check() {
  local id layout
  while IFS=$'\t' read -r id layout; do
    [[ -s "${OUT}/${id}.bam" ]] || return 1
  done < <(read_libs)
  return 0
}

step_run() {
  [[ -s "${IDX}.1.ht2" ]] || { say "ERROR: HISAT2 index ${IDX} missing"; return 1; }
  local id layout bam
  while IFS=$'\t' read -r id layout; do
    bam="${OUT}/${id}.bam"
    if [[ -s "$bam" ]]; then say "${id}: bam present, skip"; continue; fi
    say "${id}: HISAT2 ${layout} align"
    if [[ "$layout" == "PE" ]]; then
      crun genome_assembly bash -c "set -o pipefail; \
        hisat2 --dta -p ${THREADS} -x '${IDX}' \
          -1 '${OUT}/${id}.trim_1.fastq.gz' -2 '${OUT}/${id}.trim_2.fastq.gz' \
          --summary-file '${OUT}/${id}.hisat2.summary' \
        | samtools sort -@ ${THREADS} -o '${bam}' - && samtools index '${bam}'" || return 1
    else
      crun genome_assembly bash -c "set -o pipefail; \
        hisat2 --dta -p ${THREADS} -x '${IDX}' \
          -U '${OUT}/${id}.trim.fastq.gz' \
          --summary-file '${OUT}/${id}.hisat2.summary' \
        | samtools sort -@ ${THREADS} -o '${bam}' - && samtools index '${bam}'" || return 1
    fi
    crun genome_assembly samtools flagstat "$bam" > "${OUT}/${id}.flagstat"
    say "${id}: $(grep 'properly paired' "${OUT}/${id}.flagstat" 2>/dev/null | head -1 || echo 'SE - no pairing')"
  done < <(read_libs)
  # surface venom proper-pair recovery explicitly (was 0.34% before E11)
  local vpp; vpp=$(grep 'properly paired' "${OUT}/venom.flagstat" 2>/dev/null | head -1 || echo n/a)
  emit_report "$STEP_ID" "DONE" "bams=11" "venom_proper_paired=${vpp}" "outdir=${OUT}"
  return 0
}
step_main "$@"
