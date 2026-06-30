#!/bin/bash
# ========================================================
# Organize Coelastrella assembly scripts in pipeline order
# Output: 29 numbered scripts ready for neatseq-flow
# ========================================================
set -e
PROJ=/gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing
DEST=$PROJ/99.scripts_neatseq
mkdir -p $DEST

copy_script() {
  local new_name="$1"
  local src="$2"
  local desc="$3"
  if [ -f "$src" ]; then
    cp -v "$src" "$DEST/$new_name"
    echo "  → $desc"
  else
    echo "  ⚠️  לא נמצא: $src"
  fi
}

echo "============================================"
echo "STAGE 1: Pre-processing"
echo "============================================"
copy_script "01_ont_basecalling_dorado.sh" \
  "$PROJ/01.Raw_data/02.ONT_repeat_base_calling/basecaller_job.sh" \
  "ONT Dorado SUP basecalling + barcode demux"

copy_script "02_illumina_trim_qc.sh" \
  "$PROJ/01.Raw_data/03.Illumina/trim_reads_and_qc.sh" \
  "Illumina raw QC + fastp trimming"

echo ""
echo "============================================"
echo "STAGE 2: Read QC + Contamination screening"
echo "============================================"
copy_script "03_ont_kaiju_neatseq.sh" \
  "$PROJ/03.Raw_reads_QC/01.ONT/02.Kaiju/02.kaiju_2nd_run/scripts/00.workflow.commands.sh" \
  "ONT Kaiju (neatseq-flow, 2nd run with Chopper)"

copy_script "04_illumina_kaiju.sh" \
  "$PROJ/03.Raw_reads_QC/02.Illumina/02.kaiju/kaiju_illumina.sh" \
  "Illumina Kaiju contamination"

copy_script "05_ont_centrifuge.sh" \
  "$PROJ/03.Raw_reads_QC/01.ONT/03.Centrifuge/centrifuge_ont.sh" \
  "ONT Centrifuge classification (using existing nt DB)"

copy_script "06_illumina_centrifuge.sh" \
  "$PROJ/03.Raw_reads_QC/02.Illumina/03.Centrifuge/centrifuge_illumina.sh" \
  "Illumina Centrifuge classification"

echo ""
echo "============================================"
echo "STAGE 3: Genome size estimation"
echo "============================================"
copy_script "07_genomescope_smudgeplot.sh" \
  "$PROJ/04.Genome_size/genomescope_smudgeplot.sh" \
  "GenomeScope2 + Smudgeplot (k=21, ploidy inference)"

echo ""
echo "============================================"
echo "STAGE 4: De novo assembly"
echo "============================================"
copy_script "08_hifiasm_ont.sh" \
  "$PROJ/05.Assembly/01.hifiasm/hifiasm_ont.sh" \
  "Hifiasm-ONT (primary + 2 haplotypes)"

copy_script "09_flye.sh" \
  "$PROJ/05.Assembly/02.flye/flye.sh" \
  "Flye (for comparison/QC)"

copy_script "10_eval_quast_busco.sh" \
  "$PROJ/05.Assembly/03.evaluation/evluation_quast_busco.sh" \
  "QUAST + BUSCO comparison (Hifiasm vs Flye vs hap1/2)"

echo ""
echo "============================================"
echo "STAGE 5: Polishing (round 1)"
echo "============================================"
copy_script "11_medaka_test_model.sh" \
  "$PROJ/05.Assembly/04.polishing/01.medaka/test_mekada_model.sh" \
  "Medaka model selection test"

copy_script "12_medaka_polish.sh" \
  "$PROJ/05.Assembly/04.polishing/01.medaka/medaka_polish.sh" \
  "Medaka neural-network polish (r1041_e82_400bps_sup_v5.2.0)"

copy_script "13_pilon_polish.sh" \
  "$PROJ/05.Assembly/04.polishing/02.pilon/pilon_polish.sh" \
  "Pilon Illumina-based polish (round 1)"

