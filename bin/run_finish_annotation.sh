#!/usr/bin/env bash
# ============================================================================
# FINISH-ANNOTATION DRIVER  — parallel, detached, email at every transition
# ============================================================================
# Completes the S. cameroni annotation on the 4,980-contig genome.
#
# Orchestration (waits are only ever on DIRECT children — bash limitation):
#   STAGE 0  one-shot install into genome_assembly  (deeptools, ucsc-bigwig,
#            python-pptx, GeneMark perl deps) — blocking, ~1-2 min, ONE mamba
#            txn so nothing else writes the env concurrently.
#   STAGE 1  GeneMark-ETP git clone (quick).
#   Then two parallel branches:
#     Branch A (critical path):  funannotate env+DB download (bg) ‖ 7.4 BRAKER3,
#                                then wait DB → 7.5 funannotate annotate
#     Branch B (independent):    7.6 figures  →  7.7 BigWig tracks
#   FINAL    one report + Pipeline_v3_Plan.pptx build (embeds figures)
#
# Launch detached so you can close the shell:
#   setsid bash -c '/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly/run_finish_annotation.sh' \
#          >/dev/null 2>&1 &
# Re-runnable: every step skips if its output/binary already exists.
# ============================================================================
set -uo pipefail
PROJECT=/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly
cd "$PROJECT"
source "$(conda info --base)/etc/profile.d/conda.sh"

# NB: /mnt/data/{tools,dbs} are NOT writable here — keep tools + big DB under the
# project (same 1.9 TB /mnt/data volume, writable).
export TOOLS=$PROJECT/tools
export GMETP_DIR=$TOOLS/GeneMark-ETP
export FUNDB=$PROJECT/funannotate_db
RUNENV=genome_assembly
FA_ENV=funannotate
FA_BUSCO=insecta
THREADS=16

mkdir -p "$PROJECT/logs" "$TOOLS" "$FUNDB"
TS=$(date +%Y%m%d_%H%M%S)
LOG=$PROJECT/logs/finish_annotation_${TS}.log
exec > >(tee -a "$LOG") 2>&1
echo "==== finish-annotation driver START $(date -Iseconds)  PID=$$  PPID=$PPID ===="

notify(){ PYTHONPATH="$PROJECT/denovo-assembly-core" python3 -m denovo_assembly_core.notify \
          --config "$PROJECT/project.yaml" "$1" "${2:-}" 2>>"$LOG" || true; }

run_pipe(){ # $1 = phase ; one phase, --no-report (final build done once at end)
  PYTHONPATH="$PROJECT/denovo-assembly-core" \
  conda run -n "$RUNENV" python -m denovo_assembly_core.pipeline \
    --config "$PROJECT/project.yaml" --phase "$1" --force --no-report; }

notify "[S.cam annot] driver launched" "PID=$$  host=$(hostname)  log=$LOG
Stage 0 env install starting; BRAKER + funannotate + figures + tracks to follow."

# ===========================================================================
# STAGE 0 — single mamba transaction into genome_assembly (no concurrency)
# ===========================================================================
echo "==== STAGE 0: install tools into $RUNENV $(date -Iseconds) ===="
notify "[S.cam annot] STAGE0 env install START" "deeptools, ucsc-bigwig, python-pptx, GeneMark perl deps"
if conda run -n "$RUNENV" bash -c 'command -v bamCoverage && command -v bedGraphToBigWig && python -c "import pptx"' >/dev/null 2>&1; then
  echo "[STAGE0] tools already present — skipping"
else
  mamba install -y -n "$RUNENV" -c bioconda -c conda-forge \
      deeptools ucsc-bedgraphtobigwig python-pptx \
      perl-yaml perl-hash-merge perl-parallel-forkmanager perl-mce \
      perl-math-utils perl-thread-queue perl-file-which perl-logger-simple \
      perl-app-cpanminus \
    && notify "[S.cam annot] STAGE0 env install DONE" "ok" \
    || notify "[S.cam annot] STAGE0 env install WARN" "mamba returned non-zero — continuing; phases will report if a tool is missing"
fi
# GeneMark-ETP needs Statistics::LineFit (not on bioconda) — idempotent cpanm install.
conda run -n "$RUNENV" perl -MStatistics::LineFit -e1 >/dev/null 2>&1 \
  || conda run -n "$RUNENV" cpanm --notest Statistics::LineFit >/dev/null 2>&1 || true

# ===========================================================================
# STAGE 1 — GeneMark-ETP clone (quick; perl deps already installed in STAGE 0)
# ===========================================================================
echo "==== STAGE 1: GeneMark-ETP clone $(date -Iseconds) ===="
notify "[S.cam annot] STAGE1 GeneMark clone START" "$(date -Iseconds)"
GM=""
# BRAKER3 (GeneMark-ETP mode) wants $GENEMARK_PATH = dir containing gmetp.pl.
if find "$GMETP_DIR" -name gmetp.pl 2>/dev/null | grep -q .; then
  echo "[STAGE1] GeneMark already present"
else
  rm -rf "$GMETP_DIR"
  git clone --depth 1 https://github.com/gatech-genemark/GeneMark-ETP.git "$GMETP_DIR" || true
