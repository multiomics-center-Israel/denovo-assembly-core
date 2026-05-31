#!/usr/bin/env bash
# Build the Nvit-protein tblastn homology track for JBrowse 2.
# Converts a tblastn outfmt-7 tabular result into a sorted, bgzipped,
# tabix-indexed GFF3 referenced by data/jbrowse/config.json (track
# "nvit_tblastn", relative URI tracks/nvit_tblastn.gff.gz).
# Requires PATH to provide bgzip, tabix (e.g. `conda activate kallisto_env`).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"

# tblastn tabular result; override as the first argument.
TBLASTN_TAB="${1:-${REPO_DIR}/tracks/Nvit_vs_Spalngia_cameroni_assmbely.tblastn_res.txt.Protein_vs_genome.tbalstn_res.txt}"
TRACKS_DIR="${REPO_DIR}/data/jbrowse/tracks"
OUT="${TRACKS_DIR}/nvit_tblastn.gff.gz"

log() { echo "[$(date '+%F %T')] $*"; }

[[ -f "${TBLASTN_TAB}" ]] || { echo "ERROR: tblastn result not found at ${TBLASTN_TAB}" >&2; exit 1; }

mkdir -p "${TRACKS_DIR}"

log "tblastn → GFF3 → sort + bgzip + tabix → ${OUT}"
# Emit the gff-version pragma first; sort only the feature lines by position
# (coordinate sort is required for tabix).
{
    echo '##gff-version 3'
    python3 "${SCRIPT_DIR}/tblastn_to_gff3.py" "${TBLASTN_TAB}" | grep -v '^#' | sort -k1,1 -k4,4n
} | bgzip > "${OUT}"
tabix -p gff "${OUT}"

log "Done. $(zcat "${OUT}" | grep -vc '^#') features."
ls -lh "${OUT}" "${OUT}.tbi"
