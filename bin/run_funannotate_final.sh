#!/usr/bin/env bash
set -euo pipefail
export FUNANNOTATE_DB=/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly/funannotate_db
cd /mnt/data/Projects/Elad_Chiel/wasp_genome_assembly
funannotate annotate \
  --gff annotation/funannotate_merged_out/annotate_results/Spalangia_cameroni.final.gff3 \
  --fasta annotation/funannotate_in/genome.fa \
  --species "Spalangia cameroni" --cpus 8 --busco_db hymenoptera \
  -o annotation/funannotate_final_out
