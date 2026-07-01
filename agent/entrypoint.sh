#!/usr/bin/env sh
# Fetch agent data into /data on first boot (cached on a Railway volume), then serve.
# Set DATA_BASE to the public Supabase bucket base (same as TRACK_BASE). If unset,
# assumes /data is already populated (e.g. local bind mount) and skips downloads.
set -e

DATA_DIR="${DATA_DIR:-/data}"
# Tolerate a read-only /data (files pre-populated); blast_results dir is created
# by the app under BLAST_RESULTS_DIR regardless.
mkdir -p "$DATA_DIR/rag" "$DATA_DIR/genome" 2>/dev/null || true
mkdir -p "${BLAST_RESULTS_DIR:-$DATA_DIR/blast_results}" 2>/dev/null || true

fetch() {  # url dest
  if [ ! -s "$2" ]; then
    echo "[entrypoint] fetch $(basename "$2")"
    curl -fsSL "$1" -o "$2" || echo "[entrypoint] WARN: failed $1"
  fi
}

if [ -n "$DATA_BASE" ]; then
  B="${DATA_BASE%/}"
  fetch "$B/agent/gff.sqlite"          "$DATA_DIR/gff.sqlite"
  fetch "$B/agent/functional.sqlite"   "$DATA_DIR/functional.sqlite"
  fetch "$B/agent/chunks.jsonl"        "$DATA_DIR/rag/chunks.jsonl"
  # Assembly FASTA is optional (only contig_stats GC needs it); comment out to save boot time.
  if [ "${FETCH_ASSEMBLY:-1}" = "1" ]; then
    fetch "$B/final_assembly.fa.gz"     "$DATA_DIR/genome/final_assembly.fa.gz"
    fetch "$B/final_assembly.fa.gz.fai" "$DATA_DIR/genome/final_assembly.fa.gz.fai"
    fetch "$B/final_assembly.fa.gz.gzi" "$DATA_DIR/genome/final_assembly.fa.gz.gzi"
  fi
else
  echo "[entrypoint] DATA_BASE unset; assuming /data is pre-populated"
fi

exec uvicorn main:app --host 0.0.0.0 --port "${PORT:-8000}"
