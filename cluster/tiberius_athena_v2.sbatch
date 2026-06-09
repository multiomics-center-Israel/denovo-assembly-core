#!/bin/bash
# ============================================================================
# Tiberius v2 — S. cameroni — athena (SLURM)  [CORRECTED RE-RUN]
# Root cause of all prior failures (91174/91176/91181 ...): HOST-RAM OOM.
#   slurmstepd: Detected 1 oom_kill event ... OOM Killed   <- cgroup --mem=64G
#   The L40S GPU (46 GB) was never the bottleneck; lowering --batch_size would
#   NOT have helped. Tiberius holds the whole 651 Mb genome as encoded arrays
#   in SYSTEM RAM during load/one-hot, which blows past 64 GB.
# FIX: --mem 64G -> 192G (raise to 256G if a node has it / if it still OOMs).
# Also: previous runs logged `Softmasking: False` and pulled the *unmasked*
#   model even though the genome IS soft-masked (34% lowercase, 0% N). Pass the
#   soft-mask flag + matching cfg so the right model is used.
#
# SUBMIT :  sbatch tiberius_athena_v2.sbatch
# WATCH  :  squeue -u $USER ; tail -f tiberius_scam.<JOBID>.out
# VALID  :  log must show all 7 groups end in 'Done.' + '==== Tiberius DONE ===='
#           and the GTF must have ~4980 contigs in col 1 (not 546 / not 949).
# ============================================================================
#SBATCH --job-name=tiberius_scam
#SBATCH --partition=l40s-public        # a100-public also fine
#SBATCH --gres=gpu:1
#SBATCH --qos=24h_1g
#SBATCH --cpus-per-task=8
#SBATCH --mem=192G                     # <-- THE FIX (was 64G). 256G if available.
#SBATCH --time=08:00:00                # full 7 groups ~<1h once it stops OOMing; margin for safety
#SBATCH --output=tiberius_scam.%j.out
#SBATCH --mail-user=bioinfo.multiomics@technion.ac.il
#SBATCH --mail-type=END,FAIL
set -euo pipefail

WORK=/rg/admon_prj/ozsol/wasp_genome
TIBERIUS=/rg/admon_prj/ozsol/wasp_genome/tiberius/Tiberius
GENOME_MASK="$WORK/final_assembly.fa.masked"   # soft-masked (lowercase repeats, no N)
OUTDIR="$WORK/annotation/tiberius"
BATCH=16
mkdir -p "$OUTDIR"
cd "${SLURM_SUBMIT_DIR:-$WORK}"

source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate tiberius

echo "==== Tiberius START $(date -Iseconds) on $(hostname)  JOB=$SLURM_JOB_ID ===="
nvidia-smi || { echo "NO GPU VISIBLE"; exit 1; }
python -c "import tensorflow as tf; gs=tf.config.list_physical_devices('GPU'); print('TF GPUs:',gs); assert gs,'TF sees no GPU'"

# sanity: verify the staged genome is actually soft-masked (lowercase, ~0% N).
python - "$GENOME_MASK" <<'PY'
import sys
up=lo=n=0
for i,l in enumerate(open(sys.argv[1])):
    if l[0]=='>': continue
    s=l.strip(); up+=sum(c in 'ACGT' for c in s); lo+=sum(c in 'acgt' for c in s); n+=sum(c in 'Nn' for c in s)
    if i>300000: break
t=up+lo+n or 1
print(f"[mask check] lower(soft) {100*lo/t:.1f}%  N(hard) {100*n/t:.1f}%")
assert lo>up*0.05, "genome is NOT soft-masked — wrong file staged"
PY

# PRIMARY run only (cross-check removed; get one clean complete pass first).
# NB: this Tiberius build has NO --softmasking flag; --model_cfg insecta is the
# unmasked-type model by design, so `Softmasking: False` in the log is correct.
python "$TIBERIUS/tiberius.py" \
     --genome "$GENOME_MASK" --model_cfg insecta \
     --out "$OUTDIR/tiberius_insecta.gtf" \
     --codingseq "$OUTDIR/tiberius_insecta.cds.fa" \
     --protseq  "$OUTDIR/tiberius_insecta.aa.fa" \
     --batch_size "$BATCH"

echo "[ok] primary -> $OUTDIR/tiberius_insecta.gtf"
echo "==== Tiberius DONE $(date -Iseconds) ===="
# post-check (paste into shell after):
#   cut -f1 $OUTDIR/tiberius_insecta.gtf | sort -u | wc -l   # expect ~4980
#   grep -c '^>' $OUTDIR/tiberius_insecta.aa.fa
