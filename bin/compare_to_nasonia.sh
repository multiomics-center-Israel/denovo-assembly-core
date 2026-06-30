#!/usr/bin/env bash
set -euo pipefail

PROJECT=/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly
OUT=$PROJECT/comparison_to_nasonia
NASONIA=$PROJECT/short_reads_contem_index/GCF_009193385.2_Nvit_psr_1.1_genomic.fna
HIFIASM=$PROJECT/assembly/hifiasm/spalangia_asm.p_ctg.fa
FLYE=$PROJECT/assembly/flye/assembly.fasta
PPTX=$PROJECT/Spalangia_cameroni_assembly_plan.pptx
RESULTS=$PROJECT/RESULTS.md
THREADS=16

mkdir -p $OUT $PROJECT/logs
LOG=$PROJECT/logs/compare_to_nasonia_$(date +%Y%m%d_%H%M%S).log
exec > >(tee -a "$LOG") 2>&1
echo $$ > $OUT/compare.pid
echo "==== compare_to_nasonia.sh started $(date -Iseconds) ===="
echo "PID=$$  LOG=$LOG"

source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate genome_assembly

# ─────────────────────────────────────────────────────────────────────────────
# Step 1: Wait for Phase 4 completion
# ─────────────────────────────────────────────────────────────────────────────
echo "==== Step 1: Wait for Phase 4 (phase4_decontam = completed) ===="
TICK=0
while true; do
    STATUS=$(jq -r '.["phase4_decontam"].status // "missing"' $PROJECT/pipeline_status.json 2>/dev/null || echo "missing")
    if [ "$STATUS" = "completed" ]; then
        echo "[$(date +%H:%M:%S)] Phase 4 completed."
        break
    fi
    if [ $((TICK % 10)) -eq 0 ]; then
        echo "[$(date +%H:%M:%S)] waiting on Phase 4 (current status: $STATUS)"
    fi
    TICK=$((TICK+1))
    sleep 60
done

# ─────────────────────────────────────────────────────────────────────────────
# Step 2: Install Mash if missing
# ─────────────────────────────────────────────────────────────────────────────
echo "==== Step 2: Ensure Mash is installed ===="
if ! command -v mash >/dev/null 2>&1; then
    if command -v mamba >/dev/null 2>&1; then
        mamba install -y -n genome_assembly -c bioconda mash 2>&1 | tail -10
    else
        conda install -y -n genome_assembly -c bioconda mash 2>&1 | tail -10
    fi
    conda activate genome_assembly
fi
echo "mash: $(which mash)  $(mash --version 2>&1 | head -1)"

# ─────────────────────────────────────────────────────────────────────────────
# Step 3: minimap2 -x asm20 (hifiasm + Flye vs Nasonia)
# ─────────────────────────────────────────────────────────────────────────────
echo "==== Step 3: minimap2 -x asm20 vs Nasonia ===="
echo "[$(date +%H:%M:%S)] hifiasm vs Nasonia..."
minimap2 -x asm20 -t $THREADS --secondary=no \
    "$NASONIA" "$HIFIASM" \
    > $OUT/hifiasm_vs_nasonia.paf 2> $OUT/mm2_hifiasm.log
echo "    hifiasm PAF: $(wc -l < $OUT/hifiasm_vs_nasonia.paf) records"

echo "[$(date +%H:%M:%S)] Flye vs Nasonia..."
minimap2 -x asm20 -t $THREADS --secondary=no \
    "$NASONIA" "$FLYE" \
    > $OUT/flye_vs_nasonia.paf 2> $OUT/mm2_flye.log
echo "    Flye PAF:    $(wc -l < $OUT/flye_vs_nasonia.paf) records"

# ─────────────────────────────────────────────────────────────────────────────
# Step 4: PAF stats (Python)
# ─────────────────────────────────────────────────────────────────────────────
echo "==== Step 4: Compute %aligned + %identity from PAFs ===="
python3 - "$OUT" "$HIFIASM" "$FLYE" > $OUT/paf_stats.tsv <<'PYEOF'
import sys, os, subprocess

OUT, HIFIASM, FLYE = sys.argv[1:4]

def asm_total_bp(path):
    total = 0
    with open(path) as fh:
        for line in fh:
            if line.startswith('>'): continue
            total += len(line.strip())
    return total

