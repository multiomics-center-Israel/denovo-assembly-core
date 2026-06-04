#!/usr/bin/env bash
# Gene-structure comparison vs Nasonia (phase 7.23). Ensures the matched RefSeq
# Nasonia GFF (Nvit_psr_1.1), picks our best annotation (named -> braker), and
# emits the side-by-side figure + table. Idempotent + non-fatal.
set -uo pipefail
PROJECT="${1:?project dir}"
cd "$PROJECT"
OD="$PROJECT/analysis/nasonia_compare"; mkdir -p "$OD" "$PROJECT/analysis/stats"
GFF="$OD/GCF_009193385.2_Nvit_psr_1.1_genomic.gff"
if [ ! -s "$GFF" ]; then
  URL="https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/009/193/385/GCF_009193385.2_Nvit_psr_1.1/GCF_009193385.2_Nvit_psr_1.1_genomic.gff.gz"
  echo "[struct] downloading Nasonia GFF ..."
  curl -sL "$URL" -o "$GFF.gz" && gunzip -f "$GFF.gz" || { echo "[struct] download failed — skipping"; exit 0; }
fi
OURS="$PROJECT/analysis/naming/Spalangia_cameroni.annotated.gff3"
[ -s "$OURS" ] || OURS="$PROJECT/annotation/braker/braker.gff3"
[ -s "$OURS" ] || { echo "[struct] no annotation found — skipping"; exit 0; }
echo "[struct] comparing $OURS vs $GFF"
python "$PROJECT/annotation/scripts/compare_gene_structure.py" \
  --a "Nasonia vitripennis:$GFF" \
  --b "S. cameroni:$OURS" \
  --out-fig "$PROJECT/annotation/figures/nasonia_vs_spalangia_structure.png" \
  --out-tsv "$PROJECT/analysis/stats/structure_comparison.tsv"
echo "[struct] done"
