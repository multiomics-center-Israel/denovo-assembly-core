#!/usr/bin/env bash
# Repeat track + per-type count tables (phase 7.15) from the RepeatMasker .out.
# Produces analysis/repeats/repeat_counts_by_{class,family}.tsv and
# tracks/repeats.{bed.gz,bb} for JBrowse. Idempotent + non-fatal.
set -uo pipefail
PROJECT="${1:?project dir}"
cd "$PROJECT"
OUT="$PROJECT/annotation/repeats/final_assembly.fa.out"
OD="$PROJECT/analysis/repeats"; TR="$PROJECT/annotation/tracks"
mkdir -p "$OD" "$TR"
GENOME_BP=650907546
[ -s "$OUT" ] || { echo "[repeats] $OUT missing — skipping"; exit 0; }

python3 - "$OUT" "$GENOME_BP" "$OD" "$TR" <<'PY'
import sys, collections
out, genome, od, tr = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
by_fam=collections.Counter(); bp_fam=collections.Counter()
by_cls=collections.Counter(); bp_cls=collections.Counter()
n=0
with open(out) as fh, open(f"{tr}/repeats.bed","w") as bed:
    for line in fh:
        p=line.split()
        if len(p)<11 or not p[0].isdigit(): continue
        chrom=p[4]; qb=int(p[5]); qe=int(p[6]); strand='+' if p[8]=='+' else '-'
        name=p[9]; cf=p[10]; cls=cf.split('/')[0]; ln=qe-qb+1
        by_fam[cf]+=1; bp_fam[cf]+=ln; by_cls[cls]+=1; bp_cls[cls]+=ln; n+=1
        bed.write(f"{chrom}\t{qb-1}\t{qe}\t{name}|{cf}\t{min(int(p[0]),1000)}\t{strand}\n")
def w(path,c,bpc,hdr):
    with open(path,"w") as f:
        f.write(hdr+"\n"); tn=tb=0
        for k,v in sorted(c.items(), key=lambda kv:-bpc[kv[0]]):
            f.write(f"{k}\t{v}\t{bpc[k]}\t{100*bpc[k]/genome:.4f}\n"); tn+=v; tb+=bpc[k]
        f.write(f"TOTAL\t{tn}\t{tb}\t{100*tb/genome:.4f}\n")
    return tb
tb=w(f"{od}/repeat_counts_by_class.tsv", by_cls, bp_cls, "repeat_class\tn_elements\tbp\tpct_genome")
w(f"{od}/repeat_counts_by_family.tsv", by_fam, bp_fam, "repeat_family\tn_elements\tbp\tpct_genome")
print(f"[repeats] {n} elements, {100*tb/genome:.2f}% of genome masked")

# figure
import matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as plt
items=sorted(by_cls.items(), key=lambda kv:-bp_cls[kv[0]])[:10]
fig,ax=plt.subplots(figsize=(9,4.5))
ax.bar([k for k,_ in items], [100*bp_cls[k]/genome for k,_ in items], color="#E76F51")
ax.set_ylabel("% of genome"); ax.set_title("Repeat content by class (RepeatMasker)",
              color="#1B3A5C", fontweight="bold"); plt.xticks(rotation=35,ha="right",fontsize=8)
import os; figdir=os.path.join(os.path.dirname(od),"..","annotation","figures")
figdir=os.path.normpath(os.path.join(od,"..","..","annotation","figures")); os.makedirs(figdir,exist_ok=True)
for e in ("png","svg"): fig.savefig(os.path.join(figdir,f"repeat_content.{e}"),dpi=300,bbox_inches="tight")
print("[repeats] figure ->", figdir)
PY

# JBrowse track
sort -k1,1 -k2,2n "$TR/repeats.bed" > "$TR/repeats.sorted.bed"
bgzip -f -c "$TR/repeats.sorted.bed" > "$TR/repeats.bed.gz" && tabix -f -p bed "$TR/repeats.bed.gz" && echo "[repeats] tabix track ok"
cut -f1-6 "$TR/repeats.sorted.bed" > /tmp/rep6.bed
bedToBigBed -type=bed6 /tmp/rep6.bed "$TR/genome.chrom.sizes" "$TR/repeats.bb" 2>/dev/null && echo "[repeats] BigBed ok" || echo "[repeats] BigBed warn"
rm -f "$TR/repeats.sorted.bed" "$TR/repeats.bed"
echo "[repeats] done"
