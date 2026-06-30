#!/usr/bin/env bash
#
# drive_v3.sh — autonomous driver for the v3 assembly pipeline
#
# Workflow:
#   1. Wait for Phase 1.2 (cutadapt + fastp, currently PID 995417) to finish
#   2. seqkit grep -v with today's drop lists → clean FASTQs at canonical paths
#   3. Sanity-check read counts (R1 == R2, pacbio == 808171)
#   4. Write read_filter_summary.json (v3 provenance)
#   5. Mark phase1.2b_decontam_reads completed in pipeline_status.json
#   6. Launch ./run_pipeline.sh 1.3-4  (k-mer → hifiasm → Flye → merge → polish → Kraken2 decontam)
#   7. Wait for 1.3-4 to finish (~17–25 h)
#   8. Write qc/v3_phase4_summary.md summarizing Phase 4 results
#
# Launched under nohup so it survives the Claude session being closed.

set -euo pipefail

PROJECT=/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly
READS=$PROJECT/decontamination/reads
PHASE12_PID=995417
LOG_DIR=$PROJECT/logs
mkdir -p "$LOG_DIR"
LOG=$LOG_DIR/drive_v3_$(date +%Y%m%d_%H%M%S).log

exec > >(tee -a "$LOG") 2>&1
echo "==== drive_v3.sh started: $(date -Is) ===="
echo "Driver PID: $$  | Logging to: $LOG"
echo $$ > $PROJECT/drive_v3.pid

# Activate conda env (seqkit, pigz, jq, samtools, fastp, etc.)
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate genome_assembly
echo "conda env: ${CONDA_DEFAULT_ENV:-?}"
echo "seqkit: $(which seqkit) ($(seqkit version | head -1))"
echo "pigz:   $(which pigz)"
echo "jq:     $(which jq) ($(jq --version))"

# ─────────────────────────────────────────────────────────────
# Step 1 — wait for Phase 1.2
# ─────────────────────────────────────────────────────────────
echo ""
echo "==== Step 1: Wait for Phase 1.2 (PID $PHASE12_PID) ===="
START=$(date +%s)
while kill -0 $PHASE12_PID 2>/dev/null; do sleep 30; done
echo "Phase 1.2 ended at $(date -Is); driver waited $(( $(date +%s) - START ))s for it."

PHASE12_STATUS=$(jq -r '.["phase1.2_illumina_qc"].status // "missing"' $PROJECT/pipeline_status.json)
echo "phase1.2_illumina_qc status in JSON: $PHASE12_STATUS"
if [ "$PHASE12_STATUS" != "completed" ]; then
  echo "FATAL: Phase 1.2 did not complete cleanly. Aborting."
  rm -f $PROJECT/drive_v3.pid
  exit 1
fi

for F in $PROJECT/qc/illumina/trimmed_R1.fastq.gz $PROJECT/qc/illumina/trimmed_R2.fastq.gz; do
  if [ ! -s "$F" ]; then
    echo "FATAL: missing or empty: $F"
    rm -f $PROJECT/drive_v3.pid
    exit 1
  fi
  echo "  ok  $F  ($(du -h "$F" | cut -f1))"
done

# ─────────────────────────────────────────────────────────────
# Step 2 — seqkit grep -v: produce clean FASTQs
# ─────────────────────────────────────────────────────────────
echo ""
echo "==== Step 2: seqkit grep -v ===="

for F in $READS/pacbio_drop.ids $READS/illumina_drop.ids; do
  if [ ! -s "$F" ]; then
    echo "FATAL: missing or empty drop list: $F"
    rm -f $PROJECT/drive_v3.pid
    exit 1
  fi
done
echo "pacbio_drop.ids   = $(wc -l < $READS/pacbio_drop.ids) lines (expect 58192)"
echo "illumina_drop.ids = $(wc -l < $READS/illumina_drop.ids) lines (expect 14657746)"

echo ""
echo "--- 2a. PacBio ---"
T0=$(date +%s)
seqkit grep -v -f $READS/pacbio_drop.ids $PROJECT/GMCF_3514_04.107_107.fastq \
  | pigz -p 8 > $PROJECT/qc/clean_pacbio.fastq.gz
echo "wrote qc/clean_pacbio.fastq.gz in $(( $(date +%s) - T0 ))s"

echo ""
echo "--- 2b. Illumina R1 ---"
T0=$(date +%s)
seqkit grep -v -f $READS/illumina_drop.ids $PROJECT/qc/illumina/trimmed_R1.fastq.gz \
  | pigz -p 8 > $PROJECT/qc/illumina/clean_R1.fastq.gz