def paf_stats(paf):
    """Returns dict with: q_with_hits, q_total_bp_with_hits, aligned_bp_merged,
    total_matches, total_alen, largest_block."""
    queries = {}
    with open(paf) as fh:
        for line in fh:
            f = line.rstrip('\n').split('\t')
            qname, qlen = f[0], int(f[1])
            qs, qe = int(f[2]), int(f[3])
            matches, alen = int(f[9]), int(f[10])
            if qname not in queries:
                queries[qname] = [qlen, []]
            queries[qname][1].append((qs, qe, matches, alen))
    q_total = sum(v[0] for v in queries.values())
    aligned_merged = 0
    total_matches = total_alen = largest = 0
    for qname, (qlen, hits) in queries.items():
        ivs = sorted((qs, qe) for qs, qe, _, _ in hits)
        merged = []
        for s, e in ivs:
            if merged and s <= merged[-1][1]:
                merged[-1][1] = max(merged[-1][1], e)
            else:
                merged.append([s, e])
        aligned_merged += sum(e - s for s, e in merged)
        for _, _, m, a in hits:
            total_matches += m
            total_alen += a
            if a > largest:
                largest = a
    return {
        'q_with_hits': len(queries),
        'q_total_bp_with_hits': q_total,
        'aligned_bp_merged': aligned_merged,
        'total_matches': total_matches,
        'total_alen': total_alen,
        'largest_block': largest,
    }

print("metric\thifiasm_vs_nasonia\tflye_vs_nasonia")
hifi_total = asm_total_bp(HIFIASM)
flye_total = asm_total_bp(FLYE)

stats_h = paf_stats(f"{OUT}/hifiasm_vs_nasonia.paf")
stats_f = paf_stats(f"{OUT}/flye_vs_nasonia.paf")
stats_h['asm_total_bp'] = hifi_total
stats_f['asm_total_bp'] = flye_total

def pct(x, y):
    return f"{100.0*x/y:.2f}%" if y else "NA"

def avg_id(s):
    return f"{100.0*s['total_matches']/s['total_alen']:.4f}%" if s['total_alen'] else "NA"

rows = [
    ("Assembly total bp",                       f"{hifi_total:,}",                f"{flye_total:,}"),
    ("Contigs with any hit vs Nasonia",         f"{stats_h['q_with_hits']:,}",    f"{stats_f['q_with_hits']:,}"),
    ("Sum of those contig lengths (bp)",        f"{stats_h['q_total_bp_with_hits']:,}", f"{stats_f['q_total_bp_with_hits']:,}"),
    ("Aligned bp (query-side, merged)",         f"{stats_h['aligned_bp_merged']:,}", f"{stats_f['aligned_bp_merged']:,}"),
    ("% assembly aligned to Nasonia",           pct(stats_h['aligned_bp_merged'], stats_h['asm_total_bp']),
                                                pct(stats_f['aligned_bp_merged'], stats_f['asm_total_bp'])),
    ("Avg identity over alignment blocks",      avg_id(stats_h),                  avg_id(stats_f)),
    ("Largest single alignment block (bp)",     f"{stats_h['largest_block']:,}",  f"{stats_f['largest_block']:,}"),
]
for name, h, f in rows:
    print(f"{name}\t{h}\t{f}")
PYEOF

echo "--- paf_stats.tsv ---"
cat $OUT/paf_stats.tsv

# ─────────────────────────────────────────────────────────────────────────────
# Step 5: Mash sketch + dist
# ─────────────────────────────────────────────────────────────────────────────
echo "==== Step 5: Mash sketch + pairwise distances ===="
mash sketch -k 21 -s 100000 -p $THREADS -o $OUT/sketch_hifiasm "$HIFIASM" 2>&1 | tail -3
mash sketch -k 21 -s 100000 -p $THREADS -o $OUT/sketch_flye    "$FLYE"    2>&1 | tail -3
mash sketch -k 21 -s 100000 -p $THREADS -o $OUT/sketch_nasonia "$NASONIA" 2>&1 | tail -3

{
  echo -e "reference\tquery\tmash_distance\tp_value\tshared_hashes"
  mash dist $OUT/sketch_nasonia.msh  $OUT/sketch_hifiasm.msh
  mash dist $OUT/sketch_nasonia.msh  $OUT/sketch_flye.msh
  mash dist $OUT/sketch_hifiasm.msh  $OUT/sketch_flye.msh
} > $OUT/mash_dist.tsv
echo "--- mash_dist.tsv ---"
cat $OUT/mash_dist.tsv

