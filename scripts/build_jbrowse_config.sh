#!/usr/bin/env bash
# Build a static JBrowse 2 site + config.json with all available tracks.
# Requires: npx (Node.js). Run on lab host or laptop — site is the same.
set -euo pipefail

PROJECT_DIR="/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly"
WEBAPP_DIR="${PROJECT_DIR}/webapp"
BUILD_DIR="${WEBAPP_DIR}/build/data/jbrowse"
TRACKS_DIR="${BUILD_DIR}/tracks"
GENOME_DIR="${BUILD_DIR}/genome"

cd "${BUILD_DIR}"

if [[ ! -d "static" ]]; then
    npx --yes @jbrowse/cli@latest create static
fi

cd static

npx --yes @jbrowse/cli@latest add-assembly \
    "${GENOME_DIR}/final_assembly.fa.gz" \
    --name spalangia_cameroni --load inPlace --force

[[ -f "${TRACKS_DIR}/repeats.gff.gz" ]] && \
    npx --yes @jbrowse/cli@latest add-track "${TRACKS_DIR}/repeats.gff.gz" \
        --name "Repeats (RepeatMasker)" --category "Annotation" \
        --assemblyNames spalangia_cameroni --load inPlace --force

[[ -f "${TRACKS_DIR}/busco.bed.gz" ]] && \
    npx --yes @jbrowse/cli@latest add-track "${TRACKS_DIR}/busco.bed.gz" \
        --name "BUSCO (hymenoptera_odb10)" --category "QC" \
        --assemblyNames spalangia_cameroni --load inPlace --force

[[ -f "${TRACKS_DIR}/braker.gff.gz" ]] && \
    npx --yes @jbrowse/cli@latest add-track "${TRACKS_DIR}/braker.gff.gz" \
        --name "Genes (BRAKER3)" --category "Annotation" \
        --assemblyNames spalangia_cameroni --load inPlace --force

[[ -f "${TRACKS_DIR}/coverage.bam" ]] && \
    npx --yes @jbrowse/cli@latest add-track "${TRACKS_DIR}/coverage.bam" \
        --name "HiFi coverage" --category "Reads" \
        --assemblyNames spalangia_cameroni --load inPlace --force

echo "JBrowse static site built at ${BUILD_DIR}/static"
