#!/usr/bin/env bash
# ============================================================================
# EVM CONSENSUS (re-run of model-refinement STAGE B)  — detached, emailing
# ============================================================================
# Standalone redo of EVidenceModeler consensus after the first attempt failed:
# the miniprot protein alignments were emitted in miniprot's native format
# (Parent=/Target=, no chain ID), which EVM's parse_evidence_chains rejects
# ("no chainID in attributes"). Root cause = the EVM converter
# miniprot_GFF_2_EVM_alignment_GFF3.py was invoked as `python` (absent in the
# evm env). This driver regenerates protein_alignments.gff3 with `python3`,
# reuses the already-valid gene_predictions.gff3 (BRAKER, rescued models) and
# transcript_alignments.gff3 (PASA, ID= chains), then runs EVM 2.1.0.
# Inputs that exist are reused; protein alignments + partitions are rebuilt.
# Launch detached:
#   setsid bash -c '/mnt/data/.../run_evm_consensus.sh' >/dev/null 2>&1 &
# ============================================================================
set -uo pipefail
PROJECT=/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly
cd "$PROJECT"
source "$(conda info --base)/etc/profile.d/conda.sh"
RUNENV=genome_assembly
THREADS=8
REF="$PROJECT/annotation/refine"
EVM="$REF/evm"
GENOME="$PROJECT/final_assembly.fa"
NASAA="/mnt/data/genomes/wasp_nasonia/GCF_009193385.2_Nvit_psr_1.1_protein.faa"
LIN="$PROJECT/busco_downloads/lineages/hymenoptera_odb10"
BUSCODIR="$PROJECT/analysis/busco"
EVM_GFF="$EVM/evm.gff3"
mkdir -p "$EVM" "$PROJECT/logs"
TS=$(date +%Y%m%d_%H%M%S); LOG="$PROJECT/logs/evm_consensus_${TS}.log"
exec > >(tee -a "$LOG") 2>&1
echo "==== EVM consensus driver START $(date -Iseconds)  PID=$$  PPID=$PPID ===="
notify(){ PYTHONPATH="$PROJECT/denovo-assembly-core" python3 -m denovo_assembly_core.notify \
          --config "$PROJECT/project.yaml" "$1" "${2:-}" 2>>"$LOG" || true; }
run(){ conda run -n "$RUNENV" "$@"; }
have_busco(){ ls "$BUSCODIR/$1"/short_summary*.txt >/dev/null 2>&1; }
notify "[S.cam EVM] launched" "PID=$$ log=$LOG"

EVMHOME=$(conda run -n evm bash -c 'dirname $(dirname $(readlink -f $(command -v EVidenceModeler)))')
echo "EVMHOME=$EVMHOME"

# ---- inputs --------------------------------------------------------------
GP="$EVM/gene_predictions.gff3"
TA="$EVM/transcript_alignments.gff3"
WT="$EVM/weights.txt"
for f in "$GP" "$TA" "$WT"; do
  [ -s "$f" ] || { notify "[S.cam EVM] ABORT" "missing input $f (run model-refinement STAGE B first)"; exit 1; }
done

# (re)build protein alignments in EVM format (ID= chain IDs) via EVM's converter
[ -s "$EVM/miniprot.gff" ] || run miniprot -t "$THREADS" --gff "$GENOME" "$NASAA" > "$EVM/miniprot.gff" 2>>"$LOG"
PA="$EVM/protein_alignments.gff3"
MPCONV=$(find "$EVMHOME" -name 'miniprot_GFF_2_EVM_alignment_GFF3.py' 2>/dev/null | head -1)
if [ -n "$MPCONV" ] && conda run -n evm python3 "$MPCONV" "$EVM/miniprot.gff" > "$PA" 2>>"$LOG" && [ -s "$PA" ]; then
  echo "[evm] protein_alignments.gff3 rebuilt: $(grep -vc '^#' "$PA") records (chainID check: $(grep -c 'ID=MP' "$PA"))"
else
  notify "[S.cam EVM] protein evidence skipped" "converter unavailable; EVM on gene+transcript only"
  rm -f "$PA"
fi

# ---- run EVM (rebuild stale partitions) ----------------------------------
# Remove ALL prior EVM state incl. the __<id>-EVM_chckpts dir: EVM 2.1.0 skips
# partitioning/cmd-writing when those checkpoints exist, which leaves ParaFly
# with no evm_cmds file if the partition outputs were cleared.
rm -rf "$EVM"/spalangia.partitions "$EVM"/spalangia.* "$EVM"/__spalangia-EVM_chckpts "$EVM_GFF" 2>/dev/null || true
notify "[S.cam EVM] EVidenceModeler START" "CPU=$THREADS gene+protein+transcript"
( cd "$EVM" && conda run -n evm EVidenceModeler --sample_id spalangia --genome "$GENOME" \
    --weights "$WT" --gene_predictions "$GP" \
    $( [ -s "$PA" ] && echo --protein_alignments "$PA" ) \
    --transcript_alignments "$TA" \
    --segmentSize 100000 --overlapSize 10000 --CPU "$THREADS" 2>>"$LOG" )
rc=$?
out=$(ls "$EVM"/spalangia.EVM.gff3 "$EVM"/*.EVM.gff3 2>/dev/null | head -1)
if [ -n "$out" ] && [ -s "$out" ]; then
  cp "$out" "$EVM_GFF"
  run gffread "$EVM_GFF" -g "$GENOME" -y "$EVM/evm.aa" -S 2>>"$LOG" || true
  NGENE=$(awk -F'\t' '$3=="gene"' "$EVM_GFF" | wc -l)
  NAA=$(grep -c '^>' "$EVM/evm.aa" 2>/dev/null || echo 0)
  notify "[S.cam EVM] EVM DONE" "consensus: $EVM_GFF
genes=$NGENE  proteins=$NAA"
else
  notify "[S.cam EVM] EVM FAILED" "rc=$rc; no EVM.gff3 produced; see $LOG"; exit 1
fi

# ---- BUSCO on the consensus proteins -------------------------------------
if ! have_busco evm_prot; then
  notify "[S.cam EVM] BUSCO START" "evm_prot vs hymenoptera_odb10"
  run busco -i "$EVM/evm.aa" -l "$LIN" -m protein -c "$THREADS" --offline \
      --download_path "$PROJECT/busco_downloads" --out_path "$BUSCODIR" -o evm_prot -f 2>>"$LOG" || true
fi
notify "[S.cam EVM] FINISHED" "consensus + BUSCO complete
EVM   : $EVM_GFF
BUSCO : $(grep -h 'C:' "$BUSCODIR"/evm_prot/short_summary*.txt 2>/dev/null | head -1)
NOTE  : refresh AED cross-stage summary with run_model_refinement.sh STAGE C/D if desired."
echo "==== EVM consensus driver END $(date -Iseconds) ===="