# ─────────────────────────────────────────────────────────────────────────────
# Step 6: SUMMARY.md
# ─────────────────────────────────────────────────────────────────────────────
echo "==== Step 6: Write SUMMARY.md ===="
python3 - "$OUT" > $OUT/SUMMARY.md <<'PYEOF'
import sys, os, datetime

OUT = sys.argv[1]

def read_tsv(path):
    with open(path) as fh:
        return [line.rstrip('\n').split('\t') for line in fh if line.strip()]

paf = read_tsv(f"{OUT}/paf_stats.tsv")
mash = read_tsv(f"{OUT}/mash_dist.tsv")

now = datetime.datetime.now().isoformat(timespec='seconds')

print(f"# Spalangia cameroni assemblies vs Nasonia vitripennis")
print(f"\n_Generated: {now}_\n")
print("Reference: `GCF_009193385.2_Nvit_psr_1.1` (Nasonia vitripennis, 297 Mb, 436 seqs, chromosome-scale)\n")

print("## minimap2 -x asm20\n")
print("| Metric | hifiasm vs Nasonia | Flye vs Nasonia |")
print("|---|---|---|")
for row in paf[1:]:
    print("| " + " | ".join(row) + " |")
print()

print("## Mash distance (k=21, s=100000)\n")
print("| Reference | Query | Mash distance | p-value | Shared hashes |")
print("|---|---|---|---|---|")
for row in mash[1:]:
    ref = os.path.basename(row[0])
    qry = os.path.basename(row[1])
    print(f"| {ref} | {qry} | {row[2]} | {row[3]} | {row[4]} |")
print()

print("## How to read these numbers\n")
print("- **% assembly aligned to Nasonia** is computed on the *query side* (assembly contigs), with per-contig"
      " alignment intervals merged so multi-mappers don't double-count. At family-level divergence"
      " (~100–150 My) most of the genome — intergenic, intronic, repetitive — is not expected to align,"
      " so a value in the 30–60 % range is the realistic ceiling.")
print("- **Avg identity over alignment blocks** is the per-block weighted identity *where minimap2 found a"
      " hit at all* — this is conserved coding/exonic sequence and reflects long-term evolutionary divergence"
      " (≈70–85 % for hymenoptera at this distance is normal).")
print("- **Largest single alignment block** is a proxy for syntenic conservation — large blocks indicate"
      " preserved chromosome neighborhoods.")
print("- **Mash distance** is k-mer Jaccard converted to a divergence estimate. ~0 = identical, 0.05 ≈ species,"
      " 0.1–0.3 = family-level, >0.3 = unrelated. Spalangia–Nasonia should sit in the family-level range.")
print()
print("> For finer-grained synteny analysis, render `hifiasm_vs_nasonia.paf` in D-GENIES, or run GENESPACE"
      " post-annotation (Phase 7+).")
PYEOF

echo "--- SUMMARY.md head ---"
head -50 $OUT/SUMMARY.md

# ─────────────────────────────────────────────────────────────────────────────
# Step 7: Append section to RESULTS.md
# ─────────────────────────────────────────────────────────────────────────────
echo "==== Step 7: Append to RESULTS.md ===="
{
  echo
  echo "## Comparison to Nasonia vitripennis (post-Phase-4)"
  echo
  echo "_Reference: GCF_009193385.2_Nvit_psr_1.1 — 297 Mb chromosome-scale_"
  echo
  echo "### minimap2 -x asm20"
  echo
  echo "| Metric | hifiasm vs Nasonia | Flye vs Nasonia |"
  echo "|---|---|---|"
  tail -n +2 $OUT/paf_stats.tsv | awk -F'\t' '{printf "| %s | %s | %s |\n", $1, $2, $3}'
  echo
  echo "### Mash distance (k=21, s=100000)"
  echo
  echo "| Reference | Query | Mash distance | p-value | Shared hashes |"
  echo "|---|---|---|---|---|"
  tail -n +2 $OUT/mash_dist.tsv | awk -F'\t' '{
    n=split($1,r,"/"); ref=r[n];
    n=split($2,q,"/"); qry=q[n];
    printf "| %s | %s | %s | %s | %s |\n", ref, qry, $3, $4, $5
  }'
  echo
  echo "Full report: \`comparison_to_nasonia/SUMMARY.md\`"
} >> $RESULTS
echo "appended."

# ─────────────────────────────────────────────────────────────────────────────
# Step 8: Append slide(s) to PPTX
# ─────────────────────────────────────────────────────────────────────────────
echo "==== Step 8: Append slides to PPTX ===="
python3 - "$PPTX" "$OUT" <<'PYEOF'
import sys, os
PPTX, OUT = sys.argv[1:3]

