#!/usr/bin/env bash
# Build bgzipped + tabix-indexed track files for JBrowse 2.
# Run on bi-delllinux. Reuses existing genome_assembly conda env.
set -euo pipefail

PROJECT_DIR="/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly"
WEBAPP_DIR="${PROJECT_DIR}/webapp"
BUILD_DIR="${WEBAPP_DIR}/build/data/jbrowse"
TRACKS_DIR="${BUILD_DIR}/tracks"
GENOME_DIR="${BUILD_DIR}/genome"

ASM="${PROJECT_DIR}/final_assembly.fa"
REPEATS_GFF="${PROJECT_DIR}/annotation/repeats/final_assembly.fa.out.gff"
BUSCO_TABLE="${PROJECT_DIR}/qc/busco_results/run_hymenoptera_odb10/full_table.tsv"
BRAKER_GFF="${PROJECT_DIR}/annotation/braker/braker.gff3"   # pending Phase 7.4
COVERAGE_BAM="${PROJECT_DIR}/decontamination/mapped.bam"

mkdir -p "${GENOME_DIR}" "${TRACKS_DIR}"

conda_run() { conda run -n genome_assembly "$@"; }

log() { echo "[$(date '+%F %T')] $*"; }

log "Genome FASTA → bgzip + faidx"
if [[ ! -f "${GENOME_DIR}/final_assembly.fa.gz.gzi" ]]; then
    conda_run bgzip -k -c "${ASM}" > "${GENOME_DIR}/final_assembly.fa.gz"
    conda_run samtools faidx "${GENOME_DIR}/final_assembly.fa.gz"
fi

log "Repeats GFF → sorted + bgzip + tabix"
if [[ -f "${REPEATS_GFF}" ]]; then
    conda_run sort -k1,1 -k4,4n "${REPEATS_GFF}" | conda_run bgzip > "${TRACKS_DIR}/repeats.gff.gz"
    conda_run tabix -p gff "${TRACKS_DIR}/repeats.gff.gz"
else
    log "WARNING: repeats GFF missing — skipping"
fi

log "BUSCO table → BED"
if [[ -f "${BUSCO_TABLE}" ]]; then
    awk -F'\t' 'NR>1 && $2!="Missing" && $3!="" {
        printf "%s\t%d\t%d\tBUSCO_%s_%s\t.\t%s\n", $3, $4-1, $5, $1, $2, ($6=="+"?"+":"-")
    }' "${BUSCO_TABLE}" | sort -k1,1 -k2,2n | conda_run bgzip > "${TRACKS_DIR}/busco.bed.gz"
    conda_run tabix -p bed "${TRACKS_DIR}/busco.bed.gz"
else
    log "WARNING: BUSCO table missing — skipping"
fi

log "BRAKER3 GFF (Phase 7.4)"
if [[ -f "${BRAKER_GFF}" ]]; then
    conda_run sort -k1,1 -k4,4n "${BRAKER_GFF}" | conda_run bgzip > "${TRACKS_DIR}/braker.gff.gz"
    conda_run tabix -p gff "${TRACKS_DIR}/braker.gff.gz"
else
    log "INFO: BRAKER3 not yet run; track will be added once Phase 7.4 completes"
fi

log "Coverage BAM → sorted + indexed"
if [[ -f "${COVERAGE_BAM}" ]]; then
    if [[ ! -f "${TRACKS_DIR}/coverage.bam.bai" ]]; then
        conda_run samtools sort -@ 4 -o "${TRACKS_DIR}/coverage.bam" "${COVERAGE_BAM}"
        conda_run samtools index "${TRACKS_DIR}/coverage.bam"
    fi
else
    log "WARNING: coverage BAM missing — skipping"
fi

log "Done. Outputs in ${BUILD_DIR}"
ls -lh "${GENOME_DIR}" "${TRACKS_DIR}"
