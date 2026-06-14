#!/bin/bash
#$ -S /bin/bash
#$ -N mito_scan
#$ -cwd
#$ -j y
#$ -e mito_scan.err
#$ -o mito_scan.log
#$ -q bioinfo.q
#$ -pe shared 16
# ============================================================
# Step 30: Recovery scan of DROPPED contigs — is any of them mitochondrial?
# ============================================================
# Michal's supervisor asked: go back over every contig discarded during
# assembly (BlobTools + purge_dups + Tiara) and BLAST them to make sure we
# did not throw away a real mitochondrial contig.
#
# CONTEXT (from 01.assembly_workflow doc, §23 + script 26b):
#   - purge_dups flagged a 2,415 bp "mito fragment" (ptg000037l) as JUNK; it
#     was rescued and then BLAST (26b) showed it is actually a PLASTID IR
#     fragment, NOT mito. So as of now the assembly has 0 mito sequence.
#   - The earlier checks were narrow: BlobTools' 2 removed contigs were never
#     tested for mito (mito genes can spuriously hit bacteria due to
#     endosymbiotic origin), and the full purge_dups removed set was only
#     BLASTed against the chloroplast — never against mito references.
#
# THIS SCRIPT:
#   1. Collects every contig dropped at each stage into one labelled multifasta
#   2. Annotates each with length / GC / ONT cov / Illumina cov / BlobTools taxonomy
#      (joined from the existing summary_full.tsv)
#   3. diamond blastx vs nr  -> decisive protein-level ID (mito genes + taxon)
#   4. blastn vs the 8 Coelastrella nuclear genomes -> "is it just nuclear/haplotig?"
#   5. blastn vs downloaded green-algal MITOCHONDRIAL references -> targeted confirmation
#   6. Writes a single verdict table: dropped_contigs_verdict.tsv
#
# Outputs (in $WORK):
#   dropped_all.fa                 - all dropped contigs, original names + stage tag
#   dropped_contigs_annotation.tsv - length/GC/cov/taxonomy per contig
#   diamond_nr.tsv                 - diamond blastx vs nr (full)
#   blastn_vs_coelastrella.tsv     - vs 8 nuclear genomes
#   blastn_vs_mito_refs.tsv        - vs green-algal mito genomes
#   dropped_contigs_verdict.tsv    - FINAL summary + verdict per contig
# ============================================================
# NOTE: no 'set -u' — some conda activate.d scripts (binutils) reference unbound
# vars and would abort the run. We guard conda activations with 'set +u' anyway.
set -eo pipefail

# ------------------------------------------------------------
# Paths  (edit ONLY if a file moved)
# ------------------------------------------------------------
PROJ=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing

PILON=$PROJ/05.Assembly/04.polishing/02.pilon/Coelastrella_pilon.fasta                 # 64 contigs (BlobTools input)
DECON=$PROJ/05.Assembly/06.decontamination/Coelastrella_decontaminated.fasta           # 62 contigs (BlobTools output)
SUMMARY=$PROJ/05.Assembly/06.decontamination/summary_full.tsv                          # per-contig gc/len/cov/taxonomy
HAP=$PROJ/07.purge_dups/hap.fa                                                         # purge_dups removed set
RESCUE_LIST=$PROJ/07.purge_dups/rescue_contigs.txt                                     # contigs rescued back in
POLYPOLISH=$PROJ/09.polypolish/Coelastrella_polypolish_pypolca_final.fa                # 29 contigs (Tiara input)
FINAL=$PROJ/09.polypolish/Coelastrella_FINAL.fa                                        # 28 contigs (Tiara output)

NR_DMND=/gpfs0/system/conda/DataBases/Blast/NR/DIAMOND/NR.dmnd
COEL_GENOMES=/gpfs0/bioinfo/databases/Centrifuge/db_nt_2026/extra_genomes/coelastrella/coelastrella_all_genomes.fna

WORK=$PROJ/12.mito_recovery_scan
THREADS=16

# conda envs already used elsewhere in this project
CONDA_SH=/gpfs0/system/conda/miniconda2/etc/profile.d/conda.sh
ENV_SEQKIT=/gpfs0/system/conda/miniconda2/envs/Mamba/envs/seqkit
ENV_BLAST=/gpfs0/system/conda/miniconda2/envs/Omics_QC          # has blastn/makeblastdb (+ usually efetch)
ENV_DIAMOND=/gpfs0/system/conda/miniconda2/envs/Blast   # diamond lives here

mkdir -p "$WORK"
cd "$WORK"
source "$CONDA_SH"
date
echo "host: $(hostname)"

