#!/usr/bin/env bash
# ncRNA annotation (phase 7.19): tRNAscan-SE (tRNA) + barrnap (rRNA) -> merged
# ncRNA.gff3 + per-class count table + JBrowse track. Idempotent + non-fatal.
set -uo pipefail
PROJECT="${1:?project dir}"
cd "$PROJECT"
OD="$PROJECT/analysis/ncrna"
TR="$PROJECT/annotation/tracks"
mkdir -p "$OD" "$TR"

# Prefer the unmasked genome; fall back to the soft-masked one used for BRAKER.
GENOME="$PROJECT/final_assembly.fa"
[ -s "$GENOME" ] || GENOME="$PROJECT/annotation/repeats/final_assembly.fa.masked"
echo "[ncrna] genome=$GENOME"

# ---- tRNAscan-SE (eukaryotic) ----
if [ ! -s "$OD/trna.gff" ]; then
  if command -v tRNAscan-SE >/dev/null 2>&1; then
    echo "[ncrna] tRNAscan-SE ..."
    tRNAscan-SE -E --thread 16 -o "$OD/trna.out" -f "$OD/trna.ss" \
      --gff "$OD/trna.gff" "$GENOME" 2> "$OD/trna.log" || echo "[ncrna] tRNAscan-SE warn"
  else
    echo "[ncrna] tRNAscan-SE MISSING — skipping tRNA"
  fi
fi

# ---- barrnap (rRNA, eukaryote) ----
if [ ! -s "$OD/rrna.gff" ]; then
  if command -v barrnap >/dev/null 2>&1; then
    echo "[ncrna] barrnap ..."
    barrnap --kingdom euk --threads 16 "$GENOME" > "$OD/rrna.gff" 2> "$OD/rrna.log" || echo "[ncrna] barrnap warn"
  else
    echo "[ncrna] barrnap MISSING — skipping rRNA"
  fi
fi

# ---- merge + classify + count + track ----
python3 - "$OD" "$TR" <<'PY'
import sys, re, collections, subprocess, os
od, tr = sys.argv[1], sys.argv[2]
rows = []   # (chrom, src, type, start, end, strand, attr, klass)
def add(chrom, src, typ, s, e, strand, attr, klass):
    rows.append((chrom, src, typ, int(s), int(e), strand, attr, klass))

trna = os.path.join(od, "trna.gff")
if os.path.exists(trna):
    for line in open(trna):
        if line.startswith("#") or "\t" not in line: continue
        p = line.rstrip("\n").split("\t")
        if len(p) < 9: continue
        iso = "tRNA"
        m = re.search(r"isotype=([A-Za-z]+)", p[8]) or re.search(r"tRNA-([A-Za-z]+)", p[8])
        klass = "tRNA-"+m.group(1) if m else "tRNA"
        add(p[0], "tRNAscan-SE", "tRNA", p[3], p[4], p[6], p[8], "tRNA")

rrna = os.path.join(od, "rrna.gff")
if os.path.exists(rrna):
    for line in open(rrna):
        if line.startswith("#") or "\t" not in line: continue
        p = line.rstrip("\n").split("\t")
        if len(p) < 9: continue
        m = re.search(r"Name=([^;]+)", p[8]); nm = m.group(1) if m else "rRNA"
        add(p[0], "barrnap", "rRNA", p[3], p[4], p[6], p[8], nm.split("_")[0])

# write merged GFF3
out = os.path.join(od, "ncRNA.gff3")
with open(out, "w") as f:
    f.write("##gff-version 3\n")
    for r in sorted(rows, key=lambda x:(x[0], x[3])):
        f.write("\t".join([r[0], r[1], r[2], str(r[3]), str(r[4]), ".", r[5], ".", r[6]])+"\n")

# count table by class
cnt = collections.Counter(r[7] for r in rows)
with open(os.path.join(od, "ncRNA_counts.tsv"), "w") as f:
    f.write("ncRNA_class\tcount\n")
    for k, c in sorted(cnt.items(), key=lambda kv:-kv[1]):
        f.write(f"{k}\t{c}\n")
    f.write(f"TOTAL\t{sum(cnt.values())}\n")
print(f"[ncrna] {len(rows)} ncRNA features; classes={dict(cnt)}")

# JBrowse track: sorted BED -> bgzip + tabix
bed = os.path.join(tr, "ncRNA.sorted.bed")
with open(bed, "w") as f:
    for r in sorted(rows, key=lambda x:(x[0], x[3])):
        f.write(f"{r[0]}\t{r[3]-1}\t{r[4]}\t{r[7]}\t0\t{r[5]}\n")
if rows:
    subprocess.run(f"bgzip -f {bed} && tabix -f -p bed {bed}.gz", shell=True)
    print(f"[ncrna] track -> {bed}.gz")

# figure
if rows:
    import matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as plt
    items = sorted(cnt.items(), key=lambda kv:-kv[1])[:15]
    fig, ax = plt.subplots(figsize=(9,4.5))
    ax.bar([k for k,_ in items], [c for _,c in items], color="#2A9D8F")
    ax.set_ylabel("count"); ax.set_title("ncRNA genes by class (tRNAscan-SE + barrnap)",
                  color="#1B3A5C", fontweight="bold")
    plt.xticks(rotation=40, ha="right", fontsize=8)
    figdir = os.path.join(os.path.dirname(od), "..", "annotation", "figures")
    figdir = os.path.normpath(os.path.join(od, "..", "..", "annotation", "figures"))
    os.makedirs(figdir, exist_ok=True)
    for ext in ("png","svg"):
        fig.savefig(os.path.join(figdir, f"ncrna_counts.{ext}"), dpi=300, bbox_inches="tight")
    print(f"[ncrna] figure -> {figdir}/ncrna_counts.png")
PY
echo "[ncrna] done"
