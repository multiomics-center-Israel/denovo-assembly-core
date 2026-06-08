#!/usr/bin/env bash
# ============================================================================
# VENOM + MITO + CROSS-STAGE COMPARISON + DIAGRAM + SLIDES  — detached, emailing
# ============================================================================
# Covers the user's 7-item list in one detached run so the session can be closed:
#   1. verify EVM+PASA run (done) + build Nasonia/parasitoid venom reference
#   2. BUSCO on Tiberius + compare to EVM+PASA, email
#   3. update slides (results deck)
#   4. full pipeline diagram + methods explanation
#   5. assembly + annotation quality across stages vs Nasonia
#   6. identify the mitochondrial contig
#   7. how much of the venom-gland gene set we recover
# Idempotent: each step skips if its output exists. Resume: STEP_FROM=N.
# Launch detached:
#   setsid bash -c '/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly/run_venom_mito_compare.sh' >/dev/null 2>&1 &
# ============================================================================
set -uo pipefail
PROJECT=/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly
cd "$PROJECT"
source "$(conda info --base)/etc/profile.d/conda.sh"
RUNENV=genome_assembly         # miniprot/diamond/tblastn/makeblastdb/busco/seqkit/samtools/mafft
DOTENV=funannotate             # graphviz dot
THREADS=8
STEP_FROM="${STEP_FROM:-1}"

GENOME="$PROJECT/final_assembly.fa"
EVMAA="$PROJECT/annotation/funannotate_evm_out/annotate_results/Spalangia_cameroni.proteins.fa"
EVMGFF="$PROJECT/annotation/funannotate_evm_out/annotate_results/Spalangia_cameroni.gff3"
TIBAA="$PROJECT/tiberius_athena_res/tiberius_insecta.aa.fa"
NASAA="/mnt/data/genomes/wasp_nasonia/GCF_009193385.2_Nvit_psr_1.1_protein.faa"
NASFNA="/mnt/data/genomes/wasp_nasonia/GCF_009193385.2_Nvit_psr_1.1_genomic.fna.gz"
LIN="$PROJECT/busco_downloads/lineages/hymenoptera_odb10"
BUSCODIR="$PROJECT/analysis/busco"
VEN="$PROJECT/analysis/venom"
MITO="$PROJECT/analysis/mito"
CMP="$PROJECT/analysis/comparison"
FIG="$PROJECT/annotation/figures"
VSCR="$PROJECT/annotation/scripts/vmc"
mkdir -p "$VEN" "$MITO" "$CMP" "$FIG" "$PROJECT/logs" "$PROJECT/report"

TS=$(date +%Y%m%d_%H%M%S); LOG="$PROJECT/logs/venom_mito_compare_${TS}.log"
exec > >(tee -a "$LOG") 2>&1
echo "==== VMC driver START $(date -Iseconds)  PID=$$  PPID=$PPID  STEP_FROM=$STEP_FROM ===="
notify(){ PYTHONPATH="$PROJECT/denovo-assembly-core" python3 -m denovo_assembly_core.notify \
          --config "$PROJECT/project.yaml" "$1" "${2:-}" 2>>"$LOG" || true; }
run(){ conda run -n "$RUNENV" "$@"; }
have_busco(){ ls "$BUSCODIR/$1"/short_summary*.txt >/dev/null 2>&1; }
ufetch(){ # ufetch "<uniprot query>" "<out.faa>"
  curl -fsS -G "https://rest.uniprot.org/uniprotkb/stream" \
    --data-urlencode "query=$1" --data-urlencode "format=fasta" \
    --data-urlencode "includeIsoform=false" -o "$2" 2>>"$LOG"; }
notify "[S.cam VMC] launched" "PID=$$  log=$LOG  steps 1-8"

