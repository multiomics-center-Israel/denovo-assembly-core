#!/usr/bin/env bash
# E12_rna_trim_all — fastp-trim all 11 RNA libraries (PE + Elad SE), per rna_libs.tsv.
# Public lib reuses the already-trimmed files if present (idempotent shortcut).
export PIPE_DOMAIN="annotation"; STEP_ID="E12_rna_trim_all"
source "$(dirname "$0")/_lib.sh"

LIBS="${STEPS_DIR}/rna_libs.tsv"
OUT="${PROJECT_ROOT}/rnaseq/new"; mkdir -p "$OUT"
THREADS=16

# expected trimmed outputs per lib
trim_out() {  # trim_out <id> <layout> -> echoes the primary output path
  local id="$1" layout="$2"
  if [[ "$layout" == "PE" ]]; then echo "${OUT}/${id}.trim_1.fastq.gz"; else echo "${OUT}/${id}.trim.fastq.gz"; fi
}

read_libs() { awk -F'\t' '!/^#/ && NF>=5 {print $1"\t"$3"\t"$4"\t"$5}' "$LIBS"; }

step_check() {
  local id layout r1 r2
  while IFS=$'\t' read -r id layout r1 r2; do
    [[ -s "$(trim_out "$id" "$layout")" ]] || return 1
  done < <(read_libs)
  return 0
}

step_run() {
  local id layout r1 r2 out1 out2 done=0
  while IFS=$'\t' read -r id layout r1 r2; do
    out1="${OUT}/${id}.trim_1.fastq.gz"; out2="${OUT}/${id}.trim_2.fastq.gz"
    local outS="${OUT}/${id}.trim.fastq.gz"
    # public shortcut: reuse pre-existing trimmed files
    if [[ "$id" == "public" && -s "${PROJECT_ROOT}/rnaseq/trimmed_1.fastq.gz" ]]; then
      ln -sf "${PROJECT_ROOT}/rnaseq/trimmed_1.fastq.gz" "$out1"
      ln -sf "${PROJECT_ROOT}/rnaseq/trimmed_2.fastq.gz" "$out2"
      say "public: linked existing trimmed files"; continue
    fi
    if [[ "$layout" == "PE" && -s "$out1" && -s "$out2" ]]; then say "${id}: trimmed present, skip"; continue; fi
    if [[ "$layout" == "SE" && -s "$outS" ]]; then say "${id}: trimmed present, skip"; continue; fi
    if [[ "$layout" == "PE" ]]; then
      [[ -s "${PROJECT_ROOT}/${r1}" && -s "${PROJECT_ROOT}/${r2}" ]] || { say "${id}: PE inputs missing (${r1}/${r2})"; return 1; }
      say "${id}: fastp PE"
      crun genome_assembly fastp -w "$THREADS" \
        -i "${PROJECT_ROOT}/${r1}" -I "${PROJECT_ROOT}/${r2}" \
        -o "$out1" -O "$out2" \
        -j "${OUT}/${id}.fastp.json" -h "${OUT}/${id}.fastp.html" || return 1
    else
      [[ -s "${PROJECT_ROOT}/${r1}" ]] || { say "${id}: SE input missing (${r1})"; return 1; }
      say "${id}: fastp SE"
      crun genome_assembly fastp -w "$THREADS" \
        -i "${PROJECT_ROOT}/${r1}" -o "$outS" \
        -j "${OUT}/${id}.fastp.json" -h "${OUT}/${id}.fastp.html" || return 1
    fi
    done=$((done+1))
  done < <(read_libs)
  emit_report "$STEP_ID" "DONE" "libraries=11" "newly_trimmed=${done}" "outdir=${OUT}"
  return 0
}
step_main "$@"
