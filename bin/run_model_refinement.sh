#!/usr/bin/env bash
# ============================================================================
# MODEL REFINEMENT  — evidence-based single-exon rescue -> EVM consensus ->
#                     AED-like scoring -> cross-stage BUSCO/AED upgrade summary
# ============================================================================
# Detached + idempotent + graceful-degradation. Emails at every stage.
# STAGE A  rescue single-exon genes w/ RNA-seq coverage OR Nasonia protein hit,
#          re-BUSCO, re-compare vs Nasonia.            (solid; no deps)
# STAGE B  EVidenceModeler consensus (BRAKER+protein+transcript), gated on PASA
#          completing. Best-effort: any failure -> email + skip to summary.
# STAGE C  per-gene AED-like scoring for every available stage.
# STAGE D  cross-stage table + figure (does the gene set get better?).
#
# Launch detached:
#   setsid bash -c '/mnt/data/.../run_model_refinement.sh' >/dev/null 2>&1 &
# Re-runnable: each step skips when its output already exists.
# ============================================================================
set -uo pipefail
PROJECT=/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly
cd "$PROJECT"
source "$(conda info --base)/etc/profile.d/conda.sh"
RUNENV=genome_assembly
THREADS=16
BR="$PROJECT/annotation/braker"
REF="$PROJECT/annotation/refine"
SC="$PROJECT/annotation/scripts"
GENOME="$PROJECT/final_assembly.fa"
NASAA="/mnt/data/genomes/wasp_nasonia/GCF_009193385.2_Nvit_psr_1.1_protein.faa"
NASGFF="$PROJECT/analysis/nasonia_compare/GCF_009193385.2_Nvit_psr_1.1_genomic.gff"
BAM="$PROJECT/rnaseq/rnaseq_aligned.bam"
LIN="$PROJECT/busco_downloads/lineages/hymenoptera_odb10"
CFG="$(conda info --base)/envs/$RUNENV/config/braker3.cfg"
BUSCODIR="$PROJECT/analysis/busco"
FIG="$PROJECT/annotation/figures"
STATS="$PROJECT/analysis/stats"
mkdir -p "$REF" "$BUSCODIR" "$FIG" "$STATS" "$PROJECT/logs"
TS=$(date +%Y%m%d_%H%M%S)
LOG="$PROJECT/logs/model_refinement_${TS}.log"
exec > >(tee -a "$LOG") 2>&1
echo "==== model-refinement driver START $(date -Iseconds)  PID=$$  PPID=$PPID ===="

notify(){ PYTHONPATH="$PROJECT/denovo-assembly-core" python3 -m denovo_assembly_core.notify \
          --config "$PROJECT/project.yaml" "$1" "${2:-}" 2>>"$LOG" || true; }
run(){ conda run -n "$RUNENV" "$@"; }
have_busco(){ ls "$BUSCODIR/$1"/short_summary*.txt >/dev/null 2>&1; }

notify "[S.cam refine] driver launched" "PID=$$ host=$(hostname) log=$LOG
STAGE A rescue+BUSCO -> B EVM (after PASA) -> C AED -> D summary"

# diamond DB of the Nasonia proteome (shared)
NASDMND="$REF/nasonia.dmnd"
[ -s "$NASDMND" ] || run diamond makedb --in "$NASAA" -d "${NASDMND%.dmnd}" 2>>"$LOG"

