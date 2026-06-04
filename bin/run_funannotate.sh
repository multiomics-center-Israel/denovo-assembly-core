#!/usr/bin/env bash
# ============================================================================
# FUNANNOTATE functional annotation  — detached, best-effort, email per stage
# ============================================================================
# Works around the funannotate-1.8.17 `setup -b insecta` meropsDB crash
# (TypeError: cannot unpack non-iterable NoneType) by installing each DB
# individually so one failing download doesn't abort the whole setup, then
# running `funannotate annotate` on the gene models. merops is attempted last
# and is non-fatal (annotate proceeds with whatever DBs are present).
# Launch detached:
#   setsid bash -c '/mnt/data/.../run_funannotate.sh' >/dev/null 2>&1 &
# ============================================================================
set -uo pipefail
PROJECT=/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly
cd "$PROJECT"
source "$(conda info --base)/etc/profile.d/conda.sh"
ENV=funannotate
export FUNANNOTATE_DB="$PROJECT/funannotate_db"
GENOME="$PROJECT/final_assembly.fa"
OUT="$PROJECT/annotation/funannotate_out"
THREADS=8
mkdir -p "$FUNANNOTATE_DB" "$PROJECT/logs"
TS=$(date +%Y%m%d_%H%M%S); LOG="$PROJECT/logs/funannotate_${TS}.log"
exec > >(tee -a "$LOG") 2>&1
echo "==== funannotate driver START $(date -Iseconds)  PID=$$  PPID=$PPID ===="
notify(){ PYTHONPATH="$PROJECT/denovo-assembly-core" python3 -m denovo_assembly_core.notify \
          --config "$PROJECT/project.yaml" "$1" "${2:-}" 2>>"$LOG" || true; }
fun(){ conda run -n "$ENV" "$@"; }
notify "[S.cam funannotate] launched" "PID=$$ log=$LOG FUNANNOTATE_DB=$FUNANNOTATE_DB"

# ---- DB setup, one source at a time (skip the merops crash) ----
notify "[S.cam funannotate] DB setup START" "per-DB; merops attempted last (non-fatal)"
for db in pfam gene2product uniprot dbCAN go interpro mibig repeats busco_outgroups; do
  if FUNANNOTATE_DB="$FUNANNOTATE_DB" fun funannotate setup -i "$db" -d "$FUNANNOTATE_DB" --update >>"$LOG" 2>&1; then
    echo "[setup] $db ok"
  else
    notify "[S.cam funannotate] setup $db FAIL" "continuing without it"
  fi
done
FUNANNOTATE_DB="$FUNANNOTATE_DB" fun funannotate setup -i merops -d "$FUNANNOTATE_DB" >>"$LOG" 2>&1 \
  && echo "[setup] merops ok" || notify "[S.cam funannotate] merops setup FAIL (known bug)" "annotate runs without MEROPS"

# ---- annotate (prefer the rescued models; fall back to braker) ----
GFF="$PROJECT/annotation/refine/rescued.gff3"; [ -s "$GFF" ] || GFF="$PROJECT/annotation/braker/braker.gff3"
notify "[S.cam funannotate] annotate START" "input=$GFF"
EGG=""
[ -s "$PROJECT/analysis/kegg/eggnog.emapper.annotations" ] && EGG="--eggnog $PROJECT/analysis/kegg/eggnog.emapper.annotations"
rm -rf "$OUT"
if FUNANNOTATE_DB="$FUNANNOTATE_DB" fun funannotate annotate --gff3 "$GFF" --fasta "$GENOME" \
     --species "Spalangia cameroni" --cpus "$THREADS" -o "$OUT" --busco_db hymenoptera $EGG >>"$LOG" 2>&1; then
  notify "[S.cam funannotate] annotate DONE" "results: $OUT/annotate_results/"
else
  # retry with braker.gff3 if rescued failed validation
  if [ "$GFF" != "$PROJECT/annotation/braker/braker.gff3" ]; then
    GFF="$PROJECT/annotation/braker/braker.gff3"
    notify "[S.cam funannotate] retry on braker.gff3" "rescued.gff3 failed validation"
    FUNANNOTATE_DB="$FUNANNOTATE_DB" fun funannotate annotate --gff3 "$GFF" --fasta "$GENOME" \
      --species "Spalangia cameroni" --cpus "$THREADS" -o "$OUT" --busco_db hymenoptera $EGG >>"$LOG" 2>&1 \
      && notify "[S.cam funannotate] annotate DONE (braker)" "results: $OUT/annotate_results/" \
      || notify "[S.cam funannotate] annotate FAIL" "see $LOG"
  else
    notify "[S.cam funannotate] annotate FAIL" "see $LOG"
  fi
fi
echo "==== funannotate driver END $(date -Iseconds) ===="
