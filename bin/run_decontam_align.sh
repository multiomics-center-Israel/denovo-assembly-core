#!/usr/bin/env bash
# Standalone alignment + classification for v3 decontam.
# Runs PacBio minimap2 then Illumina bowtie2 against composite ref,
# streams SAM through samtools+awk to produce contam_hits.ids and
# insect_hits.ids per dataset (sorted, unique). No BAMs saved.
#
# Outputs into  decontamination/reads/  :
#   pacbio_contam_hits.ids       (unique-best contam-mapped HiFi QNAMEs)
#   pacbio_insect_hits.ids       (unique-best insect-mapped HiFi QNAMEs)
#   illumina_contam_hits.ids     (unique-best contam-mapped Illumina QNAMEs)
#   illumina_insect_hits.ids     (unique-best insect-mapped Illumina QNAMEs)
#   mm2_pacbio.log               (minimap2 stderr)
#   bowtie2_illumina.log         (bowtie2 stderr w/ mapping stats)
#   align_summary.txt            (final counts + timings)

set -euo pipefail

PROJECT_DIR="/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly"
WORK="${PROJECT_DIR}/decontamination/reads"
COMPOSITE="${PROJECT_DIR}/short_reads_contem_index/composite.fa"
BT2="${PROJECT_DIR}/short_reads_contem_index/composite"
PACBIO="${PROJECT_DIR}/GMCF_3514_04.107_107.fastq"
ILL_R1="${PROJECT_DIR}/qc/illumina/trimmed_R1.fastq.gz"
ILL_R2="${PROJECT_DIR}/qc/illumina/trimmed_R2.fastq.gz"
THREADS="${THREADS:-16}"

mkdir -p "${WORK}"
cd "${WORK}"

# Activate the conda env (best-effort — assumes tools already on PATH otherwise)
if command -v conda >/dev/null 2>&1; then
    # shellcheck disable=SC1091
    source "$(conda info --base)/etc/profile.d/conda.sh"
    conda activate genome_assembly
fi

# ── Verify inputs ──
for f in "${COMPOSITE}" "${BT2}.1.bt2" "${PACBIO}" "${ILL_R1}" "${ILL_R2}"; do
    [[ -s "$f" ]] || { echo "ERROR: missing/empty: $f" >&2; exit 1; }
done

# ── ERE pattern for the awk classifier (must match pipeline.py INSECT_PREFIXES) ──
INSECT_RE='^(Spalangia_cameroni_|Nasonia_vitripennis_|Solenopsis_invicta_)'

# ── awk classifier (same logic as pipeline.py::_AWK_CLASSIFIER) ──
cat > classify.awk <<'AWK'
{
    if (aligner == "minimap2") {
        if ($5 + 0 < 1) next                      # MAPQ >= 1 (unique-best)
    } else {
        AS = ""; XS = ""
        for (i = 12; i <= NF; i++) {
            if (substr($i, 1, 5) == "AS:i:") AS = substr($i, 6) + 0
            else if (substr($i, 1, 5) == "XS:i:") XS = substr($i, 6) + 0
        }
        if (AS == "") next
        if (XS != "" && XS >= AS) next            # AS > XS (unique-best)
    }
    if (match($3, insect_prefixes_re))
        print $1 >> insect_out
    else
        print $1 >> contam_out
}
AWK

# Helper: align → samtools → awk → sort/uniq each output
classify_stream() {
    local aligner="$1" aligner_cmd="$2" raw_c="$3" raw_i="$4" final_c="$5" final_i="$6"
    : > "${raw_c}"; : > "${raw_i}"
    bash -c "set -o pipefail; ${aligner_cmd} | samtools view -@ 4 -F 4 - | \
        awk -v insect_prefixes_re='${INSECT_RE}' \
            -v contam_out='${raw_c}' \
            -v insect_out='${raw_i}' \
            -v aligner='${aligner}' \
            -f classify.awk"
    # sort -u into final
    if [[ -s "${raw_c}" ]]; then
        sort -u --parallel="${THREADS}" -T "${WORK}" "${raw_c}" -o "${final_c}"
    else
        : > "${final_c}"
    fi
    if [[ -s "${raw_i}" ]]; then
        sort -u --parallel="${THREADS}" -T "${WORK}" "${raw_i}" -o "${final_i}"
    else
        : > "${final_i}"
    fi
    rm -f "${raw_c}" "${raw_i}"
}

t_start=$(date +%s)
echo "============================================================"
echo "v3 decontam alignments — started $(date -Iseconds)"
echo "  composite ref: ${COMPOSITE}"
echo "  threads:       ${THREADS}"
echo "============================================================"

