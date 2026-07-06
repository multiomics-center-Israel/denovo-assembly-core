#!/usr/bin/env bash
# Run BLAST *inside the agent* (server-side) — no local blast+ needed.
# POSTs a query FASTA to the agent's /blast endpoint; the agent runs
# blastn/tblastn/blastp/blastx against its bundled DBs and stores the hits as
# the JBrowse `blast_hits` track. Deterministic; the LLM is not involved.
#
# Usage:
#   AGENT_URL=http://localhost:8001 [SITE_PASSWORD=...] \
#     bash blast_search.sh <query.fasta> <blastn|tblastn|blastp|blastx> [evalue]
set -euo pipefail

QUERY="${1:?query fasta}"; PROGRAM="${2:?program}"; EVALUE="${3:-}"
: "${AGENT_URL:?set AGENT_URL}"
[ -f "$QUERY" ] || { echo "no such file: $QUERY" >&2; exit 1; }

# Build the request and POST it with the stdlib (no jq/curl deps).
QUERY="$QUERY" PROGRAM="$PROGRAM" EVALUE="$EVALUE" \
AGENT_URL="$AGENT_URL" SITE_USER="${SITE_USER:-spalangia}" \
SITE_PASSWORD="${SITE_PASSWORD:-}" python3 - <<'PY'
import base64, json, os, sys, urllib.request

payload = {"query": open(os.environ["QUERY"]).read(), "program": os.environ["PROGRAM"]}
if os.environ.get("EVALUE"):
    payload["evalue"] = float(os.environ["EVALUE"])

req = urllib.request.Request(
    os.environ["AGENT_URL"].rstrip("/") + "/blast",
    data=json.dumps(payload).encode(), headers={"Content-Type": "application/json"})
if os.environ.get("SITE_PASSWORD"):
    tok = base64.b64encode(
        f"{os.environ['SITE_USER']}:{os.environ['SITE_PASSWORD']}".encode()).decode()
    req.add_header("Authorization", "Basic " + tok)

try:
    with urllib.request.urlopen(req, timeout=300) as r:
        print(json.dumps(json.load(r), indent=2))
except urllib.error.HTTPError as e:
    sys.exit(f"HTTP {e.code}: {e.read().decode()[:500]}")
PY
