#!/usr/bin/env bash
# Add-only, evidence-gated graft of Tiberius ab-initio gene models into the
# EVM+PASA canonical set. Gate = BUSCO-rescue OR Nasonia homology (dup-protected).
# Drives annotation/scripts/vmc/merge_tib.py. Idempotent; re-runnable.
set -euo pipefail

PROJ="/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly"
ENV="genome_assembly"
RUN="conda run -n $ENV"
MT="$PROJ/annotation/scripts/vmc/merge_tib.py"
OUT="$PROJ/analysis/merge_tiberius"
mkdir -p "$OUT"

# ---- inputs ----
EVM_GFF="$PROJ/annotation/funannotate_evm_out/annotate_results/Spalangia_cameroni.gff3"
EVM_FAA="$PROJ/annotation/funannotate_evm_out/annotate_results/Spalangia_cameroni.proteins.fa"
EVM_BUSCO="$PROJ/analysis/busco/evm_pasa_prot/run_hymenoptera_odb10/full_table.tsv"
TIB_GTF="$PROJ/tiberius_athena_res/tiberius_insecta.gtf"
TIB_AA="$PROJ/tiberius_athena_res/tiberius_insecta.aa.fa"
TIB_BUSCO="$PROJ/analysis/busco/tiberius_prot/run_hymenoptera_odb10/full_table.tsv"
NAS_DMND="$PROJ/analysis/nasonia_compare/nasonia.dmnd"

# homology gate thresholds (script defaults -> "strong hit")
PID=30.0; QCOV=50.0; EVALUE=1e-10

ts(){ date +%Y-%m-%dT%H:%M:%S%z; }
echo "==== Tiberius graft START $(ts) ===="

# STEP 0: (a) normalize Tiberius GTF gene_id -> globally-unique id (per-contig ids
# are non-unique; merge_tib.py keys on the global id from the protein headers/BUSCO);
# (b) strip the uniform _np1212 contig suffix so contigs match the EVM canonical
# (funannotate) namespace -> overlap filtering works and the merged GFF3 is single-namespace.
echo "### STEP 0: normalize Tiberius GTF (global ids + strip _np1212)"
TIB_GTF_NORM="$OUT/tiberius_insecta.global.gtf"
python3 "$PROJ/annotation/scripts/vmc/normalize_tib_gtf.py" "$TIB_AA" "$TIB_GTF" "$OUT/.tib_norm_suffixed.gtf"
awk 'BEGIN{FS=OFS="\t"} /^#/{print;next} {sub(/_np1212$/,"",$1); print}' "$OUT/.tib_norm_suffixed.gtf" > "$TIB_GTF_NORM"
TIB_GTF="$TIB_GTF_NORM"   # use normalized, stripped GTF from here on

# STEP 1: gene-locus BEDs
echo "### STEP 1: beds"
python3 "$MT" beds --evm_gff "$EVM_GFF" --tib_gtf "$TIB_GTF" \
  --evm_bed "$OUT/evm.bed" --tib_bed "$OUT/tib.bed"

# STEP 2: candidates = Tiberius genes at loci EVM does NOT already cover (any-strand)
echo "### STEP 2: candidate loci (no EVM overlap)"
$RUN bedtools intersect -a "$OUT/tib.bed" -b "$OUT/evm.bed" -v \
  | cut -f4 | sort -u > "$OUT/cand_ids.txt"
echo "candidates (novel-locus Tiberius genes): $(wc -l < "$OUT/cand_ids.txt")"

# STEP 3: candidate proteins
echo "### STEP 3: candprot"
python3 "$MT" candprot --cand_ids "$OUT/cand_ids.txt" --tib_aa "$TIB_AA" \
  --out_faa "$OUT/cand.faa"

# STEP 4: homology arm -> DIAMOND blastp candidates vs Nasonia
echo "### STEP 4: diamond vs Nasonia"
$RUN diamond blastp --quiet -q "$OUT/cand.faa" -d "$NAS_DMND" \
  --max-target-seqs 1 --evalue 1e-5 -k 1 \
  -f 6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore qcovhsp \
  -o "$OUT/cand_vs_nasonia.tsv"
echo "diamond hit rows: $(wc -l < "$OUT/cand_vs_nasonia.tsv")"

# STEP 5: finalize -> apply BUSCO|homology gate, dup-protect, emit merged set
echo "### STEP 5: finalize (BUSCO + homology, no expression)"
python3 "$MT" finalize \
  --cand_ids "$OUT/cand_ids.txt" \
  --evm_busco "$EVM_BUSCO" --tib_busco "$TIB_BUSCO" \
  --diamond "$OUT/cand_vs_nasonia.tsv" \
  --evm_faa "$EVM_FAA" --tib_aa "$TIB_AA" \
  --evm_gff "$EVM_GFF" --tib_gtf "$TIB_GTF" \
  --merged_faa "$OUT/Spalangia_cameroni.merged.proteins.fa" \
  --merged_gff "$OUT/Spalangia_cameroni.merged.gff3" \
  --decisions "$OUT/graft_decisions.tsv" \
  --pid $PID --qcov $QCOV --evalue $EVALUE

# STEP 6: confirm the lift -> BUSCO on merged proteome
echo "### STEP 6: BUSCO merged proteome"
$RUN busco -i "$OUT/Spalangia_cameroni.merged.proteins.fa" -l hymenoptera_odb10 \
  -m proteins -c 8 -f --out_path "$PROJ/analysis/busco" -o merged_evm_tib_prot \
  --offline --download_path "$PROJ/busco_downloads" 2>&1 | grep -E "C:|Complete|Missing|done" || true

echo "==== Tiberius graft END $(ts) ===="