echo "wrote qc/illumina/clean_R1.fastq.gz in $(( $(date +%s) - T0 ))s"

echo ""
echo "--- 2c. Illumina R2 ---"
T0=$(date +%s)
seqkit grep -v -f $READS/illumina_drop.ids $PROJECT/qc/illumina/trimmed_R2.fastq.gz \
  | pigz -p 8 > $PROJECT/qc/illumina/clean_R2.fastq.gz
echo "wrote qc/illumina/clean_R2.fastq.gz in $(( $(date +%s) - T0 ))s"

# ─────────────────────────────────────────────────────────────
# Step 3 — verify counts
# ─────────────────────────────────────────────────────────────
echo ""
echo "==== Step 3: Verify counts ===="
PB_KEPT=$(zcat $PROJECT/qc/clean_pacbio.fastq.gz | awk 'NR%4==1' | wc -l)
R1_KEPT=$(zcat $PROJECT/qc/illumina/clean_R1.fastq.gz | awk 'NR%4==1' | wc -l)
R2_KEPT=$(zcat $PROJECT/qc/illumina/clean_R2.fastq.gz | awk 'NR%4==1' | wc -l)
echo "PacBio kept:  $PB_KEPT  (expect ~808171)"
echo "Illumina R1:  $R1_KEPT"
echo "Illumina R2:  $R2_KEPT"
if [ "$R1_KEPT" != "$R2_KEPT" ]; then
  echo "FATAL: R1 != R2 — pairing integrity broken"
  rm -f $PROJECT/drive_v3.pid
  exit 1
fi
echo "ok  R1 == R2 ($R1_KEPT pairs)"

# ─────────────────────────────────────────────────────────────
# Step 4 — write read_filter_summary.json
# ─────────────────────────────────────────────────────────────
echo ""
echo "==== Step 4: Write read_filter_summary.json ===="
cat > $READS/read_filter_summary.json <<EOF
{
  "method": "single-pass alignment vs prefix-tagged composite (v3, 2026-05-25)",
  "composite_ref": "$PROJECT/short_reads_contem_index/composite.fa",
  "insect_prefixes": ["Spalangia_cameroni_", "Nasonia_vitripennis_", "Solenopsis_invicta_"],
  "bowtie2_preset": "--local (AS > XS filter)",
  "minimap2_preset": "map-hifi (MAPQ >= 1 filter)",
  "rescue_rule": "DROP = confident_contam_hits - confident_insect_hits",
  "executed_via": "standalone run_decontam_align.sh; clean FASTQs regenerated by drive_v3.sh on $(date -Is)",
  "pacbio":   {"confident_contam_hits": 60700,    "confident_insect_hits": 441570,   "dropped": 58192,    "kept": $PB_KEPT},
  "illumina": {"confident_contam_hits": 14750873, "confident_insect_hits": 35220230, "dropped": 14657746, "kept_pairs": $R1_KEPT}
}
EOF
echo "wrote $READS/read_filter_summary.json"

# ─────────────────────────────────────────────────────────────
# Step 5 — mark phase1.2b_decontam_reads completed
# ─────────────────────────────────────────────────────────────
echo ""
echo "==== Step 5: Update pipeline_status.json ===="
NOW=$(date -Is)
jq --arg s "2026-05-25T12:07:32" --arg e "$NOW" '
  .["phase1.2b_decontam_reads"] = {
    "status": "completed",
    "started": $s,
    "completed": $e,
    "details": {
      "executed_via": "standalone alignment 2026-05-25 + drive_v3.sh seqkit filtering",
      "pacbio_dropped": 58192,
      "illumina_pairs_dropped": 14657746
    }
  }
' $PROJECT/pipeline_status.json > $PROJECT/pipeline_status.json.tmp \
  && mv $PROJECT/pipeline_status.json.tmp $PROJECT/pipeline_status.json
jq '.["phase1.2b_decontam_reads"]' $PROJECT/pipeline_status.json

# ─────────────────────────────────────────────────────────────
# Step 6 — launch ./run_pipeline.sh 1.3-4
# ─────────────────────────────────────────────────────────────
echo ""
echo "==== Step 6: Launch ./run_pipeline.sh 1.3-4 ===="
cd $PROJECT