# ------------------------------------------------------------
# Step 0 : sanity check inputs
# ------------------------------------------------------------
echo "=== Input check ==="
for f in "$PILON" "$DECON" "$SUMMARY" "$HAP" "$POLYPOLISH" "$FINAL" "$NR_DMND" "$COEL_GENOMES"; do
  if [ -e "$f" ]; then echo "OK   $f"; else echo "MISSING  $f"; fi
done
[ -f "$RESCUE_LIST" ] && echo "OK   $RESCUE_LIST" || echo "WARN missing rescue list (will treat all hap.fa as dropped)"

# ------------------------------------------------------------
# Step 1 : build the DROPPED-contig set from all three stages
# ------------------------------------------------------------
conda activate "$ENV_SEQKIT"

echo ""
echo "=== Step 1a: BlobTools-removed (in PILON, not in DECON) ==="
comm -23 <(seqkit seq -n -i "$PILON" | sort) <(seqkit seq -n -i "$DECON" | sort) > ids_blobtools.txt
seqkit grep -f ids_blobtools.txt "$PILON" | seqkit replace -p '$' -r ' stage=blobtools' > dropped_blobtools.fa
echo "  removed by BlobTools: $(wc -l < ids_blobtools.txt)"

echo ""
echo "=== Step 1b: purge_dups-removed (hap.fa minus rescued) ==="
if [ -f "$RESCUE_LIST" ]; then
  seqkit grep -v -f "$RESCUE_LIST" "$HAP" > hap_not_rescued.fa
else
  cp "$HAP" hap_not_rescued.fa
fi
seqkit replace -p '$' -r ' stage=purge_dups' hap_not_rescued.fa > dropped_purgedups.fa
echo "  removed by purge_dups (excl. rescued): $(grep -c '^>' dropped_purgedups.fa)"

echo ""
echo "=== Step 1c: Tiara-removed (in POLYPOLISH, not in FINAL) ==="
comm -23 <(seqkit seq -n -i "$POLYPOLISH" | sort) <(seqkit seq -n -i "$FINAL" | sort) > ids_tiara.txt
seqkit grep -f ids_tiara.txt "$POLYPOLISH" | seqkit replace -p '$' -r ' stage=tiara' > dropped_tiara.fa
echo "  removed by Tiara: $(wc -l < ids_tiara.txt)"

cat dropped_blobtools.fa dropped_purgedups.fa dropped_tiara.fa > dropped_all.fa
echo ""
echo "=== TOTAL dropped contigs to scan ==="
seqkit stats -a dropped_all.fa

# ------------------------------------------------------------
# Step 2 : annotate each dropped contig (join to summary_full.tsv)
#   summary_full.tsv cols: 1=index 2=id 3=gc 4=length 5=ont_cov 6=ill_cov
#                          7=phylum 8=superkingdom 9=genus 10=species
#   hap.fa names look like hap_ptg000037l_pilon_1 -> normalise to ptg000037l_pilon
# ------------------------------------------------------------
echo ""
echo "=== Step 2: annotate dropped contigs ==="
seqkit fx2tab -nlg dropped_all.fa | sed 's/ stage=/\t/' \
  | awk 'BEGIN{OFS="\t"; print "contig","stage","length","gc_seqkit"} {print $1,$3,$2,$4}' \
  > dropped_basic.tsv

# normalised id -> summary lookup
awk -F'\t' 'NR>1{
  norm=$1; sub(/^hap_/,"",norm); sub(/_[0-9]+$/,"",norm);
  print $0"\t"norm
}' dropped_basic.tsv > dropped_basic_norm.tsv

awk -F'\t' '
  FNR==NR { if(FNR>1){gc[$2]=$3; len[$2]=$4; ont[$2]=$5; ill[$2]=$6; phy[$2]=$7; gen[$2]=$9; sp[$2]=$10} next }
  {
    if(FNR==1){ print "contig\tstage\tlength\tgc\tont_cov\till_cov\tblob_phylum\tblob_genus\tblob_species"; next }
    n=$NF
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", $1,$2,$3,(gc[n]==""?$4:gc[n]),(ont[n]==""?"NA":ont[n]),(ill[n]==""?"NA":ill[n]),(phy[n]==""?"NA":phy[n]),(gen[n]==""?"NA":gen[n]),(sp[n]==""?"NA":sp[n])
  }
' "$SUMMARY" dropped_basic_norm.tsv > dropped_contigs_annotation.tsv
echo "  wrote dropped_contigs_annotation.tsv"
column -t -s$'\t' dropped_contigs_annotation.tsv | head -60

