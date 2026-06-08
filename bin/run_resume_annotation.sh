#!/usr/bin/env bash
# ============================================================================
# RESUME DRIVER — remaining annotation steps for the revised 4,980-contig genome
# ============================================================================
# Runs the next pipeline steps in order, idempotently. nohup/setsid-safe.
# Each STEP skips itself if its output already exists, so you can re-run freely.
# Start from a given step:   STEP_FROM=4 ./run_resume_annotation.sh
#
# STEP 1  RNA-Seq acquire   (ENA direct FASTQ — sra-tools 3.4.1 segfaults on the .sra)
# STEP 2  RNA-Seq trim      (fastp -> rnaseq/trimmed_{1,2}.fastq.gz)
# STEP 3  Stage TSA         (symlink -> rnaseq/spalangia_tsa.fasta)
# STEP 4  Phase 7.3         (pipeline: HISAT2 reads + minimap2 TSA -> BAMs)
# STEP 5  BRAKER preflight  (stage protein evidence; check/instate GeneMark)
# STEP 6  Phase 7.4         (pipeline: BRAKER3 gene prediction)   [needs GeneMark]
# STEP 7  Phase 7.5         (pipeline: eggNOG-mapper + diamond functional)
# ============================================================================
set -uo pipefail
PROJECT=/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly
cd "$PROJECT"
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate genome_assembly

RNASEQ=$PROJECT/rnaseq
TSA_SRC=$PROJECT/short_reads_contem_index/GBVV01.transcripts.one_line.fasta
NAS_PROT=/mnt/data/genomes/wasp_nasonia/GCF_009193385.2_Nvit_psr_1.1_protein.faa
MASKED=$PROJECT/annotation/repeats/final_assembly.fa.masked
THREADS=16
STEP_FROM=${STEP_FROM:-1}
mkdir -p "$RNASEQ" "$PROJECT/annotation"
LOG=$PROJECT/logs/resume_annotation_$(date +%Y%m%d_%H%M%S).log
exec > >(tee -a "$LOG") 2>&1
echo "==== resume driver started $(date -Iseconds)  PID=$$  STEP_FROM=$STEP_FROM ===="
run_pipe(){ PYTHONPATH="$PROJECT/denovo-assembly-core" python -m denovo_assembly_core.pipeline \
            --config "$PROJECT/project.yaml" --phase "$1" --force --no-report; }

# ── STEP 1: RNA-Seq acquisition from ENA (md5-verified), bypassing sra-tools ──
if [ "$STEP_FROM" -le 1 ]; then
echo "==== STEP 1: RNA-Seq acquire (ENA direct) $(date -Iseconds) ===="
declare -A MD5=( [SRR1502981_1.fastq.gz]=0b3ec86eea468e0097178e1346a1f2a8
                 [SRR1502981_2.fastq.gz]=854ead5cb0ee6c92f481d8272bb7d03c )
BASE=https://ftp.sra.ebi.ac.uk/vol1/fastq/SRR150/001/SRR1502981
dl_one(){ # $1 = filename ; download (resume) only if missing/!md5, then verify
  local f=$1
  if [ -s "$RNASEQ/$f" ] && [ "$(md5sum "$RNASEQ/$f" | cut -d' ' -f1)" = "${MD5[$f]}" ]; then
    echo "[skip] $f present + md5 OK"; return 0
  fi
  echo "[dl] $f ..."; wget -q -c -O "$RNASEQ/$f" "$BASE/$f"
  local got; got=$(md5sum "$RNASEQ/$f" | cut -d' ' -f1)
  [ "$got" = "${MD5[$f]}" ] && { echo "[ok] $f md5 verified"; return 0; } || { echo "FATAL: md5 mismatch $f ($got)"; return 1; }
}
# both mates download concurrently
dl_one SRR1502981_1.fastq.gz & P1=$!
dl_one SRR1502981_2.fastq.gz & P2=$!
wait $P1 || exit 1
wait $P2 || exit 1
echo "[ok] both mates present + verified"
fi

