#!/usr/bin/env bash
# ============================================================================
# AED SUMMARY AUTO-REFRESH  — waits for EVM consensus, then folds the EVM stage
#                             into the cross-stage AED/BUSCO summary.
# ============================================================================
# Background watcher: polls until run_evm_consensus.sh has finished and produced
# annotation/refine/evm/evm.{gff3,aa}, then runs model-refinement STAGE C/D for
# the EVM stage only (braker_filtered + rescued AED tsvs already exist and are
# reused) and regenerates analysis/stats/refinement_summary.tsv + the figure.
# Mirrors run_model_refinement.sh score_stage()/STAGE D exactly.
# Launch detached:
#   setsid bash -c '/mnt/data/.../run_aed_refresh.sh' >/dev/null 2>&1 &
# ============================================================================
set -uo pipefail
PROJECT=/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly
cd "$PROJECT"
source "$(conda info --base)/etc/profile.d/conda.sh"
RUNENV=genome_assembly
THREADS=8
BR="$PROJECT/annotation/braker"
REF="$PROJECT/annotation/refine"
SC="$PROJECT/annotation/scripts"
EVM="$REF/evm"
GENOME="$PROJECT/final_assembly.fa"
BAM="$PROJECT/rnaseq/rnaseq_aligned.bam"
BUSCODIR="$PROJECT/analysis/busco"
FIG="$PROJECT/annotation/figures"
STATS="$PROJECT/analysis/stats"
NASDMND="$REF/nasonia.dmnd"
PASABED="$REF/pasa_transcripts.bed"
EVM_GFF="$EVM/evm.gff3"
mkdir -p "$STATS" "$FIG" "$PROJECT/logs"
TS=$(date +%Y%m%d_%H%M%S); LOG="$PROJECT/logs/aed_refresh_${TS}.log"
exec > >(tee -a "$LOG") 2>&1
echo "==== AED refresh watcher START $(date -Iseconds)  PID=$$  PPID=$PPID ===="
notify(){ PYTHONPATH="$PROJECT/denovo-assembly-core" python3 -m denovo_assembly_core.notify \
          --config "$PROJECT/project.yaml" "$1" "${2:-}" 2>>"$LOG" || true; }
run(){ conda run -n "$RUNENV" "$@"; }

build_pasabed(){
  local g="$PROJECT/analysis/utr/pasa/pasa.sqlite.valid_gmap_alignments.gff3"
  [ -s "$g" ] || g="$PROJECT/analysis/utr/pasa/gmap.spliced_alignments.gff3"
  [ -s "$g" ] || return 1
  awk -F'\t' '!/^#/ && NF>=8 {print $1"\t"$4-1"\t"$5}' "$g" | sort -k1,1 -k2,2n > "$PASABED"
}

# AED-like scoring for one stage (label, gtf/gff3, proteins.aa, [precomputed diamond])
score_stage(){
  local label="$1" gtf="$2" aa="$3" dmd="${4:-}"
  local d="$REF/aed/$label"; mkdir -p "$d"
  [ -s "$gtf" ] || { echo "[score:$label] no gtf, skip"; return 0; }
  run python "$SC/refine_rescue.py" cdsbed --gtf "$gtf" \
      --out-bed "$d/cds.bed" --out-len "$d/genelen.tsv"
  sort -k1,1 -k2,2n "$d/cds.bed" > "$d/cds.sorted.bed"
  run bedtools coverage -a "$d/cds.sorted.bed" -b "$BAM" > "$d/cov.tsv" 2>>"$LOG" || true
  if [ -s "$PASABED" ]; then
    run bedtools coverage -a "$d/cds.sorted.bed" -b "$PASABED" > "$d/txcov.tsv" 2>>"$LOG" || true
  fi
  if [ -z "$dmd" ]; then
    dmd="$d/diamond.tsv"
    [ -s "$aa" ] && run diamond blastp -q "$aa" -d "${NASDMND%.dmnd}" -p "$THREADS" \
        -e 1e-5 -k 1 --quiet --outfmt 6 qseqid sseqid pident length evalue bitscore qcovhsp \
        -o "$dmd" 2>>"$LOG" || true
  fi
  run python "$SC/refine_score.py" aed --cov "$d/cov.tsv" --txcov "$d/txcov.tsv" \
      --diamond "$dmd" --genelen "$d/genelen.tsv" --out "$REF/aed_${label}.tsv"
}

