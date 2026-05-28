#!/usr/bin/env bash
# Package the prepared data tree into a single zstd tarball for laptop transport.
set -euo pipefail

WEBAPP_DIR="/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly/webapp"
BUILD_DIR="${WEBAPP_DIR}/build"
BUNDLE="${BUILD_DIR}/webapp_data.tar.zst"

cd "${BUILD_DIR}"

if [[ ! -d data ]]; then
    echo "ERROR: ${BUILD_DIR}/data not found — run prep_tracks.sh / build_blast_dbs.sh / build_rag_index.py first"
    exit 1
fi

echo "Packaging ${BUILD_DIR}/data → ${BUNDLE}"
tar --zstd -cf "${BUNDLE}" data/
du -h "${BUNDLE}"
echo "Done. Transport with:"
echo "  rsync -avz bi-delllinux:${BUNDLE} ."
