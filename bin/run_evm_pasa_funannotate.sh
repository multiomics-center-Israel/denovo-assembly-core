#!/usr/bin/env bash
# ============================================================================
# EVM -> PASA UTR/isoform update -> funannotate functional annotation
# ============================================================================
# Apples-to-apples counterpart of the rescued-set funannotate run, but on the
# EVidenceModeler consensus models (annotation/refine/evm/evm.gff3, 12,580
# genes). Two stages:
#   STAGE P  PASA annotation-comparison update: load EVM models into a COPY of
#            the existing pasa.sqlite (which already holds the transcript
#            alignments + pasa_assemblies, so we SKIP the ~5 h re-alignment),
#            run two annotation-compare rounds -> UTR- and isoform-aware gff3.
#   STAGE F  funannotate annotate on the PASA-updated EVM models (contigs
#            renamed <=16 chars, mirroring annotation/funannotate_in/).
# Detached + best-effort + emails each stage, matching the project's drivers.
# Launch:
#   setsid bash -c '/mnt/data/.../run_evm_pasa_funannotate.sh' >/dev/null 2>&1 &
# ============================================================================
set -uo pipefail
PROJECT=/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly
cd "$PROJECT"
source "$(conda info --base)/etc/profile.d/conda.sh"
RUNENV=genome_assembly
FUNENV=funannotate
THREADS=16
GENOME="$PROJECT/final_assembly.fa"                     # native names (ptg..._np1212)
GENOME16="$PROJECT/annotation/funannotate_in/genome.fa" # <=16-char names (ptg...)
EVM_GFF="$PROJECT/annotation/refine/evm/evm.gff3"
PASA_SRC="$PROJECT/analysis/utr/pasa"
OD="$PROJECT/analysis/utr/pasa_evm"
DB="$OD/pasa_evm.sqlite"
FUNIN="$PROJECT/annotation/funannotate_evm_in"
FUNOUT="$PROJECT/annotation/funannotate_evm_out"
export FUNANNOTATE_DB="$PROJECT/funannotate_db"
LIN="$PROJECT/busco_downloads/lineages/hymenoptera_odb10"
BUSCODIR="$PROJECT/analysis/busco"
mkdir -p "$OD" "$FUNIN" "$PROJECT/logs"
TS=$(date +%Y%m%d_%H%M%S); LOG="$PROJECT/logs/evm_pasa_funannotate_${TS}.log"
exec > >(tee -a "$LOG") 2>&1
echo "==== EVM->PASA->funannotate driver START $(date -Iseconds)  PID=$$  PPID=$PPID ===="
notify(){ PYTHONPATH="$PROJECT/denovo-assembly-core" python3 -m denovo_assembly_core.notify \
          --config "$PROJECT/project.yaml" "$1" "${2:-}" 2>>"$LOG" || true; }
run(){ conda run -n "$RUNENV" "$@"; }
fun(){ conda run -n "$FUNENV" "$@"; }
have_busco(){ ls "$BUSCODIR/$1"/short_summary*.txt >/dev/null 2>&1; }
notify "[S.cam EVM+PASA] launched" "PID=$$ log=$LOG
EVM models: $EVM_GFF (12,580 genes) -> PASA UTR/isoform update -> funannotate"

# sanity
for f in "$EVM_GFF" "$GENOME" "$GENOME16" "$PASA_SRC/pasa.sqlite" "$PASA_SRC/transcripts.fasta.clean"; do
  [ -s "$f" ] || { notify "[S.cam EVM+PASA] ABORT" "missing input: $f"; exit 1; }
done
PASAHOME="$(dirname "$(dirname "$(conda run -n $RUNENV command -v Launch_PASA_pipeline.pl)")")"
[ -d "$PASAHOME/scripts" ] || PASAHOME="$(find "$(conda info --base)/envs/$RUNENV/opt" -maxdepth 1 -iname 'pasa*' | head -1)"
echo "PASAHOME=$PASAHOME"
TX="$PASA_SRC/transcripts.fasta.clean"