# helper: AED-like scoring for one stage (label, gtf, proteins.aa, [precomputed diamond])
score_stage(){
  local label="$1" gtf="$2" aa="$3" dmd="${4:-}"
  local d="$REF/aed/$label"; mkdir -p "$d"
  [ -s "$gtf" ] || { echo "[score:$label] no gtf, skip"; return 0; }
  run python "$SC/refine_rescue.py" cdsbed --gtf "$gtf" \
      --out-bed "$d/cds.bed" --out-len "$d/genelen.tsv"
  sort -k1,1 -k2,2n "$d/cds.bed" > "$d/cds.sorted.bed"
  run bedtools coverage -a "$d/cds.sorted.bed" -b "$BAM" > "$d/cov.tsv" 2>>"$LOG" || true
  if [ -s "$PASABED" ]; then
    run bedtools coverage -a "$d/cds.sorted.bed" -b "$PASABED" > "$d/txcov.tsv" 2>>"$LOG" || true
  fi
  if [ -z "$dmd" ]; then
    dmd="$d/diamond.tsv"
    [ -s "$aa" ] && run diamond blastp -q "$aa" -d "${NASDMND%.dmnd}" -p "$THREADS" \
        -e 1e-5 -k 1 --quiet --outfmt 6 qseqid sseqid pident length evalue bitscore qcovhsp \
        -o "$dmd" 2>>"$LOG" || true
  fi
  run python "$SC/refine_score.py" aed --cov "$d/cov.tsv" --txcov "$d/txcov.tsv" \
      --diamond "$dmd" --genelen "$d/genelen.tsv" --out "$REF/aed_${label}.tsv"
}

# ===========================================================================
# STAGE A — evidence-based single-exon rescue
# ===========================================================================
notify "[S.cam refine] STAGE A START" "TSEBRA no-filter -> rescue single-exon w/ evidence -> BUSCO"

NOFILT="$REF/tsebra_nofilter.gtf"
if [ ! -s "$NOFILT" ]; then
  KEEP=""; [ -s "$BR/GeneMark-ETP/training.gtf" ] && KEEP="--keep_gtf $BR/GeneMark-ETP/training.gtf"
  run tsebra.py --gtf "$BR/augustus.hints.gtf,$BR/GeneMark-ETP/genemark.gtf" $KEEP \
      --hintfiles "$BR/hintsfile.gff" --cfg "$CFG" -o "$REF/tsebra_nofilter_raw.gtf" 2>>"$LOG"
  run rename_gtf.py --gtf "$REF/tsebra_nofilter_raw.gtf" --prefix rsc --out "$NOFILT" 2>>"$LOG" \
      || cp "$REF/tsebra_nofilter_raw.gtf" "$NOFILT"
fi

# classify + extract all-proteins for the no-filter set
run python "$SC/refine_rescue.py" classify --gtf "$NOFILT" \
    --out-genes "$REF/nofilter_genes.tsv" --out-bed "$REF/single_exon.bed" \
    --out-single-ids "$REF/single_ids.txt" --out-multi-ids "$REF/multi_ids.txt"
[ -s "$REF/nofilter.aa" ] || run gffread "$NOFILT" -g "$GENOME" -y "$REF/nofilter.aa" -S 2>>"$LOG"

# evidence 1: RNA-seq coverage over single-exon CDS
sort -k1,1 -k2,2n "$REF/single_exon.bed" > "$REF/single_exon.sorted.bed"
run bedtools coverage -a "$REF/single_exon.sorted.bed" -b "$BAM" > "$REF/single_cov.tsv" 2>>"$LOG"
# evidence 2: Nasonia protein homology (shared diamond on full no-filter set)
DMND_NOFILT="$REF/diamond_nofilter.tsv"
[ -s "$DMND_NOFILT" ] || run diamond blastp -q "$REF/nofilter.aa" -d "${NASDMND%.dmnd}" \
    -p "$THREADS" -e 1e-5 -k 1 --quiet --outfmt 6 qseqid sseqid pident length evalue bitscore qcovhsp \
    -o "$DMND_NOFILT" 2>>"$LOG"

# decide + subset
run python "$SC/refine_rescue.py" decide --coverage "$REF/single_cov.tsv" --diamond "$DMND_NOFILT" \
    --single-ids "$REF/single_ids.txt" --multi-ids "$REF/multi_ids.txt" \
    --report "$REF/rescue_report.tsv" --kept-ids "$REF/kept_gene_ids.txt" \
    --min-frac 0.5 --min-reads 5