# ── PacBio HiFi: minimap2 -ax map-hifi ──
echo
echo ">>> PacBio HiFi minimap2 (start $(date -Iseconds))"
t_pb=$(date +%s)
classify_stream \
    "minimap2" \
    "minimap2 -ax map-hifi -t ${THREADS} --split-prefix ${WORK}/mm2_split_pacbio ${COMPOSITE} ${PACBIO} 2> ${WORK}/mm2_pacbio.log" \
    "${WORK}/pacbio_contam_hits.raw" \
    "${WORK}/pacbio_insect_hits.raw" \
    "${WORK}/pacbio_contam_hits.ids" \
    "${WORK}/pacbio_insect_hits.ids"
t_pb_end=$(date +%s)
pb_c=$(wc -l < "${WORK}/pacbio_contam_hits.ids" || echo 0)
pb_i=$(wc -l < "${WORK}/pacbio_insect_hits.ids" || echo 0)
echo "    PacBio done in $((t_pb_end - t_pb))s"
echo "    confident contam hits: ${pb_c}"
echo "    confident insect hits: ${pb_i}"
rm -f "${WORK}"/mm2_split_pacbio*

# ── Illumina: bowtie2 --local ──
echo
echo ">>> Illumina bowtie2 --local (start $(date -Iseconds))"
t_ill=$(date +%s)
classify_stream \
    "bowtie2" \
    "bowtie2 --local -p ${THREADS} -x ${BT2} -1 ${ILL_R1} -2 ${ILL_R2} --no-unal 2> ${WORK}/bowtie2_illumina.log" \
    "${WORK}/illumina_contam_hits.raw" \
    "${WORK}/illumina_insect_hits.raw" \
    "${WORK}/illumina_contam_hits.ids" \
    "${WORK}/illumina_insect_hits.ids"
t_ill_end=$(date +%s)
ill_c=$(wc -l < "${WORK}/illumina_contam_hits.ids" || echo 0)
ill_i=$(wc -l < "${WORK}/illumina_insect_hits.ids" || echo 0)
echo "    Illumina done in $((t_ill_end - t_ill))s"
echo "    confident contam hits: ${ill_c}"
echo "    confident insect hits: ${ill_i}"

# ── Summary ──
t_end=$(date +%s)
SUM="${WORK}/align_summary.txt"
{
    echo "v3 decontam alignments — finished $(date -Iseconds)"
    echo "total elapsed: $((t_end - t_start))s"
    echo
    echo "PacBio HiFi (minimap2 -ax map-hifi):"
    echo "  elapsed: $((t_pb_end - t_pb))s"
    echo "  confident contam hits: ${pb_c}"
    echo "  confident insect hits: ${pb_i}"
    echo "  → if pipeline ran now: DROP would be (contam - insect) = $(comm -23 <(sort -u ${WORK}/pacbio_contam_hits.ids) <(sort -u ${WORK}/pacbio_insect_hits.ids) | wc -l)"
    echo
    echo "Illumina (bowtie2 --local, paired):"
    echo "  elapsed: $((t_ill_end - t_ill))s"
    echo "  confident contam hits (pairs): ${ill_c}"
    echo "  confident insect hits (pairs): ${ill_i}"
    echo "  → if pipeline ran now: DROP would be (contam - insect) = $(comm -23 <(sort -u ${WORK}/illumina_contam_hits.ids) <(sort -u ${WORK}/illumina_insect_hits.ids) | wc -l)"
    echo
    echo "Output files in ${WORK}:"
    ls -lh "${WORK}"/{pacbio,illumina}_*hits.ids "${WORK}"/{mm2_pacbio,bowtie2_illumina}.log 2>/dev/null
} > "${SUM}"

cat "${SUM}"

# Email notification (best-effort)
if command -v mail >/dev/null 2>&1; then
    mail -s "[v3 decontam] alignments complete" bioinfo.multiomics@technion.ac.il < "${SUM}" 2>/dev/null || true
fi

# Use the pipeline's notify module
python3 -c "
import sys
sys.path.insert(0, '${PROJECT_DIR}/denovo-assembly-core')
from denovo_assembly_core.notify import send_email
from denovo_assembly_core.config import Config
cfg = Config('${PROJECT_DIR}/project.yaml')
send_email(cfg,
           '[v3 decontam] PacBio + Illumina alignments complete',
           open('${SUM}').read())
" 2>&1 | tail -3 || true

echo
echo "============================================================"
echo "DONE."