# Wait briefly to ensure any stale pipeline.pid is gone
if [ -f $PROJECT/pipeline.pid ]; then
  STALE=$(cat $PROJECT/pipeline.pid)
  if ! kill -0 $STALE 2>/dev/null; then
    echo "Removing stale pipeline.pid (was $STALE)"
    rm -f $PROJECT/pipeline.pid
  else
    echo "FATAL: pipeline.pid present and process $STALE is still alive"
    rm -f $PROJECT/drive_v3.pid
    exit 1
  fi
fi

./run_pipeline.sh 1.3-4
sleep 5

if [ ! -f $PROJECT/pipeline.pid ]; then
  echo "FATAL: pipeline.pid not created — 1.3-4 did not start"
  rm -f $PROJECT/drive_v3.pid
  exit 1
fi
NEW_PID=$(cat $PROJECT/pipeline.pid)
echo "Pipeline 1.3-4 started (PID $NEW_PID)"

# ─────────────────────────────────────────────────────────────
# Step 7 — wait for 1.3-4 to finish
# ─────────────────────────────────────────────────────────────
echo ""
echo "==== Step 7: Wait for 1.3-4 (PID $NEW_PID) ===="
START=$(date +%s)
while kill -0 $NEW_PID 2>/dev/null; do sleep 300; done
ELAPSED=$(( $(date +%s) - START ))
echo "1.3-4 ended at $(date -Is); driver waited ${ELAPSED}s (~$((ELAPSED/3600))h) for it."

# ─────────────────────────────────────────────────────────────
# Step 8 — write summary
# ─────────────────────────────────────────────────────────────
echo ""
echo "==== Step 8: Write v3_phase4_summary.md ===="
SUMMARY=$PROJECT/qc/v3_phase4_summary.md
{
  echo "# v3 Pipeline — Phase 1.3 → 4 Summary"
  echo ""
  echo "- Generated: $(date -Is)"
  echo "- Driver log: $LOG"
  echo "- Pipeline log: $PROJECT/nohup_pipeline.log"
  echo ""

  echo "## Pipeline status (final)"
  echo '```json'
  jq 'to_entries | map({phase:.key, status:.value.status, completed:.value.completed})' $PROJECT/pipeline_status.json
  echo '```'
  echo ""

  echo "## Read-level decontam (Phase 1.2b)"
  if [ -s $READS/read_filter_summary.json ]; then
    echo '```json'
    cat $READS/read_filter_summary.json
    echo '```'
  fi
  echo ""

  echo "## Pre-Phase-4 (polished) assembly"
  if [ -s $PROJECT/polish/genome.nextpolish.fasta ]; then
    echo '```'
    seqkit stats -a $PROJECT/polish/genome.nextpolish.fasta
    echo '```'
  else
    echo "(polished assembly not found at polish/genome.nextpolish.fasta)"
    if compgen -G "$PROJECT/polish/*.fasta" > /dev/null; then
      echo '```'
      seqkit stats -a $PROJECT/polish/*.fasta
      echo '```'
    fi
  fi
  echo ""

  echo "## Phase 4 — Kraken2 contig decontam outputs"
  if [ -s $PROJECT/decontamination/contigs.kreport ]; then
    echo "### Kraken2 report (top lineages)"
    echo '```'
    head -40 $PROJECT/decontamination/contigs.kreport
    echo '```'
  fi
  echo ""
  if [ -s $PROJECT/decontamination/contam_contigs.txt ]; then
    CONTAM_N=$(wc -l < $PROJECT/decontamination/contam_contigs.txt)
    echo "### Contam contigs dropped: $CONTAM_N"
    echo '```'
    head -100 $PROJECT/decontamination/contam_contigs.txt
    echo '```'
  else
    echo "(no contam_contigs.txt found)"
  fi
  echo ""

  echo "## Post-Phase-4 (clean) assembly"
  if [ -s $PROJECT/decontamination/clean_assembly.fa ]; then
    echo '```'
    seqkit stats -a $PROJECT/decontamination/clean_assembly.fa
    echo '```'
  else
    echo "(clean_assembly.fa not found)"
  fi
  echo ""

  echo "## v2 baseline (for comparison)"
  echo "- v2 final assembly: 6,136 contigs, 517.9 Mb"
  echo "- v2 BUSCO (insecta_odb10): C:71.1%[S:69.2%,D:1.9%],F:4.0%,M:24.9% (4259/5991)"
  echo "- v2 used Kraken2 PlusPF-8 read-level filter (now replaced by alignment-based v3)"
} > $SUMMARY
echo "wrote $SUMMARY"

rm -f $PROJECT/drive_v3.pid

echo ""
echo "==== drive_v3.sh COMPLETE: $(date -Is) ===="