run python "$SC/refine_rescue.py" subset --gtf "$NOFILT" \
    --kept-ids "$REF/kept_gene_ids.txt" --out "$REF/rescued.gtf"
run gffread "$REF/rescued.gtf" -g "$GENOME" -y "$REF/rescued.aa" -S 2>>"$LOG"
# proper gene/mRNA-grouped GFF3 (gffread flattens grouping; breaks funannotate/compare)
run python "$SC/refine_rescue.py" gff3 --gtf "$REF/rescued.gtf" --out "$REF/rescued.gff3"

# BUSCO on the rescued protein set
if ! have_busco rescued_prot; then
  run busco -i "$REF/rescued.aa" -l "$LIN" -m protein -c "$THREADS" --offline \
      --download_path "$PROJECT/busco_downloads" --out_path "$BUSCODIR" -o rescued_prot -f 2>>"$LOG" || true
fi
RESCUED_BUSCO=$(grep -h 'C:' "$BUSCODIR"/rescued_prot/short_summary*.txt 2>/dev/null | head -1)
PRIOR_BUSCO=$(grep -h 'C:' "$BUSCODIR"/braker_prot/short_summary*.txt 2>/dev/null | head -1)

# re-compare gene structure vs Nasonia
[ -s "$NASGFF" ] && run python "$SC/compare_gene_structure.py" \
    --a "Nasonia vitripennis:$NASGFF" --b "S. cameroni (rescued):$REF/rescued.gff3" \
    --out-fig "$FIG/nasonia_vs_rescued_structure.png" \
    --out-tsv "$STATS/structure_comparison_rescued.tsv" 2>>"$LOG" || true

NRESC=$(grep -c '	gene	' "$REF/rescued.gtf" 2>/dev/null || awk -F'\t' '$3=="gene"' "$REF/rescued.gtf" | wc -l)
notify "[S.cam refine] STAGE A DONE" "rescued gene set: $REF/rescued.{gtf,aa,gff3}
BUSCO rescued : $RESCUED_BUSCO
BUSCO braker  : $PRIOR_BUSCO
rescue_report : $REF/rescue_report.tsv"

# transcript-evidence BED for AED (PASA gmap valid alignments; may not exist yet)
PASABED="$REF/pasa_transcripts.bed"
build_pasabed(){
  local g="$PROJECT/analysis/utr/pasa/pasa.sqlite.valid_gmap_alignments.gff3"
  [ -s "$g" ] || g="$PROJECT/analysis/utr/pasa/gmap.spliced_alignments.gff3"
  [ -s "$g" ] || return 1
  awk -F'\t' '!/^#/ && NF>=8 {print $1"\t"$4-1"\t"$5}' "$g" | sort -k1,1 -k2,2n > "$PASABED"
}
build_pasabed || echo "[stageA] PASA transcript alignments not ready yet (AED will use RNA-seq+protein)"

