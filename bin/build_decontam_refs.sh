#!/usr/bin/env bash
# Build the COMPOSITE reference for phase 1.2b alignment-based decontam.
#
# Input: pre-relabeled fasta files in short_reads_contem_index/, where each
# header starts with an organism prefix (Homo_sapiens_, Spalangia_cameroni_,
# Nasonia_vitripennis_, Solenopsis_invicta_, Escherichia_coli_,
# Escherichia_phage_phiX174_, Wolbachia_pipientis_, Sodalis_praecaptivus_,
# Arsenophonus_nasoniae_, Rickettsia_felis_).
#
# Outputs (all into short_reads_contem_index/):
#   composite.fa         concatenated relabeled fasta (used at align time)
#   composite.*.bt2      bowtie2 index of composite.fa
#   MANIFEST.tsv         provenance (path, bytes, md5, organism prefix, panel)
#
# The pipeline classifies mapped reads by reading the prefix of the RNAME:
#   prefix ∈ {Spalangia_cameroni, Nasonia_vitripennis, Solenopsis_invicta}
#                                                                        → INSECT
#   else                                                                 → CONTAM
#
# Idempotent: re-runs skip already-built bowtie2 index files.

set -euo pipefail

PROJECT_DIR="/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly"
REFS_DIR="${PROJECT_DIR}/short_reads_contem_index"
MANIFEST="${REFS_DIR}/MANIFEST.tsv"
COMPOSITE="${REFS_DIR}/composite.fa"
BT2_PREFIX="${REFS_DIR}/composite"

cd "${REFS_DIR}"

# Source files paired with their organism prefix (must match the prefix the
# relabel_headers.sh script applied to each fasta) and panel (insect|contam).
SOURCES=(
    "GBVV01.transcripts.one_line.relabeled.fasta|Spalangia_cameroni|insect"
    "GCF_009193385.2_Nvit_psr_1.1_genomic.relabeled.fna|Nasonia_vitripennis|insect"
    "GCF_016802725.1_UNIL_Sinv_3.0_genomic.relabeled.fna|Solenopsis_invicta|insect"
    "GRCh38.primary_assembly.genome.relabeled.fa|Homo_sapiens|contam"
    "PhiX174_genome.relabeled.fasta|Escherichia_phage_phiX174|contam"
    "GCF_000005845.2_ASM584v2_genomic.relabeled.fna|Escherichia_coli|contam"
    "GCF_947533255.1_wMelPlus_assembly_genomic.relabeled.fna|Wolbachia_pipientis|contam"
    "GCF_039646275.1_ASM3964627v1_genomic.relabeled.fna|Sodalis_praecaptivus|contam"
    "GCF_004768525.1_ASM476852v1_genomic.relabeled.fna|Arsenophonus_nasoniae|contam"
    "GCF_000804505.1_ASM80450v1_genomic.relabeled.fna|Rickettsia_felis|contam"
)

# ── Verify sources & relabel prefix correctness ──
echo "=== Verifying sources ==="
for entry in "${SOURCES[@]}"; do
    IFS='|' read -r f tag panel <<< "${entry}"
    if [[ ! -s "${f}" ]]; then
        echo "ERROR: missing source: ${f}" >&2; exit 1
    fi
    first=$(grep -m1 '^>' "${f}" || true)
    if [[ "${first}" != ">${tag}_"* ]]; then
        echo "ERROR: ${f}: first header '${first}' does not start with '>${tag}_'" >&2
        exit 1
    fi
    n=$(grep -c '^>' "${f}")
    printf "  [%s] %-65s %s  (%d seqs)\n" "${panel}" "${f}" "${tag}" "${n}"
done

# ── Concatenate ──
echo
echo "=== Concatenating composite.fa ==="
: > "${COMPOSITE}"
for entry in "${SOURCES[@]}"; do
    IFS='|' read -r f tag panel <<< "${entry}"
    cat "${f}" >> "${COMPOSITE}"
done
echo "  composite.fa size: $(du -h "${COMPOSITE}" | cut -f1)"
echo "  composite.fa seqs: $(grep -c '^>' "${COMPOSITE}")"

# Sanity: every header must start with one of the known organism prefixes
KNOWN_RE='^>(Spalangia_cameroni|Nasonia_vitripennis|Solenopsis_invicta|Homo_sapiens|Escherichia_phage_phiX174|Escherichia_coli|Wolbachia_pipientis|Sodalis_praecaptivus|Arsenophonus_nasoniae|Rickettsia_felis)_'
bad=$(grep '^>' "${COMPOSITE}" | grep -vE "${KNOWN_RE}" | head -5 || true)
if [[ -n "${bad}" ]]; then
    echo "ERROR: composite.fa contains headers without a known organism prefix (first 5):" >&2
    echo "${bad}" >&2
    exit 1
fi

# ── Build bowtie2 index ──
echo
echo "=== Bowtie2 index ==="
need_build=1
for ext in 1.bt2 2.bt2 3.bt2 4.bt2 rev.1.bt2 rev.2.bt2; do
    if [[ ! -s "${BT2_PREFIX}.${ext}" ]]; then need_build=1; break; fi
    sz=$(stat -c%s "${BT2_PREFIX}.${ext}")
    # Reject the broken 8/35/2-byte stubs from a prior failed build
    if (( sz < 1024 )) && [[ "${ext}" != "3.bt2" ]]; then need_build=1; break; fi
    need_build=0
done

if [[ ${need_build} -eq 1 ]]; then
    THREADS="${THREADS:-16}"
    echo "  Removing any stale/partial index files..."
    rm -f "${BT2_PREFIX}".{1,2,3,4}.bt2 "${BT2_PREFIX}".rev.{1,2}.bt2 "${BT2_PREFIX}".{1,2,3,4}.bt2l "${BT2_PREFIX}".rev.{1,2}.bt2l
    echo "  Building bowtie2 index (this takes ~15-25 min for ~3.7 GB ref, ${THREADS} threads)..."
    bowtie2-build --threads "${THREADS}" "${COMPOSITE}" "${BT2_PREFIX}" \
        > "${REFS_DIR}/composite_bt2_build.log" 2>&1
    echo "  bowtie2-build done. Log: ${REFS_DIR}/composite_bt2_build.log"
else
    echo "  [skip] index already in place at ${BT2_PREFIX}.{1,2,3,4,rev.1,rev.2}.bt2"
fi

ls -lh "${BT2_PREFIX}".{1,2,3,4,rev.1,rev.2}.bt2 2>/dev/null | awk '{printf "    %-8s %s\n", $5, $NF}'

# ── MANIFEST ──
echo
echo "=== MANIFEST ==="
{
    echo -e "panel\torganism_prefix\tsource\tbytes\theaders\tmd5"
    for entry in "${SOURCES[@]}"; do
        IFS='|' read -r f tag panel <<< "${entry}"
        bytes=$(stat -c%s "${f}")
        nseq=$(grep -c '^>' "${f}")
        md5=$(md5sum "${f}" | cut -d' ' -f1)
        echo -e "${panel}\t${tag}\t${f}\t${bytes}\t${nseq}\t${md5}"
    done
} > "${MANIFEST}"
echo "  ${MANIFEST}"

echo
echo "=== Done ==="
echo "  ${COMPOSITE}  ($(du -h "${COMPOSITE}" | cut -f1))"
echo "  ${BT2_PREFIX}.*  (bowtie2 index)"
echo "  ${MANIFEST}"
