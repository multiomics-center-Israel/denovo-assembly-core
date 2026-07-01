#!/usr/bin/env bash
# Upload genome + track files to Supabase Storage (public bucket) for JBrowse.
#
# Required env:
#   SUPABASE_URL          e.g. https://abcd1234.supabase.co
#   SUPABASE_SERVICE_KEY  service_role key (Storage write)
# Optional:
#   SUPABASE_BUCKET       default 'genome'
#   BUILD                 default ../build relative to this script
#
# Prints the TRACK_BASE public URL to feed into build_jbrowse_config_web.py.
set -euo pipefail

: "${SUPABASE_URL:?set SUPABASE_URL}"
: "${SUPABASE_SERVICE_KEY:?set SUPABASE_SERVICE_KEY}"
BUCKET="${SUPABASE_BUCKET:-genome}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="${BUILD:-$HERE/../build}"
API="${SUPABASE_URL%/}/storage/v1"

auth=(-H "Authorization: Bearer $SUPABASE_SERVICE_KEY" -H "apikey: $SUPABASE_SERVICE_KEY")

echo "[*] ensure public bucket '$BUCKET'"
curl -s "${auth[@]}" -H "Content-Type: application/json" \
  -X POST "$API/bucket" \
  -d "{\"name\":\"$BUCKET\",\"id\":\"$BUCKET\",\"public\":true}" >/dev/null || true

ctype() {
  case "$1" in
    *.gz)  echo "application/gzip" ;;
    *.fai|*.gzi|*.tbi) echo "application/octet-stream" ;;
    *.bw)  echo "application/octet-stream" ;;
    *)     echo "application/octet-stream" ;;
  esac
}

upload() {
  local f="$1" key="$2"
  echo "    -> $key ($(du -h "$f" | cut -f1))"
  curl -s -o /dev/null -w "       http %{http_code}\n" "${auth[@]}" \
    -H "x-upsert: true" -H "Content-Type: $(ctype "$f")" \
    -X POST "$API/object/$BUCKET/$key" --data-binary "@$f"
}

echo "[*] genome"
for f in "$BUILD"/genome/*; do upload "$f" "$(basename "$f")"; done
echo "[*] tracks"
for f in "$BUILD"/tracks/*; do upload "$f" "$(basename "$f")"; done
echo "[*] agent data (gff/functional/rag) under agent/ prefix"
upload "$BUILD/agent/gff.sqlite"        "agent/gff.sqlite"
upload "$BUILD/agent/functional.sqlite" "agent/functional.sqlite"
upload "$BUILD/agent/rag/chunks.jsonl"  "agent/chunks.jsonl"

PUBLIC_BASE="${SUPABASE_URL%/}/storage/v1/object/public/$BUCKET"
echo
echo "# Feed these to the config builder and the agent service:"
echo "TRACK_BASE=$PUBLIC_BASE"
echo "DATA_BASE=$PUBLIC_BASE"
