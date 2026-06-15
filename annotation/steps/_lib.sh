#!/usr/bin/env bash
# _lib.sh — shared library for the S. cameroni pipeline runners (assembly + annotation).
# Sourced by run_assembly_pipeline.sh, run_annotation_pipeline.sh, and every step wrapper.
#
# Single source of truth for: project paths, conda execution, per-step reporting,
# nohup/setsid detached launches, and step status. Both the bash runners and the
# NeatSeq-Flow Generic modules call the SAME step wrappers, so logic never drifts.
#
# Step wrapper contract:
#   bash <wrapper>.sh --check     -> exit 0 if the step's outputs already exist (DONE), else 1
#   bash <wrapper>.sh             -> run the step (skips fast if --check passes, unless FORCE=1)
#   FORCE=1 bash <wrapper>.sh     -> force re-run
# Each wrapper sources this lib, defines step_check() and step_run(), then calls step_main "$@".

set -o pipefail

# ---- project layout -------------------------------------------------------
# PROJECT_ROOT resolves to the repo root regardless of where a wrapper is invoked.
if [[ -z "${PROJECT_ROOT:-}" ]]; then
  PROJECT_ROOT="/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly"
fi
export PROJECT_ROOT
export LOGDIR="${PROJECT_ROOT}/logs"
export CONDA_BASE="/home/multiomics/miniforge3"

# Per-domain dirs are set by the caller via PIPE_DOMAIN (assembly|annotation).
export PIPE_DOMAIN="${PIPE_DOMAIN:-annotation}"
export DOMAIN_DIR="${PROJECT_ROOT}/${PIPE_DOMAIN}"
export STEPS_DIR="${DOMAIN_DIR}/steps"
export STATE_DIR="${DOMAIN_DIR}/state"
export REPORTS_DIR="${DOMAIN_DIR}/reports"
export REPORT_MD="${DOMAIN_DIR}/REPORT.md"
mkdir -p "$LOGDIR" "$STATE_DIR" "$REPORTS_DIR" 2>/dev/null || true

# ---- timestamp / logging --------------------------------------------------
ts()       { date +%Y%m%d_%H%M%S; }
now_iso()  { date "+%Y-%m-%d %H:%M:%S"; }
say()      { printf '%s [%s] %s\n' "$(now_iso)" "${STEP_ID:-pipe}" "$*"; }

# ---- conda execution ------------------------------------------------------
# crun <env> <cmd...> : run a command inside a named conda env without activating
# the shell. Keeps the orchestrating env (e.g. NeatSeq_Flow py3.6) decoupled from
# the tool envs (genome_assembly / funannotate / evm).
crun() {
  local env="$1"; shift
  "${CONDA_BASE}/bin/conda" run --no-capture-output -n "$env" "$@"
}

# ---- email notification (Technion SMTP relay; same path the assembly pipeline used) ----
export NOTIFY_PY="${NOTIFY_PY:-${PROJECT_ROOT}/.legacy_local_scripts_20260507/send_notification.py}"
export NOTIFY_ENABLED="${NOTIFY_ENABLED:-1}"
export NOTIFY_SENT_DIR="${STATE_DIR}/notify_sent"

# notify_email <dedup_key> <subject> <body> : send at most once per dedup_key.
# A shared on-disk ledger (NOTIFY_SENT_DIR) lets emit_report and any external chain
# watcher both attempt a stage while exactly one wins (atomic noclobber claim).
# Non-fatal + backgrounded so a slow/down relay never blocks or fails a pipeline step.
notify_email() {
  [[ "${NOTIFY_ENABLED}" == "1" ]] || return 0
  [[ -f "$NOTIFY_PY" ]] || return 0
  local key="$1" subj="$2" body="$3"
  mkdir -p "$NOTIFY_SENT_DIR" 2>/dev/null || true
  local marker="${NOTIFY_SENT_DIR}/${key//[^A-Za-z0-9._-]/_}"
  if ( set -o noclobber; : > "$marker" ) 2>/dev/null; then
    ( timeout 40 python3 "$NOTIFY_PY" "$subj" "$body" >/dev/null 2>&1 || rm -f "$marker" ) &
  fi
}

# notify_stage <id> <status> <frag> : email one stage using its report fragment as body.
notify_stage() {
  local id="$1" status="$2" frag="$3" body
  body="$( [[ -s "$frag" ]] && sed 's/^/  /' "$frag" || echo "  (no report fragment)" )"
  notify_email "${id}_${status}" "[S.cameroni ${PIPE_DOMAIN}] ${id} — ${status}" "$body"
}