# ── STEP 2: fastp trim -> the exact names phase 7.3 expects ──
if [ "$STEP_FROM" -le 2 ]; then
echo "==== STEP 2: fastp trim $(date -Iseconds) ===="
if [ -s "$RNASEQ/trimmed_1.fastq.gz" ] && [ -s "$RNASEQ/trimmed_2.fastq.gz" ]; then
  echo "[skip] trimmed_{1,2}.fastq.gz present"
else
  fastp -i "$RNASEQ/SRR1502981_1.fastq.gz" -I "$RNASEQ/SRR1502981_2.fastq.gz" \
        -o "$RNASEQ/trimmed_1.fastq.gz" -O "$RNASEQ/trimmed_2.fastq.gz" \
        -q 20 -l 36 --thread $THREADS \
        -j "$RNASEQ/fastp_rnaseq.json" -h "$RNASEQ/fastp_rnaseq.html"
fi
fi

# ── STEP 3: stage TSA transcriptome under expected name ──
if [ "$STEP_FROM" -le 3 ]; then
echo "==== STEP 3: stage TSA $(date -Iseconds) ===="
[ -e "$RNASEQ/spalangia_tsa.fasta" ] || ln -s "$TSA_SRC" "$RNASEQ/spalangia_tsa.fasta"
echo "[ok] $RNASEQ/spalangia_tsa.fasta -> $(readlink -f "$RNASEQ/spalangia_tsa.fasta")"
fi

# ── STEP 4: Phase 7.3 — HISAT2 reads + minimap2 TSA -> sorted/indexed BAMs ──
if [ "$STEP_FROM" -le 4 ]; then
echo "==== STEP 4: pipeline phase 7.3 $(date -Iseconds) ===="
[ -s "$MASKED" ] || { echo "FATAL: masked genome $MASKED missing"; exit 1; }
run_pipe 7.3; echo "phase 7.3 rc=$?"
[ -s "$RNASEQ/rnaseq_aligned.bam" ] && { echo "--- RNA-Seq flagstat ---"; samtools flagstat "$RNASEQ/rnaseq_aligned.bam"; }
[ -s "$RNASEQ/tsa_aligned.bam" ]   && { echo "--- TSA flagstat ---";     samtools flagstat "$RNASEQ/tsa_aligned.bam"; }
fi

# ── STEP 5: BRAKER preflight — protein evidence + GeneMark availability ──
if [ "$STEP_FROM" -le 5 ]; then
echo "==== STEP 5: BRAKER preflight $(date -Iseconds) ===="
# protein evidence for BRAKER3 (closely-related pteromalid proteome)
[ -e "$PROJECT/annotation/hymenoptera_proteins.fa" ] || ln -s "$NAS_PROT" "$PROJECT/annotation/hymenoptera_proteins.fa"
echo "[ok] protein evidence: $(readlink -f "$PROJECT/annotation/hymenoptera_proteins.fa")"
if command -v gmes_petap.pl >/dev/null 2>&1 && [ -f "$HOME/.gm_key" ]; then
  echo "[ok] GeneMark present -> 7.4 can run"
else
  echo "[BLOCK] GeneMark missing (gmes_petap.pl and/or ~/.gm_key)."
  echo "        BRAKER3 (STEP 6) cannot run. Install GeneMark-ES/ETP + place the"
  echo "        gm_key in \$HOME/.gm_key, then resume with: STEP_FROM=6 $0"
  echo "==== resume driver STOPPING before STEP 6 (7.3 outputs are complete) ===="
  exit 0
fi
fi

# ── STEP 6: Phase 7.4 — BRAKER3 gene prediction ──
if [ "$STEP_FROM" -le 6 ]; then
echo "==== STEP 6: pipeline phase 7.4 (BRAKER3) $(date -Iseconds) ===="
run_pipe 7.4; echo "phase 7.4 rc=$?"
[ -s "$PROJECT/annotation/braker/braker.aa" ] && echo "[ok] braker.aa: $(grep -c '^>' "$PROJECT/annotation/braker/braker.aa") proteins"
fi

# ── STEP 7: Phase 7.5 — functional annotation ──
if [ "$STEP_FROM" -le 7 ]; then
echo "==== STEP 7: pipeline phase 7.5 (functional) $(date -Iseconds) ===="
run_pipe 7.5; echo "phase 7.5 rc=$?"
fi

echo "==== resume driver finished $(date -Iseconds) ===="
