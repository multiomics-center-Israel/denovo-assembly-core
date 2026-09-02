#!/usr/bin/env bash
# Build the strict-ortholog subset of the Nvit tblastn track. Same input
# tblastn result as prep_tblastn_track.sh, stricter per-HSP thresholds, and
# a separate JBrowse track file. Pass the tblastn tabular file as $1 to
# override the default lookup.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export MIN_QCOVS=80
export MIN_PIDENT=50
export MAX_EVALUE=1e-20
export MIN_LENGTH_AA=100
export OUT="$(dirname "${SCRIPT_DIR}")/data/jbrowse/tracks/nvit_orthologs.gff.gz"

exec bash "${SCRIPT_DIR}/prep_tblastn_track.sh" "$@"
