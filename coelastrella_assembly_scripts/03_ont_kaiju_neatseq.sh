



# _____   __              _____ ________                      ________________                  
# ___  | / /_____ ______ ___  /___  ___/_____ ______ _        ___  ____/___  /______ ___      __
# __   |/ / _  _ \_  __ `/_  __/_____ \ _  _ \_  __ `/__________  /_    __  / _  __ \__ | /| / /
# _  /|  /  /  __// /_/ / / /_  ____/ / /  __// /_/ / _/_____/_  __/    _  /  / /_/ /__ |/ |/ / 
# /_/ |_/   \___/ \__,_/  \__/  /____/  \___/ \__, /          /_/       /_/   \____/ ____/|__/  
#                                               /_/                                             

# This is the main executable script of this pipeline
# It was created on 30/04/2026 13:23:24 by NeatSeq-Flow version 1.6.0
# See http://neatseq-flow.readthedocs.io/en/latest/

# Import helper functions
. /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/01.Raw_data/02.ONT_repeat_base_calling/QC/contam_qc/w_barcoding/scripts/CC.helper_funcs.sh


# ---------------- Code for Import..Import..20260430132323 ------------------

echo running Import..Import..20260430132323
qsub /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/01.Raw_data/02.ONT_repeat_base_calling/QC/contam_qc/w_barcoding/scripts/01.Import_Import.sh



# ---------------- Code for Fillout_Generic..Chopper..20260430132323 ------------------

echo running Fillout_Generic..Chopper..20260430132323
qsub /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/01.Raw_data/02.ONT_repeat_base_calling/QC/contam_qc/w_barcoding/scripts/02.Fillout_Generic_Chopper.sh



# ---------------- Code for Fillout_Generic..NanoPlot_Raw..20260430132323 ------------------

echo running Fillout_Generic..NanoPlot_Raw..20260430132323
qsub /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/01.Raw_data/02.ONT_repeat_base_calling/QC/contam_qc/w_barcoding/scripts/04.Fillout_Generic_NanoPlot_Raw.sh



# ---------------- Code for Fillout_Generic..Kaiju_Classify..20260430132323 ------------------

echo running Fillout_Generic..Kaiju_Classify..20260430132323
qsub /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/01.Raw_data/02.ONT_repeat_base_calling/QC/contam_qc/w_barcoding/scripts/05.Fillout_Generic_Kaiju_Classify.sh



# ---------------- Code for Fillout_Generic..NanoPlot_Filtered..20260430132323 ------------------

echo running Fillout_Generic..NanoPlot_Filtered..20260430132323
qsub /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/01.Raw_data/02.ONT_repeat_base_calling/QC/contam_qc/w_barcoding/scripts/06.Fillout_Generic_NanoPlot_Filtered.sh



# ---------------- Code for Fillout_Generic..Kaiju_Krona..20260430132323 ------------------

echo running Fillout_Generic..Kaiju_Krona..20260430132323
qsub /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/01.Raw_data/02.ONT_repeat_base_calling/QC/contam_qc/w_barcoding/scripts/07.Fillout_Generic_Kaiju_Krona.sh



# ---------------- Code for Fillout_Generic..Kaiju_Report..20260430132323 ------------------

echo running Fillout_Generic..Kaiju_Report..20260430132323
qsub /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing/01.Raw_data/02.ONT_repeat_base_calling/QC/contam_qc/w_barcoding/scripts/08.Fillout_Generic_Kaiju_Report.sh


