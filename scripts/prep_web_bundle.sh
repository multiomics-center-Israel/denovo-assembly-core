#!/usr/bin/env bash
# Prep the _np1212 web-deploy data bundle from the 2026-06-29 website_transfer.
#
# Produces, under $BUILD:
#   genome/final_assembly.fa.gz (+ .fai .gzi)     -> Supabase Storage (JBrowse refseq)
#   tracks/*.{gff,bed}.gz (+ .tbi), *.bw          -> Supabase Storage (JBrowse tracks)
#   blast/db/spalangia_{genome,proteins}.*        -> LOCAL only (local BLAST)
#   agent/gff.sqlite                              -> agent image
#   agent/rag/chunks.jsonl                        -> agent image
#
# All coordinates are canonical _np1212 (bundle is already consistent; no strip).
# Run inside: conda activate kallisto_env
set -euo pipefail

BUNDLE="${BUNDLE:-/mnt/c/Users/ozsol/Technion/MultiOmicsCenter - Documents/Projects/Elad_Chill/Results/Wasp_genome_assembly/summary/website_transfer}"
WT="${WT:-/home/ozsol/spalangia-web-deploy}"
BUILD="${BUILD:-$WT/build}"
SRC="${SRC:-/home/ozsol/denovo-assembly-core/tracks/src}"   # _np1212-native coverage/repeats/ncRNA
THREADS="${THREADS:-8}"

log() { echo "[$(date '+%F %T')] $*"; }

mkdir -p "$BUILD/genome" "$BUILD/tracks" "$BUILD/blast/db" "$BUILD/agent/rag"

# ---- 1. Genome (bgzip + faidx + gzi) ----
G="$BUILD/genome/final_assembly.fa.gz"
if [[ ! -s "$G" ]]; then
  log "bgzip genome -> $G"
  bgzip -c -@ "$THREADS" "$BUNDLE/genome/final_assembly.fa" > "$G"
  log "faidx genome"
  samtools faidx "$G"   # writes .fai + .gzi
else
  log "genome already built, skip"
fi

# ---- 2. Annotation tracks already bgzipped+tabixed in bundle (native _np1212) ----
log "copy genes + stringtie (pre-indexed in bundle)"
cp -f "$BUNDLE/annotation/genes.gff3.gz"      "$BUILD/tracks/genes.gff3.gz"
cp -f "$BUNDLE/annotation/genes.gff3.gz.tbi"  "$BUILD/tracks/genes.gff3.gz.tbi"
cp -f "$BUNDLE/annotation/stringtie_merged.gtf.gz"     "$BUILD/tracks/stringtie_merged.gtf.gz"
cp -f "$BUNDLE/annotation/stringtie_merged.gtf.gz.tbi" "$BUILD/tracks/stringtie_merged.gtf.gz.tbi"

# ---- 3. Repeats / ncRNA (native _np1212 BEDs from tracks/src) ----
if [[ -d "$SRC" ]]; then
  for f in repeats.bed.gz ncRNA.sorted.bed.gz; do
    if [[ -s "$SRC/$f" ]]; then
      log "stage $f"
      cp -f "$SRC/$f" "$BUILD/tracks/$f"
      tabix -f -p bed "$BUILD/tracks/$f"
    fi
  done
  # ---- 4. Coverage bigWigs (verify chrom naming below) ----
  for bw in rnaseq_coverage.bw rnaseq_coverage.rp10m.bw tsa_coverage.bw; do
    [[ -s "$SRC/$bw" ]] && { log "stage $bw"; cp -f "$SRC/$bw" "$BUILD/tracks/$bw"; }
  done
else
  log "WARN: $SRC missing; skipping coverage/repeats/ncRNA"
fi

# ---- 5. BLAST DBs (LOCAL ONLY) ----
# makeblastdb -in treats spaces as a file list; symlink to a space-free path.
ln -sf "$BUNDLE/genome/final_assembly.fa" "$BUILD/_genome_src.fa"
ln -sf "$BUNDLE/annotation/proteome.fa"   "$BUILD/_proteome_src.fa"
log "makeblastdb genome (nucl)"
makeblastdb -in "$BUILD/_genome_src.fa" -dbtype nucl \
  -title "Spalangia cameroni genome" -out "$BUILD/blast/db/spalangia_genome" -parse_seqids
log "makeblastdb proteome (prot)"   # no -parse_seqids: funannotate ids exceed 50-char local-id limit
makeblastdb -in "$BUILD/_proteome_src.fa" -dbtype prot \
  -title "Spalangia cameroni proteins" -out "$BUILD/blast/db/spalangia_proteins"
rm -f "$BUILD/_genome_src.fa" "$BUILD/_proteome_src.fa"

# ---- 6. gff.sqlite (agent gene-level Q&A) ----
log "build gff.sqlite"
GFF_PLAIN="$BUILD/agent/genes.gff3"
zcat "$BUNDLE/annotation/genes.gff3.gz" > "$GFF_PLAIN"
GFF_INPUTS="$GFF_PLAIN" GFF_DB_OUT="$BUILD/agent/gff.sqlite" \
  python "$WT/scripts/build_gff_db.py"
rm -f "$GFF_PLAIN"

# ---- 7. RAG index (reports + functional annotation tables) ----
log "build RAG chunks.jsonl"
PROJECT_DIR="$BUNDLE" RAG_OUT_DIR="$BUILD/agent/rag" \
RAG_SOURCES="qc/RESULTS.md:reports/Spalangia_cameroni_genome_report.md:reports/methods_explained.md:functional/eggNOG_annotations.txt:functional/funannotate_annotations.txt:functional/pfam.tsv:qc/BUSCO_assembly_hymenoptera_odb10.txt:qc/BUSCO_proteome_hymenoptera_odb10.txt" \
  python "$WT/scripts/build_rag_index.py"

log "DONE prep_web_bundle"
ls -lh "$BUILD/genome" "$BUILD/tracks" "$BUILD/blast/db" "$BUILD/agent"