# ------------------------------------------------------------
# Step 3 : diamond blastx vs nr   (decisive protein-level identity)
# ------------------------------------------------------------
echo ""
echo "=== Step 3: diamond blastx vs nr ==="
conda activate "$ENV_DIAMOND" 2>/dev/null || { echo "!! adjust ENV_DIAMOND"; command -v diamond >/dev/null || exit 1; }
command -v diamond
diamond version

if [ -s diamond_nr.tsv ]; then
  echo "  diamond_nr.tsv already exists ($(wc -l < diamond_nr.tsv) hits) -> skipping diamond run"
else
  diamond blastx \
    --query dropped_all.fa \
    --db "$NR_DMND" \
    --outfmt 6 qseqid sseqid pident length evalue bitscore staxids sscinames stitle \
    --max-target-seqs 5 \
    --evalue 1e-5 \
    --threads $THREADS \
    --out diamond_nr.tsv
  echo "  diamond hits: $(wc -l < diamond_nr.tsv)"
fi

# best hit per contig + flag mitochondrial markers in the hit description
awk -F'\t' '!seen[$1]++' diamond_nr.tsv > diamond_nr_best.tsv
# mito marker regex on the subject title (stitle = last col)
grep -iE 'cytochrome c oxidase|cox[123]|NADH dehydrogenase|nad[0-9]|cytochrome b|\bcob\b|ATP synthase|atp[0689]|mitochondri' diamond_nr.tsv \
  | awk -F'\t' '{print $1}' | sort -u > contigs_with_mito_markers.txt || true
echo "  contigs hitting mito markers: $(wc -l < contigs_with_mito_markers.txt)"
cat contigs_with_mito_markers.txt || true

# ------------------------------------------------------------
# Step 4 : blastn vs the 8 Coelastrella nuclear genomes
#          (strong hit => nuclear/haplotig => correctly dropped)
# ------------------------------------------------------------
echo ""
echo "=== Step 4: blastn vs 8 Coelastrella nuclear genomes ==="
conda activate "$ENV_BLAST"
if [ ! -f coel_db.nhr ] && [ ! -f coel_db.nin ]; then
  makeblastdb -in "$COEL_GENOMES" -dbtype nucl -out coel_db -title coelastrella_8genomes
fi
blastn -query dropped_all.fa -db coel_db \
  -outfmt "6 qseqid sseqid pident length qlen qcovs evalue bitscore" \
  -evalue 1e-10 -max_target_seqs 1 -num_threads $THREADS \
  -out blastn_vs_coelastrella.tsv
awk -F'\t' '!seen[$1]++' blastn_vs_coelastrella.tsv > blastn_vs_coelastrella_best.tsv
echo "  contigs with nuclear-genome hit: $(cut -f1 blastn_vs_coelastrella_best.tsv | sort -u | wc -l)"

# ------------------------------------------------------------
# Step 5 : targeted green-algal MITOCHONDRIAL references
#   NOTE: needs internet. Run this block on a head/login node if compute
#   nodes are offline, or pre-download the files into $WORK/mito_refs.fa
# ------------------------------------------------------------
echo ""
echo "=== Step 5: blastn vs green-algal mito references ==="
MITO_REFS=mito_refs.fa
if [ ! -s "$MITO_REFS" ]; then
  echo "  downloading green-algal mito references via Entrez ..."
  : > "$MITO_REFS"
  if command -v esearch >/dev/null 2>&1 && command -v efetch >/dev/null 2>&1; then
    # whatever complete mito genomes exist for the relevant green-algal clades
    for QUERY in \
      "Scenedesmaceae[Organism] AND mitochondrion[Title] AND complete genome[Title]" \
      "Sphaeropleales[Organism] AND mitochondrion[Title] AND complete genome[Title]" \
      "Chlamydomonas reinhardtii[Organism] AND mitochondrion[Title]" ; do
      esearch -db nucleotide -query "$QUERY" | efetch -format fasta >> "$MITO_REFS" 2>/dev/null || true
    done
    seqkit rmdup -s "$MITO_REFS" -o "${MITO_REFS}.tmp" 2>/dev/null && mv "${MITO_REFS}.tmp" "$MITO_REFS" || true
    echo "  mito reference seqs downloaded: $(grep -c '^>' "$MITO_REFS" 2>/dev/null || echo 0)"
  else
    echo "  !! Entrez Direct (esearch/efetch) not found."
    echo "     Manually place green-algal mito FASTA at $WORK/$MITO_REFS and rerun Step 5,"
    echo "     OR rely on the diamond-vs-nr result (Step 3), which already detects mito genes."
  fi
