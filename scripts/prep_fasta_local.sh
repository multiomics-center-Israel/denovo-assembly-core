#!/usr/bin/env bash
# FASTA-only local build: bgzip+faidx the assembly, build a nucleotide BLAST
# DB, and stand up a JBrowse 2 static site. Pre-Phase-7.4 demo path — no
# GFF tracks, no protein DB.
# Requires PATH to provide samtools, bgzip, makeblastdb, npx (e.g. via
# `conda activate kallisto_env`).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"

ASM="${REPO_DIR}/assembly/final_assembly.fa"
JBROWSE_DIR="${REPO_DIR}/data/jbrowse"
GENOME_DIR="${JBROWSE_DIR}/genome"
BLAST_DIR="${REPO_DIR}/data/blast/db"

log() { echo "[$(date '+%F %T')] $*"; }

[[ -f "${ASM}" ]] || { echo "ERROR: assembly not found at ${ASM}" >&2; exit 1; }

mkdir -p "${GENOME_DIR}" "${BLAST_DIR}"

log "FASTA → bgzip + faidx → ${GENOME_DIR}"
if [[ ! -f "${GENOME_DIR}/final_assembly.fa.gz.gzi" ]]; then
    bgzip -k -c "${ASM}" > "${GENOME_DIR}/final_assembly.fa.gz"
    samtools faidx "${GENOME_DIR}/final_assembly.fa.gz"
fi

log "BLAST nucleotide DB → ${BLAST_DIR}/spalangia_genome"
if [[ ! -f "${BLAST_DIR}/spalangia_genome.nsq" ]]; then
    makeblastdb -in "${ASM}" -dbtype nucl \
        -title "Spalangia cameroni genome" \
        -out "${BLAST_DIR}/spalangia_genome" \
        -parse_seqids
fi

log "JBrowse 2 static site → ${JBROWSE_DIR}"
if [[ ! -f "${JBROWSE_DIR}/index.html" ]]; then
    npx --yes @jbrowse/cli@latest create "${JBROWSE_DIR}" --force
fi

# --load symlink writes a relative URI under the static root so the browser
# can fetch the genome over nginx. --load inPlace would store the host
# absolute path, which fails when nginx is the only thing serving files.
( cd "${JBROWSE_DIR}" && npx --yes @jbrowse/cli@latest add-assembly \
    "${GENOME_DIR}/final_assembly.fa.gz" \
    --name spalangia_cameroni --load symlink --force )

# jbrowse-cli writes the symlinks with absolute host targets, which break
# inside the nginx container that only sees /usr/share/nginx/html. Replace
# them with paths relative to JBROWSE_DIR so they resolve in either context.
( cd "${JBROWSE_DIR}" && \
    ln -sfn genome/final_assembly.fa.gz final_assembly.fa.gz && \
    ln -sfn genome/final_assembly.fa.gz.fai final_assembly.fa.gz.fai && \
    ln -sfn genome/final_assembly.fa.gz.gzi final_assembly.fa.gz.gzi )

log "Done."
ls -lh "${GENOME_DIR}" "${BLAST_DIR}"
