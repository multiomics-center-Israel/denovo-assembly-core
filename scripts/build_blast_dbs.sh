#!/usr/bin/env bash
# Build BLAST databases for SequenceServer.
set -euo pipefail

PROJECT_DIR="/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly"
WEBAPP_DIR="${PROJECT_DIR}/webapp"
DB_DIR="${WEBAPP_DIR}/build/data/blast/db"

ASM="${PROJECT_DIR}/final_assembly.fa"
BRAKER_AA="${PROJECT_DIR}/annotation/braker/braker.aa"

mkdir -p "${DB_DIR}"

conda_run() { conda run -n genome_assembly "$@"; }

log() { echo "[$(date '+%F %T')] $*"; }

log "Genome nucleotide DB"
conda_run makeblastdb -in "${ASM}" -dbtype nucl \
    -title "Spalangia cameroni genome" \
    -out "${DB_DIR}/spalangia_genome" \
    -parse_seqids

if [[ -f "${BRAKER_AA}" ]]; then
    log "BRAKER3 protein DB"
    conda_run makeblastdb -in "${BRAKER_AA}" -dbtype prot \
        -title "Spalangia cameroni BRAKER3 proteins" \
        -out "${DB_DIR}/spalangia_proteins" \
        -parse_seqids
else
    log "INFO: BRAKER3 protein FASTA missing; will be added after Phase 7.4"
fi

ls -lh "${DB_DIR}"
