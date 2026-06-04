#!/bin/bash
# =============================================================
# denovo-assembly-core — annotation sub-pipeline launcher
# =============================================================
# Runs phases 7.2 → 7.5 (RNA-Seq download, alignment, gene prediction,
# functional annotation) as a SEPARATE sub-pipeline gated on user approval.
# The main pipeline (run_pipeline.sh) stops at 7.1; this script picks up.
#
# Usage:
#   run_annotation.sh [--project-dir DIR] [--config FILE] [--force]
#
# Pre-flight checks:
#   - Refuses to launch unless phase 7.1 (repeats) is COMPLETED in
#     pipeline_status.json (override with --force, not recommended).
#
# Inputs:
#   --project-dir DIR   Project directory (default: $PWD).
#   --config FILE       Path to project.yaml (default: $PROJECT_DIR/project.yaml).
#   --force             Skip the 7.1-complete pre-flight check.
#
# Logs:
#   $PROJECT_DIR/nohup_annotation.log
#   $PROJECT_DIR/annotation.pid
# =============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

PROJECT_DIR=""
PROJECT_CONFIG_ARG=""
FORCE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-dir) PROJECT_DIR="$2"; shift 2 ;;
        --config)      PROJECT_CONFIG_ARG="$2"; shift 2 ;;
        --force)       FORCE=1; shift ;;
        -h|--help)     sed -n '2,30p' "$0"; exit 0 ;;
        *) echo "Unknown arg: $1"; sed -n '2,30p' "$0"; exit 2 ;;
    esac
done

PROJECT_DIR="${PROJECT_DIR:-$PWD}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
PROJECT_CONFIG="${PROJECT_CONFIG_ARG:-${PROJECT_CONFIG:-$PROJECT_DIR/project.yaml}}"

if [[ ! -f "$PROJECT_CONFIG" ]]; then
    echo "Error: project config not found: $PROJECT_CONFIG"
    exit 1
fi

NOHUP_LOG="$PROJECT_DIR/nohup_annotation.log"
PID_FILE="$PROJECT_DIR/annotation.pid"
STATUS_JSON="$PROJECT_DIR/pipeline_status.json"

# ── Pre-flight: phase 7.1 must be done ────────────────────────
if [[ "$FORCE" -ne 1 ]]; then
    if [[ ! -f "$STATUS_JSON" ]]; then
        echo "Error: $STATUS_JSON not found — main pipeline hasn't run yet."
        exit 1
    fi
    p71_status=$(python3 -c "
import json, sys
try:
    d = json.load(open('$STATUS_JSON'))
    print(d.get('phase7.1_repeats', {}).get('status', 'missing'))
except Exception as e:
    print(f'error:{e}', file=sys.stderr); sys.exit(1)
")
    if [[ "$p71_status" != "completed" ]]; then
        echo "Refusing to launch: phase7.1_repeats status is '$p71_status', not 'completed'."
        echo "Run the main pipeline first (./run_pipeline.sh) or pass --force to override."
        exit 1
    fi
    echo "Pre-flight OK: phase 7.1 is completed."
fi

# ── Active pipeline guard ─────────────────────────────────────
if [[ -f "$PID_FILE" ]]; then
    existing_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
        echo "Annotation pipeline already running (PID $existing_pid). Stop it first."
        exit 1
    fi
    rm -f "$PID_FILE"
fi

# Activate conda env
export PYTHONPATH="$REPO_DIR:${PYTHONPATH:-}"
export PROJECT_CONFIG
CONDA_ENV="$(python3 -c 'import sys, yaml; d=yaml.safe_load(open(sys.argv[1])); print((d.get("conda") or {}).get("env","genome_assembly"))' "$PROJECT_CONFIG")"
if command -v conda >/dev/null 2>&1; then
    eval "$(conda shell.bash hook)"
    conda activate "$CONDA_ENV" 2>/dev/null || true
fi

cat <<EOF
============================================================
  denovo-assembly-core — annotation sub-pipeline
  Project:  $PROJECT_DIR
  Config:   $PROJECT_CONFIG
  Phases:   7.2 → 7.5
  Log:      $NOHUP_LOG
  Mode:     nohup (survives disconnect)
============================================================
EOF

cd "$PROJECT_DIR"
nohup python3 -u -m denovo_assembly_core.pipeline \
    --config "$PROJECT_CONFIG" \
    --phase 7.2-7.5 \
    > "$NOHUP_LOG" 2>&1 &
ANN_PID=$!
echo "$ANN_PID" > "$PID_FILE"
echo "Annotation pipeline started (PID $ANN_PID)"
echo ""
echo "Monitor with:"
echo "  tail -f $NOHUP_LOG"
echo "  $SCRIPT_DIR/run_pipeline.sh --project-dir '$PROJECT_DIR' status"
echo ""
echo "Stop with:"
echo "  kill \$(cat $PID_FILE)"
echo ""
sleep 2
echo "=== First log lines ==="
head -20 "$NOHUP_LOG" 2>/dev/null || echo "(log not yet flushed)"
