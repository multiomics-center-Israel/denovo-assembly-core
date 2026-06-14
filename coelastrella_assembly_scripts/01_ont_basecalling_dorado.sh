#!/bin/bash
#$ -S /bin/bash
#$ -N run_dorado
#$ -cwd
#$ -j y
#$ -e /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/01.Raw_data/02.ONT_repeat_base_calling/dorado_run.err
#$ -o /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/01.Raw_data/02.ONT_repeat_base_calling/dorado_run.log
#$ -q bioinfo.q@bhn1103
#$ -pe shared 10


nvidia-smi


/gpfs0/system/conda/Non_CONDA_Programs/Dorado/dorado-1.4.0-linux-x64/bin/dorado basecaller dna_r10.4.1_e8.2_400bps_sup@v5.2.0 /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/01.Raw_data/01.ONT_Plasmidsaurus/Q2H9QN_POD5/ --kit-name SQK-RBK114-96 --device cuda:0 --emit-fastq --recursive --output-dir /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/01.Raw_data/02.ONT_repeat_base_calling/Q2H9QN_dorado_sup_demuxed_out

