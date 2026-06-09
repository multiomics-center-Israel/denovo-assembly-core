#!/usr/bin/env bash
# ============================================================================
# EXPERIMENT: EVidenceModeler consensus WITH Tiberius added as an abinitio track
# (weighted below BRAKER), to compare against the post-hoc Tiberius GRAFT.
# ----------------------------------------------------------------------------
# Isolated run dir (annotation/refine/evm_tib/) so the CANONICAL EVM is untouched.
# Inputs reused from the canonical EVM dir: BRAKER gene_predictions, miniprot
# protein_alignments, PASA transcript_alignments, weights. Adds Tiberius (global
# ids, native _np1212 names) as ABINITIO_PREDICTION 'Tiberius' weight 2 (BRAKER=5).
# Runs EVM -> proteins -> BUSCO -> comparison table, then STOPS (PASA+funannotate
# is the follow-up only if this beats the graft). Detached, emails each stage.
# ============================================================================
set -uo pipefail
PROJECT=/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly
cd "$PROJECT"
source "$(conda info --base)/etc/profile.d/conda.sh"
RUNENV=genome_assembly
THREADS=8
TIB_WEIGHT=2                                  # below BRAKER (5)
GENOME="$PROJECT/final_assembly.fa"           # native _np1212 names (EVM namespace)
SRC="$PROJECT/annotation/refine/evm"          # canonical EVM dir (read-only here)
EVM="$PROJECT/annotation/refine/evm_tib"      # isolated experiment dir
PREP="$PROJECT/analysis/evm_tib_prep"
LIN="$PROJECT/busco_downloads/lineages/hymenoptera_odb10"
BUSCODIR="$PROJECT/analysis/busco"
mkdir -p "$EVM" "$PREP" "$PROJECT/logs"
TS=$(date +%Y%m%d_%H%M%S); LOG="$PROJECT/logs/evm_tiberius_experiment_${TS}.log"
exec > >(tee -a "$LOG") 2>&1
echo "==== EVM+Tiberius experiment START $(date -Iseconds)  PID=$$  PPID=$PPID ===="
notify(){ PYTHONPATH="$PROJECT/denovo-assembly-core" python3 -m denovo_assembly_core.notify \
          --config "$PROJECT/project.yaml" "$1" "${2:-}" 2>>"$LOG" || true; }
run(){ conda run -n "$RUNENV" "$@"; }
have_busco(){ ls "$BUSCODIR/$1"/short_summary*.txt >/dev/null 2>&1; }

for f in "$SRC/gene_predictions.gff3" "$SRC/transcript_alignments.gff3" "$SRC/weights.txt"; do
  [ -s "$f" ] || { notify "[S.cam EVM+Tib] ABORT" "missing $f"; echo "ABORT $f"; exit 1; }
done
notify "[S.cam EVM+Tib] launched" "PID=$$ log=$LOG
EVM consensus WITH Tiberius (weight $TIB_WEIGHT, BRAKER=5) vs the graft"

# --- STAGE 1: prep Tiberius EVM track (global ids, native names) -------------
echo "### STAGE 1: prep Tiberius abinitio track"
python3 "$PROJECT/annotation/scripts/vmc/normalize_tib_gtf.py" \
  "$PROJECT/tiberius_athena_res/tiberius_insecta.aa.fa" \
  "$PROJECT/tiberius_athena_res/tiberius_insecta.gtf" "$PREP/tib_native_global.gtf"
python3 "$PROJECT/annotation/scripts/vmc/tib_gtf_to_evm_gff3.py" \
  "$PREP/tib_native_global.gtf" "$PREP/tiberius.evm.gff3" Tiberius

# combined gene_predictions + weights
cat "$SRC/gene_predictions.gff3" <(grep -v '^#' "$PREP/tiberius.evm.gff3") > "$EVM/gene_predictions.gff3"
cp "$SRC/weights.txt" "$EVM/weights.txt"
grep -qP "^ABINITIO_PREDICTION\tTiberius\t" "$EVM/weights.txt" || \
  printf 'ABINITIO_PREDICTION\tTiberius\t%s\n' "$TIB_WEIGHT" >> "$EVM/weights.txt"
# reuse evidence
cp "$SRC/transcript_alignments.gff3" "$EVM/transcript_alignments.gff3"
[ -s "$SRC/protein_alignments.gff3" ] && cp "$SRC/protein_alignments.gff3" "$EVM/protein_alignments.gff3"
echo "[stage1] combined gene_predictions genes: $(awk -F'\t' '$3=="gene"' "$EVM/gene_predictions.gff3" | wc -l)"
echo "[stage1] weights:"; cat "$EVM/weights.txt"
notify "[S.cam EVM+Tib] STAGE 1 DONE" "Tiberius track added (weight $TIB_WEIGHT); running EVM"