fi
if [ -s "$MITO_REFS" ]; then
  makeblastdb -in "$MITO_REFS" -dbtype nucl -out mito_db -title green_algal_mito
  blastn -query dropped_all.fa -db mito_db \
    -outfmt "6 qseqid sseqid pident length qlen qcovs evalue bitscore" \
    -evalue 1e-5 -max_target_seqs 1 -num_threads $THREADS \
    -out blastn_vs_mito_refs.tsv
  awk -F'\t' '!seen[$1]++' blastn_vs_mito_refs.tsv > blastn_vs_mito_refs_best.tsv
  echo "  contigs with mito-reference hit: $(cut -f1 blastn_vs_mito_refs_best.tsv | sort -u | wc -l)"
else
  : > blastn_vs_mito_refs_best.tsv
  echo "  skipped (no mito reference available)"
fi

# ------------------------------------------------------------
# Step 6 : combine everything into one verdict table
# ------------------------------------------------------------
echo ""
echo "=== Step 6: verdict table ==="
python3 - "$WORK" << 'PY'
import sys, os, csv
W = sys.argv[1]
def load_best(path, keycol=0):
    d={}
    if os.path.exists(path):
        for line in open(path):
            p=line.rstrip("\n").split("\t")
            if p and p[keycol] not in d:
                d[p[keycol]]=p
    return d

ann={}
with open(os.path.join(W,"dropped_contigs_annotation.tsv")) as fh:
    r=csv.reader(fh,delimiter="\t"); hdr=next(r)
    for row in r:
        ann[row[0]]=dict(zip(hdr,row))

dia=load_best(os.path.join(W,"diamond_nr_best.tsv"))
coel=load_best(os.path.join(W,"blastn_vs_coelastrella_best.tsv"))
mito=load_best(os.path.join(W,"blastn_vs_mito_refs_best.tsv"))
mito_markers=set(x.strip() for x in open(os.path.join(W,"contigs_with_mito_markers.txt")) if x.strip()) \
    if os.path.exists(os.path.join(W,"contigs_with_mito_markers.txt")) else set()

out=open(os.path.join(W,"dropped_contigs_verdict.tsv"),"w")
cols=["contig","stage","length","gc","ont_cov","ill_cov","blob_phylum",
      "nr_besthit","nr_taxon","mito_marker",
      "coel_pident","coel_qcov","mito_pident","mito_qcov","VERDICT"]
out.write("\t".join(cols)+"\n")

for c,a in ann.items():
    nr=dia.get(c); nr_title=nr[8][:60] if nr else "no hit"; nr_tax=nr[7] if nr else "NA"
    has_marker="YES" if c in mito_markers else "no"
    cg=coel.get(c); coel_pid=cg[2] if cg else "NA"; coel_qcov=cg[5] if cg else "0"
    mt=mito.get(c); mito_pid=mt[2] if mt else "NA"; mito_qcov=mt[5] if mt else "0"

    # ---- verdict logic ----
    def f(x):
        try: return float(x)
        except: return 0.0
    verdict="unknown / low-complexity"
    if has_marker=="YES" or f(mito_qcov)>=30:
        if f(coel_qcov)>=80 and f(coel_pid if cg else 0)>=95:
            verdict="MITO-LIKE but matches nuclear genome -> check (NUMT?)"
        else:
            verdict=">>> CANDIDATE MITOCHONDRION -- inspect & consider rescue <<<"
    elif f(coel_qcov)>=80:
        verdict="nuclear / haplotig (correctly dropped)"
    elif nr and nr_tax not in ("NA","") and not any(k in nr_tax.lower() for k in
            ["coelastrella","scenedes","chlamydomonas","chlorophy","viridiplant","tetradesmus","raphidocelis","sphaeropleales"]):
        verdict=f"likely contaminant ({nr_tax}) (correctly dropped)"
    elif f(coel_qcov)>0:
        verdict="partial nuclear match"
    out.write("\t".join([c,a["stage"],a["length"],a["gc"],a["ont_cov"],a["ill_cov"],a["blob_phylum"],
                         nr_title,nr_tax,has_marker,
                         (cg[2] if cg else "NA"),coel_qcov,mito_pid,mito_qcov,verdict])+"\n")
out.close()
print("wrote dropped_contigs_verdict.tsv")
PY

echo ""
echo "================ CANDIDATES ================"
awk -F'\t' 'NR==1 || $NF ~ /CANDIDATE|MITO-LIKE/' dropped_contigs_verdict.tsv | column -t -s$'\t'
echo ""
echo "Full table: $WORK/dropped_contigs_verdict.tsv"
date
echo "=== DONE ==="