fi
GM=$(dirname "$(find "$GMETP_DIR" -name gmetp.pl 2>/dev/null | head -1)" 2>/dev/null)
if [ -n "$GM" ] && [ -f "$GM/gmetp.pl" ]; then
  echo "$GM" > "$PROJECT/logs/genemark_path.txt"
  notify "[S.cam annot] STAGE1 GeneMark clone DONE" "GENEMARK_PATH=$GM"
else
  rm -f "$PROJECT/logs/genemark_path.txt"
  notify "[S.cam annot] STAGE1 GeneMark clone FAIL" "gmes_petap.pl not found — Branch A will skip BRAKER"
fi

# ===========================================================================
# BRANCH A — critical path: (funannotate env+DB in bg) ‖ BRAKER, then funannotate
# ===========================================================================
branch_A(){
  # kick off the long funannotate env+DB build as a CHILD of this branch so we
  # can legitimately wait on it later, while BRAKER runs concurrently.
  ( notify "[S.cam annot] J-funannotate env+DB START" "~30-50 GB download"
    # functional check: env name existing is not enough — the binary must work.
    if ! conda run -n "$FA_ENV" command -v funannotate >/dev/null 2>&1; then
      conda env remove -n "$FA_ENV" -y >/dev/null 2>&1 || true
      mamba create -y -n "$FA_ENV" -c bioconda -c conda-forge funannotate \
        || { notify "[S.cam annot] J-funannotate FAIL" "env create failed"; exit 1; }
    fi
    conda run -n "$FA_ENV" funannotate setup -d "$FUNDB" -b "$FA_BUSCO" \
      && notify "[S.cam annot] J-funannotate env+DB DONE" "DB at $FUNDB" \
      || { notify "[S.cam annot] J-funannotate DB FAIL" "7.5 will fall back to emapper"; exit 1; }
  ) & FA_PID=$!

  if [ -f "$PROJECT/logs/genemark_path.txt" ]; then
    export GENEMARK_PATH="$(cat "$PROJECT/logs/genemark_path.txt")"
    # ProtHint ships inside GeneMark-ETP; BRAKER needs $PROTHINT_PATH for --prot_seq.
    export PROTHINT_PATH="$GENEMARK_PATH/gmes/ProtHint/bin"
    # GeneMark-ETP needs its bundled tools (gffread, stringtie, samtools, hisat2,
    # diamond, bedtools) on PATH — they live in <GMETP>/tools.
    GMTOOLS="$(dirname "$GENEMARK_PATH")/tools"
    export PATH="$GENEMARK_PATH:$GENEMARK_PATH/gmes:$PROTHINT_PATH:$GMTOOLS:$PATH"
    echo "==== Branch A: 7.4 BRAKER3 (GENEMARK_PATH=$GENEMARK_PATH) $(date -Iseconds) ===="
    run_pipe 7.4; echo "7.4 rc=$?"
  else
    echo "[Branch A] GeneMark missing — skipping 7.4 (and 7.5 unless models already exist)"
  fi

  echo "[Branch A] waiting on funannotate env+DB ..."
  wait "$FA_PID" || echo "[Branch A] funannotate prep returned non-zero (7.5 may use fallback)"
  echo "==== Branch A: 7.5 funannotate annotate $(date -Iseconds) ===="
  run_pipe 7.5; echo "7.5 rc=$?"
}

# ===========================================================================
# BRANCH B — independent: figures then tracks (tools from STAGE 0)
# ===========================================================================
branch_B(){
  echo "==== Branch B: 7.6 figures $(date -Iseconds) ===="
  run_pipe 7.6; echo "7.6 rc=$?"
  echo "==== Branch B: 7.7 tracks $(date -Iseconds) ===="
  run_pipe 7.7; echo "7.7 rc=$?"
}

branch_A & PID_A=$!
branch_B & PID_B=$!
wait "$PID_A"; wait "$PID_B"

# ===========================================================================
# FINAL — single report + PPTX build (embeds figures, refreshes status)
# ===========================================================================
echo "==== FINAL: report + Pipeline_v3_Plan.pptx $(date -Iseconds) ===="
PYTHONPATH="$PROJECT/denovo-assembly-core" conda run -n "$RUNENV" python - <<'PY'
from denovo_assembly_core.config import Config
from denovo_assembly_core.pipeline import StatusTracker, ReportGenerator, PptxUpdater
cfg = Config("project.yaml")
tr = StatusTracker(cfg.STATUS_FILE)
try: ReportGenerator(cfg, tr).update()
except Exception as e: print("report:", e)
try: PptxUpdater(cfg, tr).update()
except Exception as e: print("pptx:", e)
print("final report+pptx build done")
PY

echo "==== finish-annotation driver FINISHED $(date -Iseconds) ===="
notify "[S.cam annot] ALL FINISHED" "Driver complete at $(date -Iseconds).
Deliverables:
  annotation/braker/braker.{aa,gff3}        (gene models)
  annotation/funannotate/annotate_results/  (functional annotation)
  annotation/figures/*.png|svg              (coverage / protein support / BUSCO)
  annotation/tracks/*.bw                     (JBrowse/IGV coverage tracks)
  Pipeline_v3_Plan.pptx                      (updated deck)
Full log: $LOG"