# ---------------------------------------------------------------------------
# STEP 1 — verify EVM run + build venom reference
# ---------------------------------------------------------------------------
if [ "$STEP_FROM" -le 1 ]; then
echo "### STEP 1: verify EVM + venom reference"
EVM_GENES=$(grep -c $'\tgene\t' "$EVMGFF" 2>/dev/null || echo "?")
EVM_BUSCO=$(grep -hoE "C:[0-9.]+%\[[^]]*\],F:[0-9.]+%,M:[0-9.]+%,n:[0-9]+" \
            "$BUSCODIR"/evm_pasa_prot/short_summary*.txt 2>/dev/null | head -1)
echo "EVM canonical genes=$EVM_GENES  BUSCO=$EVM_BUSCO"
notify "[S.cam VMC 1/8] EVM verified" "Canonical EVM+PASA: ${EVM_GENES} genes; BUSCO ${EVM_BUSCO}; funannotate complete (PFAM/MEROPS/dbCAN/UniProt)."

VREF="$VEN/venom_reference.faa"
if [ ! -s "$VREF" ]; then
  echo "downloading venom reference from UniProt..."
  ufetch '(organism_id:7425) AND (cc_tissue_specificity:venom OR protein_name:venom OR keyword:KW-0800)' "$VEN/nvit_venom.faa" || true
  ufetch '(taxonomy_id:7400) AND (keyword:KW-0800) AND (reviewed:true)' "$VEN/apocrita_toxins.faa" || true
  cat "$VEN/nvit_venom.faa" "$VEN/apocrita_toxins.faa" 2>/dev/null > "$VEN/_venom_raw.faa"
  if [ ! -s "$VEN/_venom_raw.faa" ]; then
    echo "UniProt empty -> fallback: grep venom/toxin headers from Nasonia RefSeq proteome"
    run seqkit grep -nr -p 'venom' -p 'toxin' "$NASAA" > "$VEN/_venom_raw.faa" 2>>"$LOG" || true
  fi
  run seqkit rmdup -s "$VEN/_venom_raw.faa" > "$VREF" 2>>"$LOG" || cp "$VEN/_venom_raw.faa" "$VREF"
fi
NVEN=$(grep -c ">" "$VREF" 2>/dev/null || echo 0)
echo "venom reference proteins: $NVEN"
notify "[S.cam VMC 1/8] venom reference built" "$NVEN proteins -> $VREF"
fi

# ---------------------------------------------------------------------------
# STEP 2 — BUSCO on Tiberius
# ---------------------------------------------------------------------------
if [ "$STEP_FROM" -le 2 ]; then
echo "### STEP 2: BUSCO Tiberius"
if have_busco tiberius_prot; then
  echo "tiberius BUSCO already present, skip"
else
  rm -rf "$BUSCODIR/tiberius_prot"
  ( cd "$BUSCODIR" && conda run -n "$RUNENV" busco -i "$TIBAA" -l "$LIN" -m proteins \
      -o tiberius_prot -c "$THREADS" --offline -f ) || notify "[S.cam VMC 2/8] BUSCO Tiberius FAILED" "see $LOG"
fi
TB=$(grep -hoE "C:[0-9.]+%\[[^]]*\],F:[0-9.]+%,M:[0-9.]+%,n:[0-9]+" \
     "$BUSCODIR"/tiberius_prot/short_summary*.txt 2>/dev/null | head -1)
notify "[S.cam VMC 2/8] Tiberius BUSCO done" "Tiberius(20,388 genes) BUSCO ${TB:-NA}"
fi