# ===========================================================================
# STAGE P — PASA annotation-comparison update on EVM models
# ===========================================================================
# Reuse the existing alignments: copy the loaded sqlite so the costly
# alignAssembly (gmap of all transcripts + pasa_assemblies) is not repeated.
if [ ! -s "$DB" ]; then
  notify "[S.cam EVM+PASA] STAGE P: cloning PASA db" "copying pasa.sqlite (keeps transcript alignments)"
  cp "$PASA_SRC/pasa.sqlite" "$DB"
fi
ACFG="$OD/annotCompare.config"; printf 'DATABASE=%s\n' "$DB" > "$ACFG"

run_round(){  # $1 = round label, $2 = gff3 to load as current annotation
  local r="$1" gff="$2"
  notify "[S.cam EVM+PASA] PASA $r: load+compare START" "load $gff then annotation-compare"
  conda run -n "$RUNENV" "$PASAHOME/scripts/Load_Current_Gene_Annotations.dbi" \
     -c "$ACFG" -g "$GENOME" -P "$gff" >> "$OD/pasa_load_${r}.log" 2>&1 || echo "[pasa] $r load warn"
  conda run -n "$RUNENV" Launch_PASA_pipeline.pl -c "$ACFG" -A -g "$GENOME" \
     -t "$TX" --CPU "$THREADS" >> "$OD/pasa_update_${r}.log" 2>&1 || echo "[pasa] $r compare warn"
  ls -t "$OD"/*gene_structures_post_PASA_updates*.gff3 2>/dev/null | head -1
}

UPD=""
OUT1=$(run_round round1 "$EVM_GFF")
[ -n "$OUT1" ] && [ -s "$OUT1" ] && { cp "$OUT1" "$OD/evm_pasa_round1.gff3"; UPD="$OD/evm_pasa_round1.gff3"; }
if [ -n "$UPD" ]; then
  notify "[S.cam EVM+PASA] PASA round1 DONE" "updated models: $UPD ($(grep -c $'\tgene\t' "$UPD" 2>/dev/null) genes)"
  OUT2=$(run_round round2 "$UPD")
  [ -n "$OUT2" ] && [ -s "$OUT2" ] && { cp "$OUT2" "$OD/evm_pasa_round2.gff3"; UPD="$OD/evm_pasa_round2.gff3"; }
else
  notify "[S.cam EVM+PASA] PASA round1 FAILED" "no post_PASA_updates gff3; falling back to raw EVM models for funannotate"
  UPD="$EVM_GFF"
fi
FINAL_PASA="$OD/evm_pasa_updated.gff3"; cp "$UPD" "$FINAL_PASA"
NG=$(grep -c $'\tgene\t' "$FINAL_PASA" 2>/dev/null || echo 0)
NM=$(grep -c $'\tmRNA\t' "$FINAL_PASA" 2>/dev/null || echo 0)
notify "[S.cam EVM+PASA] STAGE P DONE" "PASA-updated EVM models: $FINAL_PASA
genes=$NG  transcripts=$NM (isoforms = transcripts-genes)"

# ===========================================================================
# STAGE F — funannotate annotate on PASA-updated EVM models
# ===========================================================================
# funannotate/tbl2asn reject IDs >16 chars: strip the uniform _np1212 suffix in
# the gff3 contig column (genome.fa already renamed in funannotate_in/).
GFF16="$FUNIN/evm_pasa.gff3"
awk 'BEGIN{OFS="\t"} /^#/{print;next} {sub(/_np1212$/,"",$1); print}' "$FINAL_PASA" > "$GFF16"
echo "[funannotate] renamed gff3: $GFF16 ($(grep -c $'\tgene\t' "$GFF16") genes)"

# busco db for funannotate (already present from the rescued run; guard anyway)
[ -d "$FUNANNOTATE_DB/hymenoptera" ] || FUNANNOTATE_DB="$FUNANNOTATE_DB" fun funannotate setup -b hymenoptera -d "$FUNANNOTATE_DB" >>"$LOG" 2>&1 || true
EGG=""; [ -s "$PROJECT/analysis/kegg/eggnog.emapper.annotations" ] && EGG="--eggnog $PROJECT/analysis/kegg/eggnog.emapper.annotations"

rm -rf "$FUNOUT"
notify "[S.cam EVM+PASA] STAGE F: funannotate annotate START" "input=$GFF16"
if FUNANNOTATE_DB="$FUNANNOTATE_DB" fun funannotate annotate --gff "$GFF16" --fasta "$GENOME16" \
     --species "Spalangia cameroni" --cpus 8 -o "$FUNOUT" --busco_db hymenoptera $EGG >>"$LOG" 2>&1; then
  RES="$FUNOUT/annotate_results"
  NGENE=$(awk -F'\t' '$3=="gene"' "$RES"/*.gff3 2>/dev/null | wc -l)
  notify "[S.cam EVM+PASA] STAGE F DONE" "functional annotation (EVM+PASA): $RES/
genes=$NGENE"
else
  notify "[S.cam EVM+PASA] STAGE F FAIL" "funannotate annotate failed; see $LOG"
fi

# ===========================================================================
# BUSCO + side-by-side summary vs the rescued-set funannotate run
# ===========================================================================
EVMPASA_AA="$FUNOUT/annotate_results/Spalangia_cameroni.proteins.fa"
if [ -s "$EVMPASA_AA" ] && ! have_busco evm_pasa_prot; then
  notify "[S.cam EVM+PASA] BUSCO START" "evm_pasa_prot vs hymenoptera_odb10"
  run busco -i "$EVMPASA_AA" -l "$LIN" -m protein -c 8 --offline \
      --download_path "$PROJECT/busco_downloads" --out_path "$BUSCODIR" -o evm_pasa_prot -f >>"$LOG" 2>&1 || true
fi
B_EVMPASA=$(grep -h 'C:' "$BUSCODIR"/evm_pasa_prot/short_summary*.txt 2>/dev/null | head -1)
B_RESCUED=$(grep -h 'C:' "$BUSCODIR"/braker_prot/short_summary*.txt 2>/dev/null | head -1)

# count isoforms + UTR coverage in the final set
PYSUM=$(python3 - "$FINAL_PASA" <<'PY'
import sys,re,collections
g=sys.argv[1]; genes=set(); tx=set(); utr=0; mrna_has_utr=set()
exon=collections.defaultdict(list); cds=collections.defaultdict(list); strand={}
for ln in open(g):
    if ln.startswith('#') or '\t' not in ln: continue
    p=ln.rstrip().split('\t')
    if len(p)<9: continue
    if p[2]=='gene': genes.add(re.search(r'ID=([^;]+)',p[8]).group(1) if re.search(r'ID=([^;]+)',p[8]) else ln)
    elif p[2]=='mRNA':
        m=re.search(r'ID=([^;]+)',p[8]);
        if m: tx.add(m.group(1))
    elif p[2] in ('exon','CDS'):
        m=re.search(r'Parent=([^;]+)',p[8])
        if m:
            (exon if p[2]=='exon' else cds)[m.group(1)].append((int(p[3]),int(p[4]))); strand[m.group(1)]=p[6]
for t in tx:
    e=sorted(exon.get(t,[])); c=sorted(cds.get(t,[]))
    if e and c and (e[0][0]<c[0][0] or e[-1][1]>c[-1][1]): mrna_has_utr.add(t)
print(f"genes={len(genes)} transcripts={len(tx)} isoforms_extra={max(0,len(tx)-len(genes))} mRNA_with_UTR={len(mrna_has_utr)}")
PY
)
notify "[S.cam EVM+PASA] ALL DONE" "EVM -> PASA UTR/isoform -> funannotate complete.
PASA-updated models : $FINAL_PASA
funannotate results : $FUNOUT/annotate_results/
$PYSUM
BUSCO EVM+PASA prot : $B_EVMPASA
BUSCO braker  prot  : $B_RESCUED
Compare vs rescued-set funannotate: $PROJECT/annotation/funannotate_out/annotate_results/"
echo "==== EVM->PASA->funannotate driver END $(date -Iseconds) ===="
