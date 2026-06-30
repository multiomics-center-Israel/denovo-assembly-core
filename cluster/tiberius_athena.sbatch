#!/bin/bash
# ============================================================================
# Tiberius v2 ab-initio gene prediction — S. cameroni — athena (SLURM)
# athena is SLURM (pbsnodes/qstat are flaky PBS-compat wrappers) -> use sbatch.
#
# ONE-TIME SETUP (run on the login node, in the cloned Tiberius dir):
#   mamba create -y -n tiberius python=3.12        # module python is 3.11 = too old
#   conda activate tiberius
#   pip install .[from_source]                      # tensorflow[and-cuda]>=2.17 etc.
#   python tiberius.py --list_cfg | grep -i insecta # confirm insecta models present
#
# SUBMIT :  sbatch tiberius_athena.sbatch
# WATCH  :  squeue -u $USER   ;   tail -f tiberius_scam.<JOBID>.out
# ============================================================================
#SBATCH --job-name=tiberius_scam
#SBATCH --partition=l40s-public        # a100-public also fine; avoid private (benisty/dds/shocher)
#SBATCH --gres=gpu:1                    # if rejected, try: --gpus=1  OR  --gres=gpu:nvidia_l40s:1
#SBATCH --qos=24h_1g                    # QOS sets the walltime cap; 24h_1g = 24h, 1 GPU (sacctmgr show qos)
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=04:00:00                 # well within 24h_1g; Tiberius on ~650Mb ~0.5-1.5h. raise if needed
#SBATCH --output=tiberius_scam.%j.out  # merged stdout+stderr
#SBATCH --mail-user=bioinfo.multiomics@technion.ac.il
#SBATCH --mail-type=END,FAIL
set -euo pipefail

# ---- paths (EDIT to athena layout) -----------------------------------------
WORK=/rg/admon_prj/ozsol/wasp_genome      # where you staged the data
TIBERIUS=/rg/admon_prj/ozsol/wasp_genome/tiberius/Tiberius              # cloned repo (you're in it now)
GENOME_MASK="$WORK/final_assembly.fa.masked"   # SOFT-masked (verify lowercase)
GENOME_RAW="$WORK/final_assembly.fa"
OUTDIR="$WORK/annotation/tiberius"
BATCH=16                                # L40S/A100/H200 (>=40GB): 16 | rtx6k(24-48G): 8 | 16GB: 4
mkdir -p "$OUTDIR"
cd "${SLURM_SUBMIT_DIR:-$WORK}"

# ---- environment: conda (no singularity module on athena) ------------------
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate tiberius
# TF wheels bundle their own CUDA; only load the system module if TF can't see the GPU:
# module load cuda/12.1.1-x86-nj6dyov

# ---- sanity: log GPU + confirm TensorFlow sees it --------------------------
echo "==== Tiberius START $(date -Iseconds) on $(hostname)  JOB=$SLURM_JOB_ID ===="
nvidia-smi || { echo "NO GPU VISIBLE — check partition/--gres"; exit 1; }
python -c "import tensorflow as tf; gs=tf.config.list_physical_devices('GPU'); print('TF GPUs:',gs); assert gs,'TF sees no GPU'"

# ---- primary: insecta (softmasked) on the softmasked genome ----------------
python "$TIBERIUS/tiberius.py" \
     --genome "$GENOME_MASK" --model_cfg insecta \
     --out "$OUTDIR/tiberius_insecta.gtf" \
     --codingseq "$OUTDIR/tiberius_insecta.cds.fa" \
     --protseq  "$OUTDIR/tiberius_insecta.aa.fa" \
     --batch_size "$BATCH"
echo "[ok] primary (insecta softmasked) -> $OUTDIR/tiberius_insecta.gtf"

# ---- cross-check: insecta_unmasked on raw genome (optional; comment to skip) -
python "$TIBERIUS/tiberius.py" \
     --genome "$GENOME_RAW" --model_cfg insecta_unmasked \
     --out "$OUTDIR/tiberius_insecta_unmasked.gtf" \
     --protseq "$OUTDIR/tiberius_insecta_unmasked.aa.fa" \
     --batch_size "$BATCH"
echo "[ok] cross-check (insecta unmasked) -> $OUTDIR/tiberius_insecta_unmasked.gtf"

echo "==== Tiberius DONE $(date -Iseconds) ===="
# Next: validation gate (BUSCO + Nasonia-venom DIAMOND) — tiberius_v2_install_athena.md §5
