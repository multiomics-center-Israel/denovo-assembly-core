#!/usr/bin/env bash
# Upload genome + track + agent-data files to Supabase Storage (public bucket).
#
# Files <= 50 MB use a plain POST; larger files use the TUS resumable protocol
# (chunked), because the plain upload is unreliable past the old free-tier cap.
# The bucket is (re)created and its file-size limit raised so big files fit —
# this requires a Pro project (free tier hard-caps at 50 MB per file).
#
# Required env:
#   SUPABASE_URL          e.g. https://abcd1234.supabase.co
#   SUPABASE_SERVICE_KEY  service_role key (Storage write)
# Optional:
#   SUPABASE_BUCKET       default 'genome'
#   BUILD                 default ../build relative to this script
#   BUCKET_LIMIT_BYTES    default 524288000 (500 MB) — raise if files grow
#
# Prints TRACK_BASE / DATA_BASE public URLs for build_jbrowse_config_web.py.
set -euo pipefail

: "${SUPABASE_URL:?set SUPABASE_URL}"
: "${SUPABASE_SERVICE_KEY:?set SUPABASE_SERVICE_KEY}"
BUCKET="${SUPABASE_BUCKET:-genome}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="${BUILD:-$HERE/../build}"
API="${SUPABASE_URL%/}/storage/v1"
LIMIT="${BUCKET_LIMIT_BYTES:-524288000}"           # 500 MB
PLAIN_MAX=$((50 * 1024 * 1024))                    # <=50 MB -> plain POST
TUS_CHUNK=$((6 * 1024 * 1024))                     # 6 MiB TUS chunk

auth=(-H "Authorization: Bearer $SUPABASE_SERVICE_KEY" -H "apikey: $SUPABASE_SERVICE_KEY")
b64() { printf '%s' "$1" | base64 -w0; }

ctype() {
  case "$1" in
    *.gz)              echo "application/gzip" ;;
    *.jsonl|*.json)    echo "application/json" ;;
    *.fai|*.gzi|*.tbi|*.bw|*.sqlite) echo "application/octet-stream" ;;
    *)                 echo "application/octet-stream" ;;
  esac
}

echo "[*] ensure public bucket '$BUCKET' with file-size limit $LIMIT bytes"
# Create (ignored if it already exists) then update to force the raised limit.
curl -s -o /dev/null "${auth[@]}" -H "Content-Type: application/json" \
  -X POST "$API/bucket" \
  -d "{\"name\":\"$BUCKET\",\"id\":\"$BUCKET\",\"public\":true,\"file_size_limit\":$LIMIT}" || true
code=$(curl -s -o /dev/null -w '%{http_code}' "${auth[@]}" -H "Content-Type: application/json" \
  -X PUT "$API/bucket/$BUCKET" \
  -d "{\"public\":true,\"file_size_limit\":$LIMIT}")
echo "    bucket update http $code"

upload_plain() {
  local f="$1" key="$2" code
  code=$(curl -s -o /dev/null -w '%{http_code}' "${auth[@]}" \
    -H "x-upsert: true" -H "Content-Type: $(ctype "$f")" \
    -X POST "$API/object/$BUCKET/$key" --data-binary "@$f")
  echo "       plain http $code"
  [[ "$code" =~ ^2 ]] || { echo "       ! upload failed ($key)"; return 1; }
}

upload_resumable() {
  local f="$1" key="$2" size loc off idx tmp clen code
  size=$(stat -c%s "$f")
  local md="bucketName $(b64 "$BUCKET"),objectName $(b64 "$key"),contentType $(b64 "$(ctype "$f")"),cacheControl $(b64 3600)"
  loc=$(curl -s -D - -o /dev/null "${auth[@]}" \
    -H "Tus-Resumable: 1.0.0" -H "Upload-Length: $size" \
    -H "Upload-Metadata: $md" -H "x-upsert: true" \
    -X POST "$API/upload/resumable" | tr -d '\r' | awk 'tolower($1)=="location:"{print $2}')
  if [ -z "$loc" ]; then echo "       ! resumable create failed ($key)"; return 1; fi
  off=0; idx=0
  while [ "$off" -lt "$size" ]; do
    tmp=$(mktemp)
    dd if="$f" of="$tmp" bs="$TUS_CHUNK" skip="$idx" count=1 status=none
    clen=$(stat -c%s "$tmp")
    code=$(curl -s -o /dev/null -w '%{http_code}' "${auth[@]}" \
      -H "Tus-Resumable: 1.0.0" -H "Upload-Offset: $off" \
      -H "Content-Type: application/offset+octet-stream" \
      -X PATCH "$loc" --data-binary "@$tmp")
    rm -f "$tmp"
    if [ "$code" != "204" ]; then echo "       ! chunk $idx http $code ($key)"; return 1; fi
    off=$((off + clen)); idx=$((idx + 1))
    printf '\r       resumable %d%% (%d/%d bytes)' $((off * 100 / size)) "$off" "$size"
  done
  echo "  ok"
}

upload() {
  local f="$1" key="$2" size
  size=$(stat -c%s "$f")
  printf '    -> %s (%s)\n' "$key" "$(du -h "$f" | cut -f1)"
  if [ "$size" -le "$PLAIN_MAX" ]; then upload_plain "$f" "$key"; else upload_resumable "$f" "$key"; fi
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