# ---- wait for EVM to finish (up to ~8 h) ---------------------------------
notify "[S.cam AED] watcher armed" "waiting for EVM consensus to finish (evm.gff3 + evm.aa)"
t=0
while [ $t -lt 480 ]; do
  # EVM is done when its driver process is gone
  if ! pgrep -f '[r]un_evm_consensus.sh' >/dev/null 2>&1; then break; fi
  sleep 60; t=$((t+1))
done
# small settle, then require the outputs
sleep 10
if [ ! -s "$EVM_GFF" ] || [ ! -s "$EVM/evm.aa" ]; then
  notify "[S.cam AED] ABORT" "EVM finished without evm.gff3/evm.aa; summary NOT refreshed. See evm log."
  echo "==== AED refresh watcher END (no EVM output) $(date -Iseconds) ===="; exit 1
fi

# EVM emits GFF3, but the AED/count parser (refine_rescue.parse_cds) reads
# GTF-style transcript_id/gene_id from CDS lines (braker.gtf/rescued.gtf). EVM's
# Parent= CDS attrs parse to 0 genes -> convert to GTF for scoring + counts.
EVM_GTF="$EVM/evm.gtf"
if [ ! -s "$EVM_GTF" ] || [ "$EVM_GFF" -nt "$EVM_GTF" ]; then
  run gffread "$EVM_GFF" -T -o "$EVM_GTF" 2>>"$LOG" || true
fi

# ---- STAGE C (evm only; braker_filtered + rescued tsvs reused) -----------
notify "[S.cam AED] refresh START" "scoring EVM stage + rebuilding cross-stage summary"
build_pasabed || true
if [ ! -s "$REF/aed_evm.tsv" ] || [ "$EVM_GTF" -nt "$REF/aed_evm.tsv" ]; then
  score_stage "evm" "$EVM_GTF" "$EVM/evm.aa" ""
fi

# ---- STAGE D (cross-stage manifest incl. EVM -> summary) -----------------
MAN="$REF/stage_manifest.tsv"
{
  printf "Genome assembly\t%s\t\t\n" "$PROJECT/qc/busco_results"
  printf "Nasonia proteome\t%s\t\t\n" "$BUSCODIR/nasonia_prot"
  printf "BRAKER (filtered)\t%s\t%s\t%s\n" "$BUSCODIR/braker_prot" "$REF/aed_braker_filtered.tsv" "$BR/braker.gtf"
  printf "Rescued (single-exon)\t%s\t%s\t%s\n" "$BUSCODIR/rescued_prot" "$REF/aed_rescued.tsv" "$REF/rescued.gtf"
  printf "EVM consensus\t%s\t%s\t%s\n" "$BUSCODIR/evm_prot" "$REF/aed_evm.tsv" "$EVM_GTF"
} > "$MAN"
run python "$SC/refine_score.py" summary --manifest "$MAN" \
    --out-tsv "$STATS/refinement_summary.tsv" --out-fig "$FIG/refinement_summary.png"

SUMTXT=$(cat "$STATS/refinement_summary.tsv" 2>/dev/null)
notify "[S.cam AED] refresh DONE" "Cross-stage summary now includes EVM ($STATS/refinement_summary.tsv):
$SUMTXT

Figure: $FIG/refinement_summary.png"
echo "==== AED refresh watcher END $(date -Iseconds) ===="
