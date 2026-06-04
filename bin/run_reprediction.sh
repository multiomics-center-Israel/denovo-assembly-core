#!/usr/bin/env bash
# ============================================================================
# RE-PREDICTION with OrthoDB Arthropoda proteins  — detached, gated, emailing
# ============================================================================
# Wires the broad OrthoDB Arthropoda partition (all Hymenoptera + arthropods,
# the protein DB BRAKER/ProtHint is designed for) into a fresh BRAKER3 ETP run
# alongside the RNA-seq BAM. Self-gates: downloads OrthoDB first, then WAITS for
# PASA + the model-refinement driver to finish so it doesn't oversubscribe the
# 16 cores. New species name + workdir so existing braker/ models are untouched.
# Best-effort; emails each stage.
# Launch: setsid bash -c '/mnt/data/.../run_reprediction.sh' >/dev/null 2>&1 &
# ============================================================================
set -uo pipefail
PROJECT=/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly
cd "$PROJECT"
source "$(conda info --base)/etc/profile.d/conda.sh"
RUNENV=genome_assembly
THREADS=16
GMETP="$PROJECT/tools/GeneMark-ETP"
export GENEMARK_PATH="$GMETP/bin"
export PROTHINT_PATH="$GENEMARK_PATH/gmes/ProtHint/bin"
export PATH="$GMETP/tools:$PATH"
MASKED="$PROJECT/annotation/repeats/final_assembly.fa.masked"
BAM="$PROJECT/rnaseq/rnaseq_aligned.bam"
ODBDIR="$PROJECT/orthodb"; ODB="$ODBDIR/Arthropoda.fa"
WD="$PROJECT/annotation/braker_odb"
LIN="$PROJECT/busco_downloads/lineages/hymenoptera_odb10"
mkdir -p "$ODBDIR" "$PROJECT/logs"
TS=$(date +%Y%m%d_%H%M%S); LOG="$PROJECT/logs/reprediction_${TS}.log"
exec > >(tee -a "$LOG") 2>&1
echo "==== re-prediction driver START $(date -Iseconds)  PID=$$  PPID=$PPID ===="
notify(){ PYTHONPATH="$PROJECT/denovo-assembly-core" python3 -m denovo_assembly_core.notify \
          --config "$PROJECT/project.yaml" "$1" "${2:-}" 2>>"$LOG" || true; }
run(){ conda run -n "$RUNENV" "$@"; }
notify "[S.cam reprediction] launched" "PID=$$ log=$LOG (download OrthoDB -> wait -> BRAKER3 ETP)"

# ---- STAGE 1: OrthoDB Arthropoda (download during the gate wait) ----
if [ ! -s "$ODB" ]; then
  notify "[S.cam reprediction] OrthoDB download START" "~4.7 GB Arthropoda.fa.gz"
  if wget -q -O "$ODB.gz" https://bioinf.uni-greifswald.de/bioinf/partitioned_odb12/Arthropoda.fa.gz \
       && gunzip -f "$ODB.gz"; then
    notify "[S.cam reprediction] OrthoDB ready" "$(grep -c '^>' "$ODB" 2>/dev/null) proteins -> $ODB"
  else
    notify "[S.cam reprediction] OrthoDB download FAIL" "aborting re-prediction"; exit 1
  fi
fi

# ---- STAGE 2: gate on PASA + refinement finishing (free the cores) ----
notify "[S.cam reprediction] waiting for PASA + refinement to free cores" "polls every 5 min"
t=0
while [ $t -lt 200 ]; do
  pgrep -f 'Launch_PASA_pipeline' >/dev/null 2>&1 || \
  pgrep -f 'run_model_refinement.sh' >/dev/null 2>&1 || break
  sleep 300; t=$((t+1))
done
echo "[gate] cores free (or timeout) at $(date -Iseconds)"

# ---- STAGE 3: BRAKER3 ETP — RNA-seq + OrthoDB Arthropoda proteins ----
notify "[S.cam reprediction] BRAKER3 START" "genome=masked bam=rnaseq prot=OrthoDB/Arthropoda species=spalangia_odb"
rm -rf "$WD"
if run braker.pl --genome="$MASKED" --bam="$BAM" --prot_seq="$ODB" \
     --species=spalangia_odb --workingdir="$WD" --threads="$THREADS" \
     --softmasking --gff3 --GENEMARK_PATH="$GENEMARK_PATH" --PROTHINT_PATH="$PROTHINT_PATH" >>"$LOG" 2>&1; then
  notify "[S.cam reprediction] BRAKER3 DONE" "models: $WD/braker.{aa,gtf,gff3}"
else
  notify "[S.cam reprediction] BRAKER3 FAIL" "see $LOG (check getAnnoFastaFromJoingenes patch / GeneMark)"; exit 1
fi

# ---- STAGE 4: BUSCO + structure compare ----
if [ -s "$WD/braker.aa" ]; then
  run busco -i "$WD/braker.aa" -l "$LIN" -m protein -c "$THREADS" --offline \
      --download_path "$PROJECT/busco_downloads" --out_path "$PROJECT/analysis/busco" -o odb_prot -f >>"$LOG" 2>&1 || true
  run python "$PROJECT/annotation/scripts/compare_gene_structure.py" \
      --a "Nasonia vitripennis:$PROJECT/analysis/nasonia_compare/GCF_009193385.2_Nvit_psr_1.1_genomic.gff" \
      --b "S. cameroni (OrthoDB re-pred):$WD/braker.gff3" \
      --out-fig "$PROJECT/annotation/figures/nasonia_vs_odb_structure.png" \
      --out-tsv "$PROJECT/analysis/stats/structure_comparison_odb.tsv" >>"$LOG" 2>&1 || true
  notify "[S.cam reprediction] ALL DONE" "BUSCO: $(grep -h 'C:' "$PROJECT"/analysis/busco/odb_prot/short_summary*.txt 2>/dev/null | head -1)
genes: $(grep -c $'\tgene\t' "$WD/braker.gtf" 2>/dev/null)
compare: $PROJECT/analysis/stats/structure_comparison_odb.tsv"
fi
echo "==== re-prediction driver END $(date -Iseconds) ===="
