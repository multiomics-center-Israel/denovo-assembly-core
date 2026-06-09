#!/usr/bin/env bash
# ============================================================================
# Functional annotation of the EVM+PASA + Tiberius-graft MERGED set, then make
# it the project CANONICAL annotation.
# ----------------------------------------------------------------------------
#  STAGE 1  Build a clean STRUCTURAL merged gff3 = structural EVM+PASA models
#           (annotation/funannotate_evm_in/evm_pasa.gff3, 12,580 genes) +
#           the kept Tiberius graft features (TIBR_*, 4,076 genes) extracted
#           from analysis/merge_tiberius/Spalangia_cameroni.merged.gff3.
#           (We feed structural models — NOT funannotate's own output — so the
#           grafted genes get the SAME functional pipeline as everything else.)
#  STAGE 2  funannotate annotate on the merged models (same DBs/flags as the
#           EVM canonical run: PFAM/dbCAN/SwissProt/MEROPS/BUSCO; no eggNOG).
#  STAGE 3  BUSCO(protein) on the merged annotated proteome.
#  STAGE 4  Designate canonical: annotation/canonical_annotation -> merged results.
# Detached, best-effort, emails each stage. Launch with nohup/setsid.
# ============================================================================
set -uo pipefail
PROJECT=/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly
cd "$PROJECT"
source "$(conda info --base)/etc/profile.d/conda.sh"
RUNENV=genome_assembly
FUNENV=funannotate
export FUNANNOTATE_DB="$PROJECT/funannotate_db"

GENOME16="$PROJECT/annotation/funannotate_in/genome.fa"          # <=16-char contig names
EVM_STRUCT="$PROJECT/annotation/funannotate_evm_in/evm_pasa.gff3" # structural EVM+PASA (12,580)
MERGED_GFF="$PROJECT/analysis/merge_tiberius/Spalangia_cameroni.merged.gff3"
FUNIN="$PROJECT/annotation/funannotate_merged_in"
FUNOUT="$PROJECT/annotation/funannotate_merged_out"
LIN="$PROJECT/busco_downloads/lineages/hymenoptera_odb10"
BUSCODIR="$PROJECT/analysis/busco"
mkdir -p "$FUNIN" "$PROJECT/logs"
TS=$(date +%Y%m%d_%H%M%S); LOG="$PROJECT/logs/merged_functional_canonical_${TS}.log"
exec > >(tee -a "$LOG") 2>&1
echo "==== merged functional+canonical driver START $(date -Iseconds)  PID=$$  PPID=$PPID ===="
notify(){ PYTHONPATH="$PROJECT/denovo-assembly-core" python3 -m denovo_assembly_core.notify \
          --config "$PROJECT/project.yaml" "$1" "${2:-}" 2>>"$LOG" || true; }
run(){ conda run -n "$RUNENV" "$@"; }
fun(){ conda run -n "$FUNENV" "$@"; }

# sanity
for f in "$GENOME16" "$EVM_STRUCT" "$MERGED_GFF"; do
  [ -s "$f" ] || { notify "[S.cam MERGED] ABORT" "missing input: $f"; echo "ABORT missing $f"; exit 1; }
done
notify "[S.cam MERGED] launched" "PID=$$ log=$LOG
functional annotation of merged set (12,580 EVM + 4,076 Tiberius graft) -> canonical"

# ===========================================================================
# STAGE 1 — build structural merged gff3
# ===========================================================================
MGFF="$FUNIN/merged.gff3"
{
  echo "##gff-version 3"
  grep -v '^#' "$EVM_STRUCT"
  grep 'TIBR_' "$MERGED_GFF" | grep -v '^#'
} > "$MGFF"
NG=$(awk -F'\t' '$3=="gene"' "$MGFF" | wc -l)
NTIBR=$(awk -F'\t' '$3=="gene" && /ID=TIBR_/' "$MGFF" | wc -l)
echo "[stage1] structural merged gff3: $MGFF  genes=$NG (TIBR=$NTIBR)"
notify "[S.cam MERGED] STAGE 1 DONE" "structural merged gff3: $NG genes ($NTIBR grafted)"

# ===========================================================================
# STAGE 2 — funannotate annotate
# ===========================================================================
[ -d "$FUNANNOTATE_DB/hymenoptera" ] || fun funannotate setup -b hymenoptera -d "$FUNANNOTATE_DB" >>"$LOG" 2>&1 || true
EGG=""; [ -s "$PROJECT/analysis/kegg/eggnog.emapper.annotations" ] && EGG="--eggnog $PROJECT/analysis/kegg/eggnog.emapper.annotations"

rm -rf "$FUNOUT"
notify "[S.cam MERGED] STAGE 2: funannotate annotate START" "input=$MGFF ($NG genes)"
if FUNANNOTATE_DB="$FUNANNOTATE_DB" fun funannotate annotate --gff "$MGFF" --fasta "$GENOME16" \
     --species "Spalangia cameroni" --cpus 8 -o "$FUNOUT" --busco_db hymenoptera $EGG >>"$LOG" 2>&1; then
  RES="$FUNOUT/annotate_results"
  NGENE=$(awk -F'\t' '$3=="gene"' "$RES"/*.gff3 2>/dev/null | wc -l)
  notify "[S.cam MERGED] STAGE 2 DONE" "merged functional annotation: $RES/  genes=$NGENE"
else
  notify "[S.cam MERGED] STAGE 2 FAIL" "funannotate annotate failed; see $LOG"
  echo "STAGE 2 FAILED"; exit 2
fi

# ===========================================================================
# STAGE 3 — BUSCO on merged annotated proteome
# ===========================================================================
AA="$FUNOUT/annotate_results/Spalangia_cameroni.proteins.fa"
if [ -s "$AA" ]; then
  notify "[S.cam MERGED] BUSCO START" "merged_canonical_prot vs hymenoptera_odb10"
  run busco -i "$AA" -l "$LIN" -m protein -c 8 --offline \
      --download_path "$PROJECT/busco_downloads" --out_path "$BUSCODIR" -o merged_canonical_prot -f >>"$LOG" 2>&1 || true
fi
BUSCO=$(grep -h 'C:' "$BUSCODIR"/merged_canonical_prot/short_summary*.txt 2>/dev/null | head -1)
echo "[stage3] merged canonical BUSCO: $BUSCO"

# ===========================================================================
# STAGE 4 — designate canonical
# ===========================================================================
ln -sfn "funannotate_merged_out/annotate_results" "$PROJECT/annotation/canonical_annotation"
cat > "$PROJECT/annotation/canonical_annotation/CANONICAL.md" <<EOF
# CANONICAL annotation — Spalangia cameroni
Set: EVM+PASA (12,580) + evidence-gated Tiberius graft (4,076) = merged
Functional annotation: funannotate annotate (PFAM/dbCAN/SwissProt/MEROPS/BUSCO; no eggNOG)
Designated canonical: $(date -Iseconds)
Source dir: annotation/funannotate_merged_out/annotate_results/
Graft gate: BUSCO-rescue OR Nasonia homology, add-only at novel loci, dup-protected
Merged-proteome BUSCO: $BUSCO
Previous canonical (superseded): annotation/funannotate_evm_out/annotate_results/ (12,580 genes)
EOF
notify "[S.cam MERGED] ALL DONE — CANONICAL SET UPDATED" "canonical -> annotation/funannotate_merged_out/annotate_results/
genes=$NGENE  BUSCO=$BUSCO
symlink: annotation/canonical_annotation"
echo "==== merged functional+canonical driver END $(date -Iseconds) ===="
