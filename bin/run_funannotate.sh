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
# funannotate/NCBI tbl2asn reject sequence IDs >16 chars. The assembly contigs
# (ptg000001l_np1212 = 17 chars) are renamed in a funannotate-only copy by
# stripping the uniform _np1212 suffix -> 10-char hifiasm names (built in
# annotation/funannotate_in/; canonical files untouched). GFFs renamed to match.
GENOME="$PROJECT/annotation/funannotate_in/genome.fa"
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
# Presence-aware: DBs already downloaded in a prior run are skipped (avoids
# re-downloading ~5 GB and avoids funannotate's stale-URL HTTP 403s).
notify "[S.cam funannotate] DB setup START" "per-DB; skip already-present; merops + go handled specially"
# go.obo: funannotate's hardcoded GO URL 403s; fetch the canonical file directly.
if [ ! -s "$FUNANNOTATE_DB/go.obo" ]; then
  curl -fsSL --connect-timeout 30 -o "$FUNANNOTATE_DB/go.obo" \
    "http://purl.obolibrary.org/obo/go.obo" >>"$LOG" 2>&1 \
    && echo "[setup] go.obo ok (direct)" \
    || notify "[S.cam funannotate] go.obo fetch FAIL" "gff2tbl needs go.obo; see $LOG"
else
  echo "[setup] go.obo already present, skip"
fi
# sentinel file per DB → skip if already installed
declare -A DBSENT=( [pfam]=Pfam-A.hmm [gene2product]=ncbi_cleaned_gene_products.txt \
  [uniprot]=uniprot.dmnd [dbCAN]=dbCAN.hmm [interpro]=interpro.xml [mibig]=mibig.dmnd \
  [repeats]=repeats.dmnd [busco_outgroups]=busco_outgroups.tar.gz )
for db in pfam gene2product uniprot dbCAN interpro mibig repeats busco_outgroups; do
  if [ -s "$FUNANNOTATE_DB/${DBSENT[$db]}" ]; then
    echo "[setup] $db already present, skip"
  elif FUNANNOTATE_DB="$FUNANNOTATE_DB" fun funannotate setup -i "$db" -d "$FUNANNOTATE_DB" --update >>"$LOG" 2>&1; then
    echo "[setup] $db ok"
  else
    notify "[S.cam funannotate] setup $db FAIL" "continuing without it"
  fi
done
if [ -s "$FUNANNOTATE_DB/merops.dmnd" ]; then
  echo "[setup] merops already present, skip"
else
  FUNANNOTATE_DB="$FUNANNOTATE_DB" fun funannotate setup -i merops -d "$FUNANNOTATE_DB" >>"$LOG" 2>&1 \
    && echo "[setup] merops ok" || notify "[S.cam funannotate] merops setup FAIL (known bug)" "annotate runs without MEROPS"
fi

# ---- annotate (prefer the rescued models; fall back to braker) ----
# Use the renamed-to-match GFFs (contig IDs <=16 chars), built alongside genome.fa.
GFF="$PROJECT/annotation/funannotate_in/rescued.gff3"; [ -s "$GFF" ] || GFF="$PROJECT/annotation/funannotate_in/braker.gff3"
notify "[S.cam funannotate] annotate START" "input=$GFF"
EGG=""
[ -s "$PROJECT/analysis/kegg/eggnog.emapper.annotations" ] && EGG="--eggnog $PROJECT/analysis/kegg/eggnog.emapper.annotations"
rm -rf "$OUT"
if FUNANNOTATE_DB="$FUNANNOTATE_DB" fun funannotate annotate --gff "$GFF" --fasta "$GENOME" \
     --species "Spalangia cameroni" --cpus "$THREADS" -o "$OUT" --busco_db hymenoptera $EGG >>"$LOG" 2>&1; then
  notify "[S.cam funannotate] annotate DONE" "results: $OUT/annotate_results/"
else
  # retry with braker models if the rescued set was rejected
  if [ "$GFF" != "$PROJECT/annotation/funannotate_in/braker.gff3" ]; then
    GFF="$PROJECT/annotation/funannotate_in/braker.gff3"
    notify "[S.cam funannotate] retry on braker models" "rescued set rejected; retrying braker.gff3 (renamed contigs)"
    FUNANNOTATE_DB="$FUNANNOTATE_DB" fun funannotate annotate --gff "$GFF" --fasta "$GENOME" \
      --species "Spalangia cameroni" --cpus "$THREADS" -o "$OUT" --busco_db hymenoptera $EGG >>"$LOG" 2>&1 \
      && notify "[S.cam funannotate] annotate DONE (braker)" "results: $OUT/annotate_results/" \
      || notify "[S.cam funannotate] annotate FAIL" "see $LOG"
  else
    notify "[S.cam funannotate] annotate FAIL" "see $LOG"
  fi
fi
echo "==== funannotate driver END $(date -Iseconds) ===="