copy_script "14_eval_polished.sh" \
  "$PROJ/05.Assembly/05.final_evaluation/final_evaluation.sh" \
  "Post-polish QUAST + BUSCO evaluation"

echo ""
echo "============================================"
echo "STAGE 6: Decontamination (BlobTools + BLAST)"
echo "============================================"
copy_script "15_blobtools_decontamination.sh" \
  "$PROJ/05.Assembly/06.decontamination/blobtools_decontamination.sh" \
  "BlobTools2 contamination screen (sensitive mode)"

copy_script "16_blobtools_fast_mode.sh" \
  "$PROJ/05.Assembly/06.decontamination/blobtools_fast_mode.sh" \
  "BlobTools2 --fast mode (used after sensitive was too slow)"

copy_script "17_busco_decontaminated.sh" \
  "$PROJ/05.Assembly/06.decontamination/run_busco_clean.sh" \
  "BUSCO on decontaminated assembly"

copy_script "18_blast_validate_boris_refs.sh" \
  "$PROJ/05.Assembly/07.reference_validation/validate_assembly_blast_v2.sh" \
  "BLASTn + tblastn vs Boris's reference seqs (psbA, psbD, rbcS, 18S+ITS)"

echo ""
echo "============================================"
echo "STAGE 7: Haplotig purging + Polish (round 2)"
echo "============================================"
copy_script "19_purge_dups.sh" \
  "$PROJ/07.purge_dups/run_purge_dups.sh" \
  "purge_dups haplotig removal (with manual organelle rescue)"

copy_script "20_busco_purged.sh" \
  "$PROJ/07.purge_dups/run_busco_purged.sh" \
  "BUSCO on purged + rescued assembly (29 contigs)"

copy_script "21_nextpolish.sh" \
  "$PROJ/08.nextpolish/run_nextpolish.sh" \
  "NextPolish 2 rounds (Python 3.10 required - see workflow doc §24e)"

copy_script "22_busco_nextpolish.sh" \
  "$PROJ/08.nextpolish/run_busco_polished.sh" \
  "BUSCO on NextPolish output (miniprot)"

copy_script "23_busco_metaeuk_compare.sh" \
  "$PROJ/08.nextpolish/run_busco_metaeuk.sh" \
  "BUSCO with --metaeuk (artifact check)"

copy_script "24_polypolish_pypolca.sh" \
  "$PROJ/09.polypolish/run_polypolish_pypolca.sh" \
  "Polypolish + Pypolca (orthogonal polish)"

copy_script "25_busco_final_polish.sh" \
  "$PROJ/09.polypolish/run_busco_final.sh" \
  "BUSCO on Polypolish+Pypolca output (miniprot + metaeuk)"

echo ""
echo "============================================"
echo "STAGE 8: Final decontamination (Tiara + FCS-GX)"
echo "============================================"
copy_script "26_tiara.sh" \
  "$PROJ/10.tiara/run_tiara.sh" \
  "Tiara deep-learning classifier (eukarya/organelle/bacteria)"

copy_script "27_busco_FINAL.sh" \
  "$PROJ/09.polypolish/run_busco_FINAL.sh" \
  "BUSCO on Coelastrella_FINAL.fa (post-Tiara cleanup)"

copy_script "28_fcs_gx_download_db.sh" \
  "$PROJ/11.fcs_gx/download_fcs_db.sh" \
  "Download NCBI FCS-GX DB (~465 GB, 12 hours) [ONE-TIME]"

copy_script "29_fcs_gx_run.sh" \
  "$PROJ/11.fcs_gx/run_fcs_gx.sh" \
  "Run FCS-GX on FINAL assembly (NCBI gold-standard)"

echo ""
echo "============================================"
echo "Summary"
echo "============================================"
total=$(ls -1 $DEST/[0-9]*.sh 2>/dev/null | wc -l)
echo "Total scripts copied: $total / 29 expected"
echo ""
echo "List:"
ls -1 $DEST/[0-9]*.sh | xargs -n1 basename