# ---- per-step reporting ---------------------------------------------------
# emit_report <step_id> <status> [k=v ...]
# Writes reports/<id>.md (overwrite) and appends a dated block to the domain REPORT.md.
emit_report() {
  local id="$1" status="$2"; shift 2
  local frag="${REPORTS_DIR}/${id}.md"
  {
    echo "### ${id} — ${status}"
    echo ""
    echo "- when: $(now_iso)"
    echo "- domain: ${PIPE_DOMAIN}"
    local kv
    for kv in "$@"; do echo "- ${kv%%=*}: ${kv#*=}"; done
    [[ -n "${STEP_LOG:-}" ]] && echo "- log: ${STEP_LOG}"
  } > "$frag"

  {
    echo ""
    echo "## [$(now_iso)] ${id} — ${status}"
    for kv in "$@"; do echo "- ${kv%%=*}: ${kv#*=}"; done
    [[ -n "${STEP_LOG:-}" ]] && echo "- log: ${STEP_LOG}"
  } >> "$REPORT_MD"

  # per-stage email (shared dedup ledger with any external chain watcher)
  notify_stage "$id" "$status" "$frag"
}

# ---- status helpers (status derived from wrapper --check + pid files) ------
step_status() {           # echo DONE|RUNNING|FAILED|PENDING for a wrapper path
  local wrapper="$1" id="$2"
  local pidf="${STATE_DIR}/${id}.pid"
  if [[ -f "$pidf" ]] && kill -0 "$(cat "$pidf" 2>/dev/null)" 2>/dev/null; then
    echo RUNNING; return
  fi
  if FORCE=0 bash "$wrapper" --check >/dev/null 2>&1; then echo DONE; return; fi
  if [[ -f "${STATE_DIR}/${id}.failed" ]]; then echo FAILED; return; fi
  echo PENDING
}

# ---- detached launch (requirement b: survives session detach) -------------
# launch_long <id> <wrapper> : run a LONG step under nohup+setsid, reparented to init.
launch_long() {
  local id="$1" wrapper="$2"
  local log="${LOGDIR}/${id}_$(ts).log"
  rm -f "${STATE_DIR}/${id}.failed" 2>/dev/null || true
  STEP_LOG="$log" nohup setsid bash -c \
    "STEP_LOG='$log' bash '$wrapper'; rc=\$?; rm -f '${STATE_DIR}/${id}.pid'; \
     [[ \$rc -ne 0 ]] && touch '${STATE_DIR}/${id}.failed'; exit \$rc" \
    >"$log" 2>&1 &
  echo $! > "${STATE_DIR}/${id}.pid"
  say "launched ${id} detached (pid $(cat "${STATE_DIR}/${id}.pid")) -> ${log}"
}

# launch_chain <chain_id> <wrapper1> [wrapper2 ...] : run an ORDERED list of step
# wrappers sequentially inside ONE detached (nohup+setsid) process. Used for multi-step
# ranges so dependent steps (E11->E12->E13->E14) run in order and the whole chain
# survives session detach. Stops the chain if any step fails.
launch_chain() {
  local cid="$1"; shift
  local wrappers=("$@")
  local log="${LOGDIR}/chain_${cid}_$(ts).log"
  rm -f "${STATE_DIR}/chain_${cid}.failed" 2>/dev/null || true
  local script=""
  local w
  for w in "${wrappers[@]}"; do
    script+="echo '=== STEP: ${w} ==='; STEP_LOG='${log}' FORCE='${FORCE:-0}' bash '${w}' || { touch '${STATE_DIR}/chain_${cid}.failed'; echo 'CHAIN ABORTED at ${w}'; exit 1; }; "
  done
  script+="rm -f '${STATE_DIR}/chain_${cid}.pid'; echo '=== CHAIN DONE ==='"
  nohup setsid bash -c "$script" >"$log" 2>&1 &
  echo $! > "${STATE_DIR}/chain_${cid}.pid"
  say "launched chain ${cid} detached (pid $(cat "${STATE_DIR}/chain_${cid}.pid"), ${#wrappers[@]} steps) -> ${log}"
}

# ---- step wrapper entrypoint ----------------------------------------------
# Wrappers define step_check() and step_run(), then call: step_main "$@"
step_main() {
  : "${STEP_ID:?wrapper must set STEP_ID}"
  if [[ "${1:-}" == "--check" ]]; then
    step_check && exit 0 || exit 1
  fi
  if [[ "${FORCE:-0}" != "1" ]] && step_check; then
    say "outputs present — skipping (FORCE=1 to re-run)"
    emit_report "$STEP_ID" "SKIPPED (already done)"
    exit 0
  fi
  local start; start=$(date +%s)
  say "START"
  if step_run; then
    local dur=$(( $(date +%s) - start ))
    say "DONE in ${dur}s"
    emit_report "$STEP_ID" "DONE" "runtime_s=${dur}"
    exit 0
  else
    local rc=$?
    say "FAILED rc=${rc}"
    emit_report "$STEP_ID" "FAILED" "rc=${rc}"
    exit "$rc"
  fi
}
