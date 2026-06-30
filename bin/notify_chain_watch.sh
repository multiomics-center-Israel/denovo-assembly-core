#!/usr/bin/env bash
# notify_chain_watch.sh — email per stage for a running detached step chain.
#
# The chain's step wrappers self-email via emit_report -> notify_stage (when they
# load the current _lib.sh). This watcher covers the gaps: steps that started under
# an older in-memory _lib.sh (no email), plus the final chain-complete summary that
# nothing else sends. It shares the same on-disk dedup ledger (NOTIFY_SENT_DIR) as
# emit_report, so every stage is emailed exactly once regardless of who sends it.
#
# Usage: notify_chain_watch.sh <PIPE_DOMAIN> <chain_name> <chain_pid> <step_id...>
set -o pipefail
export PIPE_DOMAIN="${1:?domain}"; shift
CHAIN_NAME="${1:?chain_name}"; shift
CHAIN_PID="${1:?chain_pid}"; shift
STEPS=("$@")

export PROJECT_ROOT="/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly"
source "${PROJECT_ROOT}/annotation/steps/_lib.sh"

frag_status() { sed -n '1s/^### .* — //p' "$1" 2>/dev/null; }

DEADLINE=$(( $(date +%s) + 8*3600 ))
while :; do
  for id in "${STEPS[@]}"; do
    frag="${REPORTS_DIR}/${id}.md"
    [[ -s "$frag" ]] || continue
    st="$(frag_status "$frag")"; [[ -n "$st" ]] || st="DONE"
    notify_stage "$id" "$st" "$frag"
  done

  if ! kill -0 "$CHAIN_PID" 2>/dev/null; then
    if [[ -f "${STATE_DIR}/${CHAIN_NAME}.failed" ]]; then res="FAILED"; else res="DONE"; fi
    summary=""
    for id in "${STEPS[@]}"; do
      s="$(frag_status "${REPORTS_DIR}/${id}.md")"
      summary+="  ${id}: ${s:-MISSING}"$'\n'
    done
    notify_email "${CHAIN_NAME}_FINAL_${res}" \
      "[S.cameroni ${PIPE_DOMAIN}] chain ${CHAIN_NAME} — ${res}" \
      "Detached chain ${CHAIN_NAME} finished: ${res}  ($(now_iso))

Stage results:
${summary}
Next gate: P20 BRAKER3 (all-11 BAM + protein hints) — awaiting go."
    # give backgrounded senders a moment to flush before exit
    sleep 5
    exit 0
  fi
  [[ $(date +%s) -ge $DEADLINE ]] && exit 0
  sleep 30
done