try:
    from pptx import Presentation
    from pptx.util import Inches, Pt
    from pptx.dml.color import RGBColor
except ImportError:
    print("python-pptx not installed; skipping slide update.")
    sys.exit(0)

if not os.path.exists(PPTX):
    print(f"PPTX not found at {PPTX}; skipping.")
    sys.exit(0)

def read_tsv(p):
    with open(p) as fh:
        return [l.rstrip('\n').split('\t') for l in fh if l.strip()]

paf = read_tsv(f"{OUT}/paf_stats.tsv")
mash = read_tsv(f"{OUT}/mash_dist.tsv")

prs = Presentation(PPTX)
blank = prs.slide_layouts[6]  # blank layout

# --- Slide 1: minimap2 vs Nasonia table ---
slide = prs.slides.add_slide(blank)
tx = slide.shapes.add_textbox(Inches(0.4), Inches(0.25), Inches(12.5), Inches(0.7))
tf = tx.text_frame
p = tf.paragraphs[0]
p.text = "Spalangia assemblies vs Nasonia vitripennis — minimap2 -x asm20"
p.runs[0].font.size = Pt(24)
p.runs[0].font.bold = True

rows = len(paf)
cols = len(paf[0])
tbl_shape = slide.shapes.add_table(rows, cols,
    Inches(0.4), Inches(1.1), Inches(12.5), Inches(rows * 0.4))
tbl = tbl_shape.table
for r, row in enumerate(paf):
    for c, val in enumerate(row):
        cell = tbl.cell(r, c)
        cell.text = val
        for para in cell.text_frame.paragraphs:
            for run in para.runs:
                run.font.size = Pt(12)
                if r == 0:
                    run.font.bold = True

# Tag the slide so future re-runs can recognise it
slide.shapes.title  # noqa - just touch
slide_note = slide.notes_slide
slide_note.notes_text_frame.text = "AUTO:comparison_to_nasonia"

# --- Slide 2: Mash distance ---
slide2 = prs.slides.add_slide(blank)
tx = slide2.shapes.add_textbox(Inches(0.4), Inches(0.25), Inches(12.5), Inches(0.7))
tf = tx.text_frame
p = tf.paragraphs[0]
p.text = "Mash distance (k=21, s=100000) — Spalangia vs Nasonia"
p.runs[0].font.size = Pt(24)
p.runs[0].font.bold = True

rows = len(mash)
cols = len(mash[0])
tbl_shape = slide2.shapes.add_table(rows, cols,
    Inches(0.4), Inches(1.1), Inches(12.5), Inches(rows * 0.45))
tbl = tbl_shape.table
for r, row in enumerate(mash):
    for c, val in enumerate(row):
        cell = tbl.cell(r, c)
        # Trim path prefix on first two cols (filenames)
        if r > 0 and c < 2:
            val = os.path.basename(val)
        cell.text = val
        for para in cell.text_frame.paragraphs:
            for run in para.runs:
                run.font.size = Pt(12)
                if r == 0:
                    run.font.bold = True

note_box = slide2.shapes.add_textbox(Inches(0.4), Inches(rows * 0.45 + 1.5),
                                     Inches(12.5), Inches(2.0))
nf = note_box.text_frame
nf.word_wrap = True
nf.text = ("Mash distance ≈ 1 − ANI for the shared-k-mer fraction. "
           "Spalangia–Nasonia diverged ~100–150 Mya (different Pteromalidae subfamilies); "
           "expect family-level distances (0.1–0.3). Same-genome distances should be ~0.")
for para in nf.paragraphs:
    for run in para.runs:
        run.font.size = Pt(12)

slide2.notes_slide.notes_text_frame.text = "AUTO:comparison_to_nasonia"

prs.save(PPTX)
print(f"Appended 2 slides to {PPTX}")
PYEOF

echo "==== compare_to_nasonia.sh completed $(date -Iseconds) ===="
echo
echo "Outputs:"
echo "  $OUT/SUMMARY.md"
echo "  $OUT/paf_stats.tsv"
echo "  $OUT/mash_dist.tsv"
echo "  $OUT/hifiasm_vs_nasonia.paf  (for D-GENIES dotplot)"
echo "  $OUT/flye_vs_nasonia.paf"
echo "  RESULTS.md  (appended)"
echo "  $PPTX  (2 slides appended)"
