#!/usr/bin/env bash
# E11_rna_repair_venom — re-pair the desynced Martinson venom RNA-Seq.
# The raw files are out of order AND unequal length (R1 13.89M / R2 13.78M), so
# mates do not line up by position -> only 0.34% proper pairs if used as-is.
# bbmap repair.sh re-pairs by read name, keeps shared reads in sync, dumps orphans.
export PIPE_DOMAIN="annotation"; STEP_ID="E11_rna_repair_venom"
source "$(dirname "$0")/_lib.sh"

VEN="${PROJECT_ROOT}/extera_data/From_Ellen_Martinson/Venom_RNAseq"
IN1="${VEN}/clt_S_cam_VA_R1.fastq.gz"
IN2="${VEN}/clt_S_cam_VA_R2.fastq.gz"
OUT="${PROJECT_ROOT}/rnaseq/new"
O1="${OUT}/venom_repaired_1.fastq.gz"
O2="${OUT}/venom_repaired_2.fastq.gz"
OS="${OUT}/venom_singletons.fastq.gz"

step_check() { [[ -s "$O1" && -s "$O2" ]]; }
step_run() {
  mkdir -p "$OUT"
  [[ -s "$IN1" && -s "$IN2" ]] || { say "ERROR: venom raw inputs missing"; return 1; }
  say "re-pairing venom with bbmap repair.sh (this reads both files fully)"
  crun genome_assembly repair.sh -Xmx32g \
      in1="$IN1" in2="$IN2" out1="$O1" out2="$O2" outs="$OS" repair overwrite=t \
    || { say "repair.sh failed"; return 1; }
  local n1 n2 ns
  n1=$(( $(zcat "$O1" | wc -l) / 4 ))
  n2=$(( $(zcat "$O2" | wc -l) / 4 ))
  ns=$(( $(zcat "$OS" 2>/dev/null | wc -l) / 4 ))
  say "repaired pairs: R1=${n1} R2=${n2} singletons=${ns}"
  [[ "$n1" -eq "$n2" && "$n1" -gt 0 ]] || { say "ERROR: repaired R1/R2 counts unequal or zero"; return 1; }
  emit_report "$STEP_ID" "DONE" "repaired_pairs=${n1}" "singletons=${ns}" "out1=${O1}" "out2=${O2}"
  return 0
}
step_main "$@"
