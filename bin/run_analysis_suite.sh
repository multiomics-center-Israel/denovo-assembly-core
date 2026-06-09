#!/usr/bin/env bash
# ============================================================================
# POST-ANNOTATION ANALYSIS SUITE  — parallel, detached, email at every step
# ============================================================================
# Runs pipeline phases 7.8-7.22 (Infernal/ncRNA-Rfam deferred) on the finished
# braker models. Native pipeline phases => each emits its own START/COMPLETED/
# FAILED email and the pptx auto-updates. Driver adds stage emails for installs
# and the long eggNOG/PASA work. Waits are only on DIRECT children.
#
# Branches (run concurrently):
#   FAST : 7.8 7.9 7.10 7.11 7.12 7.15 7.19      (inputs ready / quick-ish)
#   LONG-A: eggNOG DB DL -> emapper -> 7.17 KEGG + 7.21 naming
#   LONG-B: 7.13 PASA -> 7.14 UTR merge
#   then : 7.22 master merge ; FINAL pptx+report build
#
# Launch detached:
#   setsid bash -c '/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly/run_analysis_suite.sh' \
#          >/dev/null 2>&1 &
# Re-runnable: phases skip if their tracker step / output exists.
# ============================================================================
set -uo pipefail
PROJECT=/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly
cd "$PROJECT"
source "$(conda info --base)/etc/profile.d/conda.sh"
RUNENV=genome_assembly
THREADS=16
EGGDB="$PROJECT/eggnog_db"
mkdir -p "$PROJECT/logs" "$EGGDB" "$PROJECT/analysis"
TS=$(date +%Y%m%d_%H%M%S)
LOG="$PROJECT/logs/analysis_suite_${TS}.log"
exec > >(tee -a "$LOG") 2>&1
echo "==== analysis-suite driver START $(date -Iseconds)  PID=$$  PPID=$PPID ===="

notify(){ PYTHONPATH="$PROJECT/denovo-assembly-core" python3 -m denovo_assembly_core.notify \
          --config "$PROJECT/project.yaml" "$1" "${2:-}" 2>>"$LOG" || true; }
run_pipe(){ PYTHONPATH="$PROJECT/denovo-assembly-core" conda run -n "$RUNENV" \
            python -m denovo_assembly_core.pipeline --config "$PROJECT/project.yaml" \
            --phase "$1" --force --no-report; }

notify "[S.cam analysis] driver launched" "PID=$$ host=$(hostname) log=$LOG
Phases 7.8-7.22 (no Infernal). eggNOG + PASA are the long poles."

# ===========================================================================
# STAGE 0 — one mamba transaction (tools for 7.10/7.11/7.13/7.19/7.21)
# ===========================================================================
echo "==== STAGE 0 installs $(date -Iseconds) ===="
notify "[S.cam analysis] STAGE0 installs START" "subread gffcompare tRNAscan-SE barrnap agat gffread eggnog-mapper pasa"
if conda run -n "$RUNENV" bash -c 'command -v featureCounts && command -v gffcompare && command -v tRNAscan-SE && command -v barrnap' >/dev/null 2>&1; then
  echo "[STAGE0] core analysis tools already present"
else
  mamba install -y -n "$RUNENV" -c bioconda -c conda-forge \
      subread gffcompare trnascan-se barrnap gffread eggnog-mapper pasa \
    && notify "[S.cam analysis] STAGE0 installs DONE" "ok" \
    || notify "[S.cam analysis] STAGE0 installs WARN" "some tools may be missing; phases will skip those"
fi

# ===========================================================================
# LONG-A as a background child: eggNOG DB (~50 GB) -> emapper -> KEGG + naming
# ===========================================================================
branch_longA(){
  notify "[S.cam analysis] eggNOG DB download START" "~50 GB into $EGGDB"
  if [ ! -s "$EGGDB/eggnog.db" ]; then
    conda run -n "$RUNENV" download_eggnog_data.py -y --data_dir "$EGGDB" \
      && notify "[S.cam analysis] eggNOG DB DONE" "$EGGDB" \
      || { notify "[S.cam analysis] eggNOG DB FAIL" "KEGG/naming will use Nasonia-only fallback"; }
  fi
  ANN="$PROJECT/analysis/kegg/eggnog.emapper.annotations"
  mkdir -p "$PROJECT/analysis/kegg"
  if [ ! -s "$ANN" ] && [ -s "$EGGDB/eggnog.db" ]; then
    notify "[S.cam analysis] emapper START" "braker.aa -> KO/GO/products"
    conda run -n "$RUNENV" emapper.py -i "$PROJECT/annotation/braker/braker.aa" \
      --itype proteins -m diamond --data_dir "$EGGDB" --cpu "$THREADS" --override \
      -o eggnog --output_dir "$PROJECT/analysis/kegg" \
      && notify "[S.cam analysis] emapper DONE" "annotations ready" \
      || notify "[S.cam analysis] emapper FAIL" "naming falls back to Nasonia products"
  fi
  run_pipe 7.17; echo "7.17 rc=$?"      # KEGG housekeeping (skips if annotations absent)
  run_pipe 7.21; echo "7.21 rc=$?"      # naming (eggNOG + Nasonia)
}

# ===========================================================================
# LONG-B as a background child: PASA -> UTR merge
# ===========================================================================
branch_longB(){
  run_pipe 7.13; echo "7.13 rc=$?"      # PASA (best-effort)
  run_pipe 7.14; echo "7.14 rc=$?"      # merge lightweight + PASA UTRs
}

# ===========================================================================
# FAST branch (this shell): quick analyses, inputs ready
# ===========================================================================
branch_longA & PA=$!
branch_longB & PB=$!

for p in 7.8 7.9 7.10 7.11 7.12 7.15 7.19; do
  echo "==== FAST phase $p $(date -Iseconds) ===="
  run_pipe "$p"; echo "$p rc=$?"
done

echo "[driver] waiting on long branches ..."
wait "$PA"; echo "longA done"
wait "$PB"; echo "longB done"

# ===========================================================================
# 7.22 master merge + FINAL pptx/report
# ===========================================================================
run_pipe 7.22; echo "7.22 rc=$?"
echo "==== FINAL report + pptx $(date -Iseconds) ===="
PYTHONPATH="$PROJECT/denovo-assembly-core" conda run -n "$RUNENV" python - <<'PY'
from denovo_assembly_core.config import Config
from denovo_assembly_core.pipeline import StatusTracker, ReportGenerator, PptxUpdater
cfg = Config("project.yaml"); tr = StatusTracker(cfg.STATUS_FILE)
try: ReportGenerator(cfg, tr).update()
except Exception as e: print("report:", e)
try: PptxUpdater(cfg, tr).update()
except Exception as e: print("pptx:", e)
print("final report+pptx done")
PY

echo "==== analysis-suite driver FINISHED $(date -Iseconds) ===="
notify "[S.cam analysis] ALL FINISHED" "Driver complete $(date -Iseconds).
Deliverables under analysis/ + annotation/{figures,tracks}:
  nasonia_compare/  busco/  expression/  transcript_compare/  utr/  ncrna/
  kegg/  naming/Spalangia_cameroni.annotated.{gff3,gtf}  final/Spalangia_cameroni.annotation.gff3
  tracks/{rnaseq_coverage.rp10m.bw, repeats.bb, ncRNA.bed.gz}
  Pipeline_v3_Plan.pptx (all plots embedded)
Long poles that may have warned: eggNOG DB, PASA. Log: $LOG"