# ===========================================================================
# STAGE B — EVidenceModeler consensus (gated on PASA finishing)  [best-effort]
# ===========================================================================
EVM_GFF="$REF/evm/evm.gff3"
run_evm(){
  notify "[S.cam refine] STAGE B: waiting for PASA" "EVM needs PASA transcript assemblies"
  # wait up to 10h for PASA assemblies (analysis-suite LONG-B)
  local pasa_gff="" t=0
  while [ $t -lt 600 ]; do
    pasa_gff=$(ls "$PROJECT/analysis/utr/pasa/"*pasa_assemblies.gff3 2>/dev/null | head -1)
    [ -n "$pasa_gff" ] && [ -s "$pasa_gff" ] && break
    # if PASA process is gone and still no assemblies, give up waiting
    if ! pgrep -f 'Launch_PASA_pipeline' >/dev/null 2>&1; then
      pasa_gff=$(ls "$PROJECT/analysis/utr/pasa/"*pasa_assemblies.gff3 2>/dev/null | head -1)
      [ -z "$pasa_gff" ] && pasa_gff="$PROJECT/analysis/utr/pasa/pasa.sqlite.valid_gmap_alignments.gff3"
      break
    fi
    sleep 60; t=$((t+1))
  done
  build_pasabed || true
  mkdir -p "$REF/evm"
  # EVM in its own env
  conda env list | grep -qE '^evm\s|/evm$' || mamba create -y -n evm -c bioconda -c conda-forge evidencemodeler 2>>"$LOG"
  # inputs
  # 1) gene predictions: rescued models, source col2 = BRAKER
  awk 'BEGIN{OFS="\t"} !/^#/ && NF>=8 {$2="BRAKER"; print} /^#/{print}' "$REF/rescued.gtf" > "$REF/evm/gene_predictions.gtf"
  # convert gtf->EVM gff3 if EVM ships the converter; else use rescued.gff3
  GP="$REF/evm/gene_predictions.gff3"
  if conda run -n evm bash -c 'command -v EVidenceModeler' >/dev/null 2>&1; then
    EVMHOME=$(conda run -n evm bash -c 'dirname $(dirname $(readlink -f $(command -v EVidenceModeler)))')
    CONV=$(find "$EVMHOME" -name 'misc' -type d 2>/dev/null | head -1)
    if [ -n "$CONV" ] && [ -s "$CONV/braker_GTF_to_EVM_GFF3.py" ]; then
      conda run -n evm python "$CONV/braker_GTF_to_EVM_GFF3.py" "$REF/evm/gene_predictions.gtf" > "$GP" 2>>"$LOG" || cp "$REF/rescued.gff3" "$GP"
    else
      awk 'BEGIN{OFS="\t"} !/^#/ && NF>=8 {$2="BRAKER"; print}' "$REF/rescued.gff3" > "$GP"
    fi
  else
    notify "[S.cam refine] STAGE B SKIP" "EVidenceModeler not installed; skipping consensus"; return 1
  fi
  # 2) protein alignments via miniprot -> EVM-format gff3.
  #    EVM's parse_evidence_chains REQUIRES an ID= chain identifier on each
  #    match record. miniprot's native GFF uses Parent=/Target= (no chainID),
  #    so EVM rejects it ("no chainID in attributes") — the old awk shortcut was
  #    NOT a valid fallback. Use EVM's own converter (under python3, not python,
  #    which is absent in the evm env); if it's unavailable, DROP protein
  #    evidence rather than feed EVM malformed records.
  [ -s "$REF/evm/miniprot.gff" ] || run miniprot -t "$THREADS" --gff "$GENOME" "$NASAA" > "$REF/evm/miniprot.gff" 2>>"$LOG"
  PA="$REF/evm/protein_alignments.gff3"
  local MPCONV
  MPCONV=$(find "$EVMHOME" -name 'miniprot_GFF_2_EVM_alignment_GFF3.py' 2>/dev/null | head -1)
  if [ -n "$MPCONV" ] && conda run -n evm python3 "$MPCONV" "$REF/evm/miniprot.gff" > "$PA" 2>>"$LOG" && [ -s "$PA" ]; then
    :
  else
    notify "[S.cam refine] EVM protein evidence skipped" "miniprot->EVM converter unavailable; EVM runs on gene+transcript only"
    rm -f "$PA"
  fi
  # 3) transcript alignments from PASA
  TA="$REF/evm/transcript_alignments.gff3"
  awk 'BEGIN{OFS="\t"} !/^#/ && NF>=8 {$2="assembler-pasa"; print}' "$pasa_gff" > "$TA" 2>>"$LOG" || true
  # weights
  printf 'ABINITIO_PREDICTION\tBRAKER\t5\nPROTEIN\tminiprot\t2\nTRANSCRIPT\tassembler-pasa\t8\n' > "$REF/evm/weights.txt"
  ( cd "$REF/evm" && conda run -n evm EVidenceModeler --sample_id spalangia --genome "$GENOME" \
      --weights "$REF/evm/weights.txt" --gene_predictions "$GP" \
      $( [ -s "$PA" ] && echo --protein_alignments "$PA" ) \
      $( [ -s "$TA" ] && echo --transcript_alignments "$TA" ) \
      --segmentSize 100000 --overlapSize 10000 --CPU "$THREADS" 2>>"$LOG" )
  local out
  out=$(ls "$REF/evm/"*.EVM.gff3 "$REF/evm/spalangia.EVM.gff3" 2>/dev/null | head -1)
  [ -n "$out" ] && cp "$out" "$EVM_GFF" && run gffread "$EVM_GFF" -g "$GENOME" -y "$REF/evm/evm.aa" -S 2>>"$LOG"
  [ -s "$EVM_GFF" ] || return 1
  if ! have_busco evm_prot; then
    run busco -i "$REF/evm/evm.aa" -l "$LIN" -m protein -c "$THREADS" --offline \
        --download_path "$PROJECT/busco_downloads" --out_path "$BUSCODIR" -o evm_prot -f 2>>"$LOG" || true
  fi
  return 0
}
if run_evm; then
  notify "[S.cam refine] STAGE B DONE (EVM)" "consensus: $EVM_GFF