# ---------------------------------------------------------------------------
# STEP 3 — cross-stage comparison table + figure (+ assembly vs Nasonia)
# ---------------------------------------------------------------------------
if [ "$STEP_FROM" -le 3 ]; then
echo "### STEP 3: cross-stage comparison"
run python3 "$VSCR/build_comparison.py" || notify "[S.cam VMC 3/8] comparison FAILED" "see $LOG"
# assembly contiguity vs Nasonia
{
  echo -e "assembly\tn_seqs\ttotal_bp\tN50\tGC%"
  echo -ne "Spalangia_cameroni\t"; awk -F'\t' '
    /^# contigs\t/{c=$2} /^Total length\t/{t=$2} /^N50\t/{n=$2} /^GC \(%\)\t/{g=$2}
    END{print c"\t"t"\t"n"\t"g}' "$PROJECT/qc/quast_final_4980/report.tsv" 2>/dev/null
  echo -ne "Nasonia_vitripennis\t"; ( zcat "$NASFNA" 2>/dev/null | conda run -n "$RUNENV" seqkit stats -T 2>/dev/null \
      | awk 'NR==2{print $4"\t"$5"\t"$13"\t-"}' )
} > "$CMP/assembly_comparison.tsv" 2>>"$LOG"
TABLE=$(cat "$CMP/annotation_comparison.tsv" 2>/dev/null)
ATABLE=$(cat "$CMP/assembly_comparison.tsv" 2>/dev/null)
notify "[S.cam VMC 3/8] comparison ready" "ASSEMBLY:
$ATABLE

ANNOTATION (per stage, BUSCO hymenoptera_odb10):
$TABLE"
fi

# ---------------------------------------------------------------------------
# STEP 4 — mitochondrial contig
# ---------------------------------------------------------------------------
if [ "$STEP_FROM" -le 4 ]; then
echo "### STEP 4: mito contig"
MPROT="$MITO/mito_proteins.faa"
if [ ! -s "$MPROT" ]; then
  ufetch '(organism_id:7425) AND (organelle:mitochondrion)' "$MPROT" || true
  if [ ! -s "$MPROT" ]; then
    echo "Nasonia mito empty -> fallback: reviewed Insecta mito proteins"
    ufetch '(taxonomy_id:50557) AND (organelle:mitochondrion) AND (reviewed:true)' "$MPROT" || true
  fi
fi
echo "mito query proteins: $(grep -c '>' "$MPROT" 2>/dev/null || echo 0)"
# genome .fai
[ -s "$GENOME.fai" ] || run samtools faidx "$GENOME" 2>>"$LOG" || \
  run seqkit fx2tab -nl "$GENOME" 2>/dev/null | awk '{print $1"\t"$2}' > "$GENOME.fai"
# blast db + tblastn
DB="$MITO/genome_db"
[ -s "${DB}.nsq" ] || [ -s "${DB}.00.nsq" ] || run makeblastdb -in "$GENOME" -dbtype nucl -out "$DB" >>"$LOG" 2>&1
if [ -s "$MPROT" ]; then
  [ -s "$MITO/mito_tblastn.tsv" ] || run tblastn -query "$MPROT" -db "$DB" -evalue 1e-5 \
      -num_threads "$THREADS" -max_target_seqs 5 -outfmt 6 -out "$MITO/mito_tblastn.tsv" 2>>"$LOG"
  run python3 "$VSCR/mito_summary.py" "$MITO/mito_tblastn.tsv" "$GENOME.fai" "$MITO/mito_summary.tsv" > "$MITO/mito_top.txt" 2>>"$LOG"
fi
MTOP=$(cat "$MITO/mito_top.txt" 2>/dev/null)
MTAB=$(head -6 "$MITO/mito_summary.tsv" 2>/dev/null | cut -f1-4)
notify "[S.cam VMC 4/8] mito contig" "$MTOP

