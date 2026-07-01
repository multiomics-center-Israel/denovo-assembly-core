#!/usr/bin/env bash
# Run BLAST locally against the local DBs, then upload hits to the cloud agent.
#
# Usage:
#   AGENT_URL=https://your-agent.up.railway.app SITE_PASSWORD=... \
#     bash run_blast.sh query.fa blastn
#
# Args: <query.fasta> <program: blastn|tblastn|blastp|blastx> [extra blast args...]
# Env:
#   BLAST_DB_DIR   dir with spalangia_genome / spalangia_proteins (default ../build/blast/db)
#   EVALUE         default 1e-5
set -euo pipefail

QUERY="${1:?query fasta}"; PROGRAM="${2:?program}"; shift 2 || true
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_DIR="${BLAST_DB_DIR:-$HERE/../build/blast/db}"
EVALUE="${EVALUE:-1e-5}"

case "$PROGRAM" in
  blastn|tblastn) DB="$DB_DIR/spalangia_genome" ;;
  blastp|blastx)  DB="$DB_DIR/spalangia_proteins" ;;
  *) echo "unknown program $PROGRAM"; exit 1 ;;
esac

TMP="$(mktemp)"
echo "[*] $PROGRAM vs $DB (evalue $EVALUE)" >&2
"$PROGRAM" -query "$QUERY" -db "$DB" -evalue "$EVALUE" -outfmt 6 "$@" > "$TMP"
echo "[*] $(wc -l < "$TMP") hits -> uploading to $AGENT_URL" >&2
python3 "$HERE/post_results.py" "$TMP" --program "$PROGRAM"
rm -f "$TMP"