BUSCO: $(grep -h 'C:' "$BUSCODIR"/evm_prot/short_summary*.txt 2>/dev/null | head -1)"
else
  notify "[S.cam refine] STAGE B incomplete" "EVM consensus skipped/failed; continuing to AED+summary (non-fatal)"
fi

# ===========================================================================
# STAGE C — per-gene AED-like scoring for every available stage
# ===========================================================================
notify "[S.cam refine] STAGE C START" "AED-like scoring per gene (RNA-seq + protein + transcript)"
build_pasabed || true
score_stage "braker_filtered" "$BR/braker.gtf" "$BR/braker.aa" ""
score_stage "rescued"         "$REF/rescued.gtf" "$REF/rescued.aa" "$DMND_NOFILT"
# EVM emits GFF3; the parser needs GTF (transcript_id/gene_id) -> convert first.
EVM_GTF="$REF/evm/evm.gtf"
[ -s "$EVM_GFF" ] && { [ -s "$EVM_GTF" ] && [ "$EVM_GTF" -nt "$EVM_GFF" ] || run gffread "$EVM_GFF" -T -o "$EVM_GTF" 2>>"$LOG"; \
                       score_stage "evm" "$EVM_GTF" "$REF/evm/evm.aa" ""; }

# ===========================================================================
# STAGE D — cross-stage upgrade summary (table + figure)
# ===========================================================================
MAN="$REF/stage_manifest.tsv"
{
  printf "Genome assembly\t%s\t\t\n" "$PROJECT/qc/busco_results"
  printf "Nasonia proteome\t%s\t\t\n" "$BUSCODIR/nasonia_prot"
  printf "BRAKER (filtered)\t%s\t%s\t%s\n" "$BUSCODIR/braker_prot" "$REF/aed_braker_filtered.tsv" "$BR/braker.gtf"
  printf "Rescued (single-exon)\t%s\t%s\t%s\n" "$BUSCODIR/rescued_prot" "$REF/aed_rescued.tsv" "$REF/rescued.gtf"
  [ -s "$EVM_GFF" ] && printf "EVM consensus\t%s\t%s\t%s\n" "$BUSCODIR/evm_prot" "$REF/aed_evm.tsv" "$REF/evm/evm.gtf"
} > "$MAN"
run python "$SC/refine_score.py" summary --manifest "$MAN" \
    --out-tsv "$STATS/refinement_summary.tsv" --out-fig "$FIG/refinement_summary.png"

SUMTXT=$(cat "$STATS/refinement_summary.tsv" 2>/dev/null)
notify "[S.cam refine] ALL DONE" "Cross-stage summary ($STATS/refinement_summary.tsv):
$SUMTXT

Figure: $FIG/refinement_summary.png
Rescued models: $REF/rescued.{gtf,aa,gff3}"
echo "==== model-refinement driver END $(date -Iseconds) ===="