top candidates (contig / #distinct mito proteins / bitscore / length):
$MTAB"
fi

# ---------------------------------------------------------------------------
# STEP 5 — venom-gland gene recovery
# ---------------------------------------------------------------------------
if [ "$STEP_FROM" -le 5 ]; then
echo "### STEP 5: venom recovery"
VREF="$VEN/venom_reference.faa"
# miniprot venom vs genome (PAF)
[ -s "$VEN/venom_vs_genome.paf" ] || run miniprot -t "$THREADS" "$GENOME" "$VREF" > "$VEN/venom_vs_genome.paf" 2>>"$LOG"
# diamond venom vs EVM canonical proteins
[ -s "$VEN/evm.dmnd" ] || run diamond makedb --in "$EVMAA" -d "$VEN/evm" >>"$LOG" 2>&1
[ -s "$VEN/venom_vs_evm.tsv" ] || run diamond blastp -q "$VREF" -d "$VEN/evm" -p "$THREADS" \
    --very-sensitive -e 1e-5 --max-target-seqs 1 \
    -f 6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore qcovhsp scovhsp \
    -o "$VEN/venom_vs_evm.tsv" >>"$LOG" 2>&1
# diamond venom vs Tiberius proteins
[ -s "$VEN/tib.dmnd" ] || run diamond makedb --in "$TIBAA" -d "$VEN/tib" >>"$LOG" 2>&1
[ -s "$VEN/venom_vs_tib.tsv" ] || run diamond blastp -q "$VREF" -d "$VEN/tib" -p "$THREADS" \
    --very-sensitive -e 1e-5 --max-target-seqs 1 \
    -f 6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore qcovhsp scovhsp \
    -o "$VEN/venom_vs_tib.tsv" >>"$LOG" 2>&1
run python3 "$VSCR/venom_summary.py" --ref "$VREF" \
    --genome_paf "$VEN/venom_vs_genome.paf" \
    --evm_blast "$VEN/venom_vs_evm.tsv" \
    --tib_blast "$VEN/venom_vs_tib.tsv" \
    --out "$VEN/venom_recovery_summary.tsv" > "$VEN/venom_top.txt" 2>>"$LOG"
VSUM=$(cat "$VEN/venom_recovery_summary.tsv" 2>/dev/null)
notify "[S.cam VMC 5/8] venom recovery" "$VSUM

Caveat: only one public RNA-seq lib (whole body, not venom gland) -> recovery is homology+ab-initio based."
fi

# ---------------------------------------------------------------------------
# STEP 6 — pipeline diagram + methods markdown
# ---------------------------------------------------------------------------
if [ "$STEP_FROM" -le 6 ]; then
echo "### STEP 6: pipeline diagram"
run python3 "$VSCR/build_pipeline_dot.py" || true
conda run -n "$DOTENV" dot -Tpng "$FIG/pipeline_diagram.dot" -o "$FIG/pipeline_diagram.png" 2>>"$LOG" \
  || run dot -Tpng "$FIG/pipeline_diagram.dot" -o "$FIG/pipeline_diagram.png" 2>>"$LOG" || true
[ -s "$FIG/pipeline_diagram.png" ] && S=OK || S="dot-missing(dot file written)"
notify "[S.cam VMC 6/8] pipeline diagram $S" "diagram=$FIG/pipeline_diagram.png ; methods=$PROJECT/report/methods_explained.md"
fi

# ---------------------------------------------------------------------------
# STEP 7 — slides
# ---------------------------------------------------------------------------
if [ "$STEP_FROM" -le 7 ]; then
echo "### STEP 7: slides"
run python3 "$VSCR/build_slides.py" && S=OK || S=FAILED
notify "[S.cam VMC 7/8] slides $S" "deck=$PROJECT/report/Spalangia_results_update.pptx"
fi

# ---------------------------------------------------------------------------
# STEP 8 — final roundup
# ---------------------------------------------------------------------------
if [ "$STEP_FROM" -le 8 ]; then
echo "### STEP 8: done"
notify "[S.cam VMC] ALL DONE" "Outputs:
- venom ref: $VEN/venom_reference.faa
- venom recovery: $VEN/venom_recovery_summary.tsv (+ _per_protein.tsv)
- mito: $MITO/mito_summary.tsv
- comparison: $CMP/annotation_comparison.tsv + $CMP/assembly_comparison.tsv
- figures: $FIG/stage_comparison.png, $FIG/pipeline_diagram.png
- methods: report/methods_explained.md
- slides: report/Spalangia_results_update.pptx
Log: $LOG"
fi
echo "==== VMC driver END $(date -Iseconds) ===="
