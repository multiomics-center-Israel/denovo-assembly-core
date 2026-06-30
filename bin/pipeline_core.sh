#!/usr/bin/env bash
# pipeline_core.sh — shared CLI engine for both pipeline runners.
# A runner sets PIPE_DOMAIN (+ optionally defines next_hint()), sources _lib.sh, then
# sources this file passing "$@". One engine -> assembly and annotation behave identically.
# Catalogue (DOMAIN/steps/catalogue.tsv) is the single source of truth.

CAT="${STEPS_DIR}/catalogue.tsv"

step_ids()  { awk -F'\t' '!/^#/ && NF>=7 {print $1}' "$CAT"; }

# resolve_id <token> : map a shorthand (e.g. E11) to the full unique step id
# (E11_rna_repair_venom). Exact match wins; else unique prefix match; else error.
resolve_id() {
  local tok="$1" m matches=()
  for m in $(step_ids); do [[ "$m" == "$tok" ]] && { echo "$m"; return 0; }; done
  for m in $(step_ids); do [[ "$m" == "$tok"* ]] && matches+=("$m"); done
  if [[ ${#matches[@]} -eq 1 ]]; then echo "${matches[0]}"; return 0; fi
  if [[ ${#matches[@]} -eq 0 ]]; then echo "ERR: no step matches '$tok'" >&2; return 1; fi
  echo "ERR: '$tok' is ambiguous: ${matches[*]}" >&2; return 1
}
field()     { awk -F'\t' -v id="$1" -v c="$2" '$1==id{print $c}' "$CAT"; }
wrapper_of(){ echo "${STEPS_DIR}/$1.sh"; }

color() { case "$1" in DONE) printf '\033[32m';; RUNNING) printf '\033[33m';; FAILED) printf '\033[31m';; *) printf '\033[90m';; esac; }
reset() { printf '\033[0m'; }

print_status() {
  printf '%-26s %-7s %-9s %s\n' "STEP" "MODE" "STATUS" "LABEL"
  printf '%-26s %-7s %-9s %s\n' "----" "----" "------" "-----"
  local id mode label st w
  for id in $(step_ids); do
    w="$(wrapper_of "$id")"; mode="$(field "$id" 3)"; label="$(field "$id" 7)"
    if [[ -f "$w" ]]; then st="$(step_status "$w" "$id")"; else st="NOWRAP"; fi
    printf '%b%-26s%b %-7s %b%-9s%b %s\n' "$(color "$st")" "$id" "$(reset)" "$mode" "$(color "$st")" "$st" "$(reset)" "$label"
  done
  # active detached chains / single LONG steps
  local pf pid
  for pf in "${STATE_DIR}"/chain_*.pid "${STATE_DIR}"/*.pid; do
    [[ -f "$pf" ]] || continue
    pid="$(cat "$pf" 2>/dev/null)"
    if kill -0 "$pid" 2>/dev/null; then
      printf '\033[33m  RUNNING (detached): %s  pid=%s\033[0m\n' "$(basename "$pf" .pid)" "$pid"
    fi
  done
}

next_pending() {
  local id w st
  for id in $(step_ids); do
    w="$(wrapper_of "$id")"; [[ -f "$w" ]] || continue
    st="$(step_status "$w" "$id")"
    [[ "$st" == "PENDING" || "$st" == "FAILED" ]] && { echo "$id"; return; }
  done
}

print_next() {
  local n; n="$(next_pending || true)"
  echo ""
  if [[ -z "$n" ]]; then echo ">>> NEXT: (none) — all steps DONE or RUNNING"; return; fi
  if declare -F next_hint >/dev/null; then next_hint; fi
  echo "    first PENDING in order: ${n}  ($(field "$n" 7))"
}

run_one() {
  local id="$1" w mode
  w="$(wrapper_of "$id")"
  [[ -f "$w" ]] || { echo "!! no wrapper for ${id} (${w})"; return 0; }
  mode="$(field "$id" 3)"
  if [[ "${FORCE:-0}" != "1" ]] && [[ "$(step_status "$w" "$id")" == "DONE" ]]; then
    echo ".. ${id} already DONE (FORCE=1 to re-run)"; return 0
  fi
  if [[ "$mode" == "LONG" ]]; then
    launch_long "$id" "$w"
  else
    local log="${LOGDIR}/${id}_$(ts).log"
    echo ">> ${id} (SHORT, inline) -> ${log}"
    STEP_LOG="$log" FORCE="${FORCE:-0}" bash "$w" 2>&1 | tee -a "$log"
    return "${PIPESTATUS[0]}"
  fi
}

run_range() {  # FROM [TO]
  # Build the ordered list of steps in [FROM..TO] that still need running.
  local from="$1" to="${2:-}" started=0 id w st
  local ids=() wraps=()
  for id in $(step_ids); do
    [[ "$id" == "$from" ]] && started=1
    if [[ "$started" == 1 ]]; then
      w="$(wrapper_of "$id")"
      if [[ -f "$w" ]]; then
        st="$(step_status "$w" "$id")"
        if [[ "${FORCE:-0}" == "1" || "$st" != "DONE" ]]; then ids+=("$id"); wraps+=("$w"); fi
      fi
    fi
    [[ -n "$to" && "$id" == "$to" ]] && break
  done
  if [[ ${#ids[@]} -eq 0 ]]; then echo "nothing to run in range (all DONE; FORCE=1 to redo)"; return 0; fi
  if [[ ${#ids[@]} -eq 1 ]]; then run_one "${ids[0]}"; return; fi
  # multi-step range -> ONE detached sequential chain (respects deps, survives detach)
  echo "running ${#ids[@]} steps as a detached chain: ${ids[*]}"
  launch_chain "${ids[0]}" "${wraps[@]}"
}

pipeline_cli() {
  local cmd="${1:-resume}"
  case "$cmd" in
    status)  print_status; print_next ;;
    --step)  local SID; SID="$(resolve_id "${2:?--step needs an ID}")" || return 2; run_one "$SID" ;;
    --from)  shift; local FROM TO=""
             FROM="$(resolve_id "${1:?--from needs an ID}")" || return 2; shift || true
             [[ "${1:-}" == "--to" ]] && { TO="$(resolve_id "${2:-}")" || return 2; }
             run_range "$FROM" "$TO" ;;
    --all)   run_range "$(step_ids | head -1)" "" ;;
    resume|"") local n; n="$(next_pending || true)"
             [[ -z "$n" ]] && { echo "all done/running"; print_next; return 0; }
             echo "resuming from ${n}"; run_range "$n" "" ;;
    *) echo "unknown: $cmd"; echo "usage: $0 [status|--step ID|--from ID [--to ID]|--all|resume]"; return 2 ;;
  esac
}
