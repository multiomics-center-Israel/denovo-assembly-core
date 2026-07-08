#!/usr/bin/env bash
# Smoke test for the Spalangia web stack. Exits non-zero on the first failure so
# CI / the deploy pipeline can gate on it.
#
#   AGENT_URL     default http://localhost:8001
#   JBROWSE_URL   default http://localhost:8090   (skipped if empty)
#   FULL          set to 1 to also exercise the data-backed endpoints
#                 (needs gff/functional/rag present — true in prod & local,
#                  not in dataless cloud CI)
#   AUTH          optional "user:password" for basic-auth (prod)
set -uo pipefail

AGENT_URL="${AGENT_URL:-http://localhost:8001}"
# Use `-` (not `:-`) so an explicitly-empty JBROWSE_URL="" disables the jbrowse
# checks (e.g. in cloud CI where only the agent runs); unset still gets the default.
JBROWSE_URL="${JBROWSE_URL-http://localhost:8090}"
CURL=(curl -fsS --max-time 30)
[ -n "${AUTH:-}" ] && CURL+=(-u "$AUTH")
fails=0

check() {  # name, command...
  local name="$1"; shift
  if "$@"; then echo "  ok   $name"; else echo "  FAIL $name"; fails=$((fails + 1)); fi
}

json_true() {  # url, python-expr on `d`
  local url="$1" expr="$2" body
  body=$("${CURL[@]}" "$url" 2>/dev/null) || return 1
  printf '%s' "$body" | python3 -c "import sys,json;d=json.load(sys.stdin);sys.exit(0 if ($expr) else 1)" 2>/dev/null
}

echo "== agent $AGENT_URL =="
check "/health ok"           json_true "$AGENT_URL/health" "d.get('ok') is True"

if [ "${FULL:-0}" = "1" ]; then
  check "/health dbs present" json_true "$AGENT_URL/health" "d['gff_db_present'] and d['functional_db_present'] and d['rag_index_present']"
  check "/goto gene resolves" json_true "$AGENT_URL/goto?q=evm.model.ptg000776l_np1212.1" "d.get('found') is True and 'view' in d"
  check "/goto coords"        json_true "$AGENT_URL/goto?q=ptg000004l:1-200000" "d.get('found') is True"
  check "/genes/search sql"   json_true "$AGENT_URL/genes/search?limit=3&q=kinase" "d.get('count',0) >= 1"
  check "/docs/search bm25"   json_true "$AGENT_URL/docs/search?q=BUSCO&k=2" "len(d.get('hits',[])) >= 1"
fi

if [ -n "$JBROWSE_URL" ]; then
  echo "== jbrowse $JBROWSE_URL =="
  check "page 200"            bash -c "${CURL[*]} -o /dev/null '$JBROWSE_URL/' >/dev/null"
  check "widget served"       bash -c "${CURL[*]} '$JBROWSE_URL/chat/widget.js' | grep -q spa-genes-btn"
fi

echo
if [ "$fails" -gt 0 ]; then echo "SMOKE FAILED ($fails)"; exit 1; fi
echo "SMOKE PASSED"