# --- STAGE 2: run EVM -------------------------------------------------------
GP="$EVM/gene_predictions.gff3"; TA="$EVM/transcript_alignments.gff3"
PA="$EVM/protein_alignments.gff3"; WT="$EVM/weights.txt"; EVM_GFF="$EVM/evm.gff3"
rm -rf "$EVM"/spalangia.partitions "$EVM"/spalangia.* "$EVM"/__spalangia-EVM_chckpts "$EVM_GFF" 2>/dev/null || true
notify "[S.cam EVM+Tib] EVM START" "CPU=$THREADS"
( cd "$EVM" && conda run -n evm EVidenceModeler --sample_id spalangia --genome "$GENOME" \
    --weights "$WT" --gene_predictions "$GP" \
    $( [ -s "$PA" ] && echo --protein_alignments "$PA" ) \
    --transcript_alignments "$TA" \
    --segmentSize 100000 --overlapSize 10000 --CPU "$THREADS" 2>>"$LOG" )
rc=$?
out=$(ls "$EVM"/spalangia.EVM.gff3 "$EVM"/*.EVM.gff3 2>/dev/null | head -1)
if [ -n "$out" ] && [ -s "$out" ]; then
  cp "$out" "$EVM_GFF"
  run gffread "$EVM_GFF" -g "$GENOME" -y "$EVM/evm_tib.aa" -S 2>>"$LOG" || true
  NGENE=$(awk -F'\t' '$3=="gene"' "$EVM_GFF" | wc -l)
  NAA=$(grep -c '^>' "$EVM/evm_tib.aa" 2>/dev/null || echo 0)
  # how many consensus genes are Tiberius-derived (locus chosen from Tiberius)
  NTIB=$(grep -c 'Tiberius' "$EVM_GFF" 2>/dev/null || echo NA)
  notify "[S.cam EVM+Tib] EVM DONE" "consensus genes=$NGENE proteins=$NAA"
else
  notify "[S.cam EVM+Tib] EVM FAILED" "rc=$rc; see $LOG"; echo "EVM FAILED rc=$rc"; exit 2
fi

# --- STAGE 3: BUSCO ---------------------------------------------------------
if [ -s "$EVM/evm_tib.aa" ] && ! have_busco evm_tib_consensus_prot; then
  notify "[S.cam EVM+Tib] BUSCO START" "evm_tib_consensus_prot"
  run busco -i "$EVM/evm_tib.aa" -l "$LIN" -m protein -c "$THREADS" --offline \
      --download_path "$PROJECT/busco_downloads" --out_path "$BUSCODIR" -o evm_tib_consensus_prot -f 2>>"$LOG" || true
fi

# --- STAGE 4: comparison table ----------------------------------------------
b(){ grep -h 'C:' "$BUSCODIR/$1"/short_summary*.txt 2>/dev/null | head -1; }
g(){ awk -F'\t' '$3=="gene"' "$1" 2>/dev/null | wc -l; }
CMP="$PROJECT/analysis/comparison/evm_tib_vs_graft.tsv"
mkdir -p "$(dirname "$CMP")"
{
  printf "stage\tgenes\tBUSCO\n"
  printf "EVM consensus (BRAKER only)\t%s\t%s\n" "$(g "$SRC/evm.gff3")" "$(b evm_prot)"
  printf "EVM consensus + Tiberius (w=%s)\t%s\t%s\n" "$TIB_WEIGHT" "$(g "$EVM_GFF")" "$(b evm_tib_consensus_prot)"
  printf "GRAFT canonical (EVM+PASA+TIBR, post-funannotate)\t16656\t%s\n" "$(b merged_evm_tib_prot)"
} > "$CMP"
echo "=== comparison ==="; cat "$CMP"
notify "[S.cam EVM+Tib] DONE — COMPARE" "EVM+Tiberius consensus vs graft:
$(cat "$CMP")
NOTE: this is the EVM-consensus stage (pre-PASA/funannotate). If it beats the
graft on BUSCO without ballooning gene count / duplication, run PASA+funannotate
on $EVM_GFF (reuse run_evm_pasa_funannotate.sh pointed at evm_tib) for the final
apples-to-apples. Tiberius weight=$TIB_WEIGHT is tunable."
echo "==== EVM+Tiberius experiment END $(date -Iseconds) ===="
