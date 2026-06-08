#!/usr/bin/env bash
# Full PASA UTR/isoform refinement (phase 7.13). Aligns TSA(+StringTie) transcripts,
# assembles, loads braker models, runs annotation-update -> UTR-aware gff3, then
# extracts UTR lengths -> analysis/utr/pasa_utr.tsv. Best-effort + non-fatal:
# if PASA can't complete, utr-merge falls back to the lightweight UTRs.
set -uo pipefail
PROJECT="${1:?project dir}"
cd "$PROJECT"
OD="$PROJECT/analysis/utr/pasa"; mkdir -p "$OD"; cd "$OD"

if ! command -v Launch_PASA_pipeline.pl >/dev/null 2>&1; then
  echo "[pasa] Launch_PASA_pipeline.pl MISSING — skipping (lightweight UTRs stand)"; exit 0
fi
PASAHOME="$(dirname "$(dirname "$(command -v Launch_PASA_pipeline.pl)")")"
[ -d "$PASAHOME/pasa_conf" ] || PASAHOME="$(find "$CONDA_PREFIX/opt" -maxdepth 1 -iname 'pasa*' 2>/dev/null | head -1)"
echo "[pasa] PASAHOME=$PASAHOME"

GENOME="$PROJECT/final_assembly.fa"
[ -s "$GENOME" ] || GENOME="$PROJECT/annotation/repeats/final_assembly.fa.masked"
BRAKER_GFF="$PROJECT/annotation/braker/braker.gff3"

# transcript evidence: TSA (de novo) + StringTie transcript fasta (genome-guided)
TX="$OD/transcripts.fasta"
if [ ! -s "$TX" ]; then
  cat "$PROJECT/rnaseq/spalangia_tsa.fasta" > "$TX" 2>/dev/null || true
  ST="$PROJECT/annotation/braker/GeneMark-ETP/rnaseq/stringtie/transcripts_merged.gff"
  if command -v gffread >/dev/null 2>&1 && [ -s "$ST" ]; then
    gffread -w "$OD/stringtie.fa" -g "$GENOME" "$ST" 2>/dev/null && cat "$OD/stringtie.fa" >> "$TX" || true
  fi
fi
[ -s "$TX" ] || { echo "[pasa] no transcript evidence — skipping"; exit 0; }
command -v seqclean >/dev/null 2>&1 && seqclean "$TX" >/dev/null 2>&1 || true
[ -s "$TX.clean" ] || cp "$TX" "$TX.clean"

# SQLite alignAssembly config
cfg="$OD/alignAssembly.config"
{ echo "DATABASE=$OD/pasa.sqlite"
  echo "validate_alignments_in_db.dbi:--MIN_PERCENT_ALIGNED=75"
  echo "validate_alignments_in_db.dbi:--MIN_AVG_PER_ID=90"
} > "$cfg"

ALN="minimap2"; command -v gmap >/dev/null 2>&1 && ALN="gmap"
if [ ! -s "$OD/pasa.sqlite.pasa_assemblies.gff3" ]; then
  echo "[pasa] alignAssembly ($ALN) ..."
  Launch_PASA_pipeline.pl -c "$cfg" -C -R -g "$GENOME" \
    -t "$TX.clean" --ALIGNERS "$ALN" --CPU 16 > "$OD/pasa_align.log" 2>&1 \
    || { echo "[pasa] alignAssembly failed (see pasa_align.log)"; exit 0; }
fi

# load braker models + one annotation-update round (adds UTRs/isoforms)
acfg="$OD/annotCompare.config"
{ echo "DATABASE=$OD/pasa.sqlite"; } > "$acfg"
"$PASAHOME/scripts/Load_Current_Gene_Annotations.dbi" -c "$acfg" -g "$GENOME" -P "$BRAKER_GFF" \
  > "$OD/pasa_load.log" 2>&1 || echo "[pasa] load warn"
Launch_PASA_pipeline.pl -c "$acfg" -A -g "$GENOME" -t "$TX.clean" --CPU 16 \
  > "$OD/pasa_update.log" 2>&1 || echo "[pasa] update warn"

# extract UTR lengths from the PASA-updated gff3
UPD="$(ls -t "$OD"/*gene_structures_post_PASA_updates*.gff3 2>/dev/null | head -1)"
if [ -n "$UPD" ] && [ -s "$UPD" ]; then
  cp "$UPD" "$PROJECT/analysis/utr/pasa_updated.gff3"
  python3 - "$UPD" "$PROJECT/analysis/utr/pasa_utr.tsv" <<'PY'
import sys, re, collections
gff, out = sys.argv[1], sys.argv[2]
mrna=collections.defaultdict(lambda:{"cds":[], "exon":[], "strand":"+"})
for line in open(gff):
    if line.startswith("#") or "\t" not in line: continue
    p=line.rstrip("\n").split("\t")
    if len(p)<9: continue
    m=re.search(r"Parent=([^;]+)", p[8])
    if not m: continue
    tid=m.group(1); d=mrna[tid]; d["strand"]=p[6]
    if p[2]=="CDS": d["cds"].append((int(p[3]),int(p[4])))
    if p[2]=="exon": d["exon"].append((int(p[3]),int(p[4])))
with open(out,"w") as f:
    f.write("mrna_id\tutr5_len\tutr3_len\n")
    for tid,d in mrna.items():
        if not d["cds"] or not d["exon"]: continue
        ex=sorted(d["exon"]); cds=sorted(d["cds"])
        cds_lo, cds_hi = cds[0][0], cds[-1][1]
        ex_lo, ex_hi = ex[0][0], ex[-1][1]
        left = max(0, cds_lo-ex_lo); right = max(0, ex_hi-cds_hi)
        u5,u3 = (left,right) if d["strand"]=="+" else (right,left)
        if u5 or u3: f.write(f"{tid}\t{u5}\t{u3}\n")
print("[pasa] UTR table written:", out)
PY
  echo "[pasa] done"
else
  echo "[pasa] no PASA-updated gff3 produced — lightweight UTRs stand"
fi
