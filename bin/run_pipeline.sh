#!/bin/bash
# =============================================================
# denovo-assembly-core — nohup runner
# =============================================================
# Wraps `python -m denovo_assembly_core.pipeline` so the run survives
# disconnects, captures logs, and emails on completion/failure.
#
# Usage:
#   run_pipeline.sh [--project-dir DIR] [--config FILE] <command>
#
# Commands:
#   all              Run all phases (background, survives disconnect)
#   <phase>          Run specific phase(s), e.g. '2', '2-3', '1.3'
#   from <phase>     Run from <phase> to the end
#   resume           Continue from first incomplete phase
#   list             List available phases
#   status           Show pipeline step status
#   tail             Live-follow the pipeline log
#   report           Regenerate HTML report, RESULTS.md, PPTX
#   stop             Stop the running pipeline
#   logs             Show recent log lines
#
# Inputs:
#   --project-dir DIR   Project working directory (default: $PWD).
#                       Logs, PID, status JSON live here.
#   --config FILE       Path to project.yaml (default: $PROJECT_DIR/project.yaml,
#                       overridable via $PROJECT_CONFIG).
# =============================================================

set -euo pipefail

# Resolve the repo root (this script lives in <repo>/bin/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# ── Parse leading flags ────────────────────────────────────────
PROJECT_DIR=""
PROJECT_CONFIG_ARG=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-dir) PROJECT_DIR="$2"; shift 2 ;;
        --config)      PROJECT_CONFIG_ARG="$2"; shift 2 ;;
        --) shift; break ;;
        -*) echo "Unknown flag: $1"; exit 2 ;;
        *) break ;;
    esac
done

PROJECT_DIR="${PROJECT_DIR:-$PWD}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
PROJECT_CONFIG="${PROJECT_CONFIG_ARG:-${PROJECT_CONFIG:-$PROJECT_DIR/project.yaml}}"

if [[ ! -f "$PROJECT_CONFIG" ]]; then
    echo "Error: project config not found: $PROJECT_CONFIG"
    echo "Pass --config FILE or place project.yaml in --project-dir."
    exit 1
fi

NOHUP_LOG="$PROJECT_DIR/nohup_pipeline.log"
PID_FILE="$PROJECT_DIR/pipeline.pid"

# Make the python package importable from anywhere
export PYTHONPATH="$REPO_DIR:${PYTHONPATH:-}"
export PROJECT_CONFIG

# Activate the conda env named in the YAML (best-effort).
CONDA_ENV="$(python3 -c 'import sys, yaml; d=yaml.safe_load(open(sys.argv[1])); print((d.get("conda") or {}).get("env","genome_assembly"))' "$PROJECT_CONFIG")"
if command -v conda >/dev/null 2>&1; then
    eval "$(conda shell.bash hook)"
    conda activate "$CONDA_ENV" 2>/dev/null || true
fi

PIPELINE_MOD="denovo_assembly_core.pipeline"
NOTIFY_MOD="denovo_assembly_core.notify"

usage() {
    sed -n '2,30p' "$0"
}

check_running() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            echo "Pipeline is already running (PID $PID)."
            echo "Use 'tail' to follow progress or 'stop' to stop it."
            return 0
        else
            rm -f "$PID_FILE"
        fi
    fi
    return 1
}

case "${1:-}" in
    ""|"-h"|"--help")
        usage
        ;;

    "status")
        python3 -m "$PIPELINE_MOD" --config "$PROJECT_CONFIG" --status
        ;;

    "list")
        python3 -m "$PIPELINE_MOD" --config "$PROJECT_CONFIG" --list
        ;;

    "tail")
        if [ -f "$NOHUP_LOG" ]; then
            echo "=== Following pipeline log (Ctrl+C to stop watching) ==="
            tail -f "$NOHUP_LOG"
        else
            echo "No log file found. Pipeline may not have started yet."
        fi
        ;;

    "report")
        python3 -m "$PIPELINE_MOD" --config "$PROJECT_CONFIG" --report
        echo "Reports regenerated."
        ;;

    "stop")
        if [ -f "$PID_FILE" ]; then
            PID=$(cat "$PID_FILE")
            if kill -0 "$PID" 2>/dev/null; then
                echo "Stopping pipeline (PID $PID)..."
                kill "$PID"
                rm -f "$PID_FILE"
                echo "Stopped. Completed steps are saved — re-run to resume."
            else
                echo "Pipeline not running (stale PID file). Cleaning up."
                rm -f "$PID_FILE"
            fi
        else
            echo "No running pipeline found."
        fi
        ;;

    "logs")
        if [ -f "$NOHUP_LOG" ]; then
            tail -100 "$NOHUP_LOG"
        else
            echo "No log file found."
        fi
        ;;

    *)
        case "$1" in
            "from")
                if [ -z "${2:-}" ]; then
                    echo "Error: 'from' requires a phase argument, e.g. 'from 3'"
                    exit 1
                fi
                PY_FLAGS="--from $2"
                LABEL="from $2"
                ;;
            "resume")
                PY_FLAGS="--resume"
                LABEL="resume"
                ;;
            *)
                PY_FLAGS="--phase $1"
                LABEL="$1"
                ;;
        esac

        if check_running; then
            exit 1
        fi

        echo "============================================================"
        echo "  denovo-assembly-core pipeline"
        echo "  Project: $PROJECT_DIR"
        echo "  Config:  $PROJECT_CONFIG"
        echo "  Phase(s): $LABEL"
        echo "  Log:     $NOHUP_LOG"
        echo "  Mode:    nohup (survives disconnect)"
        echo "============================================================"

        : > "$NOHUP_LOG"

        nohup bash -c "
            cd '$PROJECT_DIR'
            export PYTHONPATH='$REPO_DIR:\${PYTHONPATH:-}'
            export PROJECT_CONFIG='$PROJECT_CONFIG'
            python3 -u -m '$PIPELINE_MOD' --config '$PROJECT_CONFIG' $PY_FLAGS >> '$NOHUP_LOG' 2>&1
            EXIT_CODE=\$?
            if [ \$EXIT_CODE -eq 0 ]; then
                python3 -m '$NOTIFY_MOD' --config '$PROJECT_CONFIG' \
                    '[Pipeline] Phase $LABEL COMPLETE' \
                    \"Pipeline finished successfully.

Project: $PROJECT_DIR
Phase(s): $LABEL
Log: $NOHUP_LOG

Check RESULTS.md and pipeline_report.html for results.\"
            else
                TAIL=\$(tail -20 '$NOHUP_LOG')
                python3 -m '$NOTIFY_MOD' --config '$PROJECT_CONFIG' \
                    '[Pipeline] Phase $LABEL FAILED' \
                    \"Pipeline failed (exit code \$EXIT_CODE).

Project: $PROJECT_DIR
Phase(s): $LABEL
Log: $NOHUP_LOG

Last 20 log lines:
\$TAIL\"
            fi
        " &

        echo $! > "$PID_FILE"
        PID=$(cat "$PID_FILE")
        echo "Pipeline started (PID $PID)"
        echo
        echo "Monitor with:"
        echo "  $0 --project-dir '$PROJECT_DIR' tail"
        echo "  $0 --project-dir '$PROJECT_DIR' status"
        echo "  $0 --project-dir '$PROJECT_DIR' logs"
        echo "  $0 --project-dir '$PROJECT_DIR' stop"
        sleep 3
        echo
        echo "=== First log lines ==="
        head -20 "$NOHUP_LOG" 2>/dev/null || true
        ;;
esac
