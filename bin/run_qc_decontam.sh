#!/bin/bash
# =============================================================
# Run QC + Decontamination phases (1.1 → 1.2 → 1.2b) in nohup.
# Sends email after EACH phase: subject indicates success or failure.
# Stops the chain on first failure (so you don't waste time on a
# Kraken2 run if cutadapt died).
#
# Usage:
#   ./run_qc_decontam.sh              # start in background
#   ./run_qc_decontam.sh tail         # follow the log
#   ./run_qc_decontam.sh status       # show pipeline step status
#   ./run_qc_decontam.sh stop         # stop the running chain
# =============================================================

set -uo pipefail

PROJECT_DIR="/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly"
PIPELINE="$PROJECT_DIR/genome_assembly_pipeline.py"
NOTIFY="$PROJECT_DIR/send_notification.py"
CONDA_ENV="genome_assembly"
LOG="$PROJECT_DIR/qc_decontam.log"
PID_FILE="$PROJECT_DIR/qc_decontam.pid"
PHASES=("1.1" "1.2" "1.2b")

cd "$PROJECT_DIR"

case "${1:-run}" in
    "tail")
        [ -f "$LOG" ] && tail -f "$LOG" || echo "No log yet."
        exit 0 ;;
    "status")
        eval "$(conda shell.bash hook)"; conda activate "$CONDA_ENV" 2>/dev/null || true
        python3 "$PIPELINE" --status
        exit 0 ;;
    "stop")
        if [ -f "$PID_FILE" ]; then
            PID=$(cat "$PID_FILE")
            if kill -0 "$PID" 2>/dev/null; then
                kill "$PID" && rm -f "$PID_FILE"
                echo "Stopped (PID $PID)."
            else
                rm -f "$PID_FILE"; echo "Stale PID, cleaned."
            fi
        else
            echo "Not running."
        fi
        exit 0 ;;
    "run"|"")
        ;;
    *)
        echo "Usage: $0 [run|tail|status|stop]"; exit 1 ;;
esac

# Already running?
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        echo "Already running (PID $PID). Use '$0 tail' or '$0 stop'."
        exit 1
    else
        rm -f "$PID_FILE"
    fi
fi

# Background runner
nohup bash -c '
    set -uo pipefail
    cd "'"$PROJECT_DIR"'"
    eval "$(conda shell.bash hook)"
    conda activate "'"$CONDA_ENV"'" 2>/dev/null || true

    echo "=== QC+Decontam chain started: $(date) ==="

    for PHASE in '"${PHASES[*]}"'; do
        START_TS=$(date "+%Y-%m-%d %H:%M:%S")
        echo ""
        echo "============================================================"
        echo " >>> Phase $PHASE — START $START_TS"
        echo "============================================================"

        python3 -u "'"$PIPELINE"'" --phase "$PHASE"
        EXIT=$?
        END_TS=$(date "+%Y-%m-%d %H:%M:%S")

        if [ $EXIT -eq 0 ]; then
            echo " >>> Phase $PHASE — DONE $END_TS"
            python3 "'"$NOTIFY"'" \
                "[Pipeline] Phase $PHASE COMPLETE — S. cameroni QC/decontam" \
                "Phase $PHASE finished successfully.

Started:  $START_TS
Finished: $END_TS
Log:      '"$LOG"'

Next phase will start automatically (if any remain)." \
                || echo "(email send failed — continuing)"
        else
            echo " >>> Phase $PHASE — FAILED (exit $EXIT) at $END_TS"
            TAIL=$(tail -40 "'"$LOG"'")
            python3 "'"$NOTIFY"'" \
                "[Pipeline] Phase $PHASE FAILED — S. cameroni QC/decontam" \
                "Phase $PHASE failed with exit code $EXIT.

Started:  $START_TS
Failed:   $END_TS
Log:      '"$LOG"'

Chain HALTED — remaining phases skipped.

Last 40 log lines:
$TAIL" \
                || echo "(email send failed)"
            echo ""
            echo "=== Chain halted at phase $PHASE: $(date) ==="
            exit $EXIT
        fi
    done

    echo ""
    echo "=== All phases complete: $(date) ==="
    python3 "'"$NOTIFY"'" \
        "[Pipeline] QC+Decontam CHAIN COMPLETE — S. cameroni" \
        "All phases (1.1, 1.2, 1.2b) finished successfully.

Log: '"$LOG"'

Ready for Phase 1.3 (k-mer survey) and Phase 2 (assembly)." \
        || true
' > "$LOG" 2>&1 &

echo $! > "$PID_FILE"
PID=$(cat "$PID_FILE")

echo "QC+Decontam chain started in background (PID $PID)."
echo "Phases: ${PHASES[*]}"
echo ""
echo "  Log:    $LOG"
echo "  Tail:   $0 tail"
echo "  Status: $0 status"
echo "  Stop:   $0 stop"
echo ""
echo "You'll get an email after each phase (success or fail)."
sleep 2
echo "=== First log lines ==="
head -10 "$LOG" 2>/dev/null || echo "(log not flushed yet)"
