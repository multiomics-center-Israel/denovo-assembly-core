#!/usr/bin/env bash
# Build the funannotate-era JBrowse tracks for the scaffolds assembly:
#   - gene annotation (GFF3, 16,656 genes)
#   - repeats (RepeatMasker BED)
#   - ncRNA (tRNA etc. BED)
#   - RNA-seq + TSA coverage (bigWig)
#
# Source files live in tracks/src/ (staged from the OneDrive summary/ folder).
# The canonical genome + GFF3 use refName `ptg000001l`; the BED/bigWig/chrom
# files use `ptg000001l_np1212`. We strip the uniform `_np1212` suffix so every
# track renders on the single `spalangia_cameroni` assembly.
#
# Requires: bgzip, tabix, bigWigToBedGraph, bedGraphToBigWig (conda activate kallisto_env).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"
SRC="${REPO_DIR}/tracks/src"
TRACKS="${REPO_DIR}/data/jbrowse/tracks"

log() { echo "[$(date '+%F %T')] $*"; }
mkdir -p "${TRACKS}"

# chrom.sizes with the suffix stripped — needed to rebuild the bigWigs.
CHROM="${TRACKS}/.genome.chrom.sizes"
sed 's/_np1212//' "${SRC}/genome.chrom.sizes" > "${CHROM}"

log "[1/4] gene annotation GFF3 -> spalangia_genes.gff.gz"
{
    echo '##gff-version 3'
    grep -v '^#' "${SRC}/Spalangia_cameroni.gff3" | sort -k1,1 -k4,4n
} | bgzip > "${TRACKS}/spalangia_genes.gff.gz"
tabix -p gff "${TRACKS}/spalangia_genes.gff.gz"

log "[2/4] repeats BED -> repeats.bed.gz (strip _np1212)"
zcat "${SRC}/repeats.bed.gz" | sed 's/_np1212//' | sort -k1,1 -k2,2n \
    | bgzip > "${TRACKS}/repeats.bed.gz"
tabix -p bed "${TRACKS}/repeats.bed.gz"

log "[3/4] ncRNA BED -> ncRNA.bed.gz (strip _np1212)"
zcat "${SRC}/ncRNA.sorted.bed.gz" | sed 's/_np1212//' | sort -k1,1 -k2,2n -u \
    | bgzip > "${TRACKS}/ncRNA.bed.gz"
tabix -p bed "${TRACKS}/ncRNA.bed.gz"

log "[4/4] coverage bigWigs (rename chroms via bedGraph round-trip)"
for bw in rnaseq_coverage rnaseq_coverage.rp10m tsa_coverage; do
    [[ -f "${SRC}/${bw}.bw" ]] || { log "  skip ${bw}.bw (missing)"; continue; }
    log "  ${bw}.bw"
    bigWigToBedGraph "${SRC}/${bw}.bw" /dev/stdout \
        | sed 's/_np1212//' \
        | sort -k1,1 -k2,2n > "${TRACKS}/.${bw}.bg"
    bedGraphToBigWig "${TRACKS}/.${bw}.bg" "${CHROM}" "${TRACKS}/${bw}.bw"
    rm -f "${TRACKS}/.${bw}.bg"
done

log "Done."
ls -lh "${TRACKS}"
