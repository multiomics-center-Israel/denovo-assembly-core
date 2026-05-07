#!/usr/bin/env python3
"""Generate PowerPoint presentation for S. cameroni genome assembly plan."""

from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.enum.shapes import MSO_SHAPE

prs = Presentation()
prs.slide_width = Inches(13.333)
prs.slide_height = Inches(7.5)

# Color scheme
DARK_BLUE = RGBColor(0x1B, 0x3A, 0x5C)
MED_BLUE = RGBColor(0x2E, 0x6B, 0x9E)
LIGHT_BLUE = RGBColor(0x4A, 0x9E, 0xD9)
ACCENT_GREEN = RGBColor(0x27, 0xAE, 0x60)
ACCENT_ORANGE = RGBColor(0xE6, 0x7E, 0x22)
ACCENT_RED = RGBColor(0xC0, 0x39, 0x2B)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)
LIGHT_GRAY = RGBColor(0xF0, 0xF0, 0xF0)
DARK_GRAY = RGBColor(0x33, 0x33, 0x33)
MED_GRAY = RGBColor(0x66, 0x66, 0x66)


def add_bg(slide, color=DARK_BLUE):
    bg = slide.background
    fill = bg.fill
    fill.solid()
    fill.fore_color.rgb = color


def add_text_box(slide, left, top, width, height, text, font_size=18,
                 color=DARK_GRAY, bold=False, alignment=PP_ALIGN.LEFT, font_name="Calibri"):
    txBox = slide.shapes.add_textbox(Inches(left), Inches(top), Inches(width), Inches(height))
    tf = txBox.text_frame
    tf.word_wrap = True
    p = tf.paragraphs[0]
    p.text = text
    p.font.size = Pt(font_size)
    p.font.color.rgb = color
    p.font.bold = bold
    p.font.name = font_name
    p.alignment = alignment
    return txBox


def add_bullet_slide(slide, left, top, width, height, items, font_size=16,
                     color=DARK_GRAY, bullet_color=None, spacing=Pt(6)):
    txBox = slide.shapes.add_textbox(Inches(left), Inches(top), Inches(width), Inches(height))
    tf = txBox.text_frame
    tf.word_wrap = True
    for i, item in enumerate(items):
        if i == 0:
            p = tf.paragraphs[0]
        else:
            p = tf.add_paragraph()
        p.text = item
        p.font.size = Pt(font_size)
        p.font.color.rgb = color
        p.font.name = "Calibri"
        p.space_after = spacing
        p.level = 0
    return txBox


def add_rounded_rect(slide, left, top, width, height, fill_color, text="",
                     font_size=14, font_color=WHITE, bold=True):
    shape = slide.shapes.add_shape(
        MSO_SHAPE.ROUNDED_RECTANGLE,
        Inches(left), Inches(top), Inches(width), Inches(height)
    )
    shape.fill.solid()
    shape.fill.fore_color.rgb = fill_color
    shape.line.fill.background()
    if text:
        tf = shape.text_frame
        tf.word_wrap = True
        tf.paragraphs[0].alignment = PP_ALIGN.CENTER
        tf.paragraphs[0].text = text
        tf.paragraphs[0].font.size = Pt(font_size)
        tf.paragraphs[0].font.color.rgb = font_color
        tf.paragraphs[0].font.bold = bold
        tf.paragraphs[0].font.name = "Calibri"
        shape.text_frame.paragraphs[0].space_before = Pt(4)
    return shape


# ============================================================
# SLIDE 1: Title slide
# ============================================================
slide = prs.slides.add_slide(prs.slide_layouts[6])  # blank
add_bg(slide, DARK_BLUE)

add_text_box(slide, 1, 1.5, 11.3, 1.5,
             "De Novo Genome Assembly Plan",
             font_size=44, color=WHITE, bold=True, alignment=PP_ALIGN.CENTER)
add_text_box(slide, 1, 3.0, 11.3, 1.0,
             "Spalangia cameroni (Hymenoptera: Pteromalidae)",
             font_size=28, color=LIGHT_BLUE, bold=False, alignment=PP_ALIGN.CENTER)
add_text_box(slide, 1, 4.2, 11.3, 0.5,
             "Pupal parasitoid of filth flies  |  Biological control agent",
             font_size=18, color=RGBColor(0xAA, 0xCC, 0xEE), bold=False, alignment=PP_ALIGN.CENTER)

# Bottom info
add_text_box(slide, 1, 5.8, 11.3, 0.4,
             "Sample: GMCF_3514_04  |  PacBio Revio HiFi + Illumina NovaSeq X",
             font_size=16, color=RGBColor(0x88, 0xAA, 0xCC), alignment=PP_ALIGN.CENTER)
add_text_box(slide, 1, 6.3, 11.3, 0.4,
             "April 2026",
             font_size=14, color=RGBColor(0x88, 0xAA, 0xCC), alignment=PP_ALIGN.CENTER)

# ============================================================
# SLIDE 2: Project Overview & Current Status
# ============================================================
slide = prs.slides.add_slide(prs.slide_layouts[6])
add_bg(slide, WHITE)

add_text_box(slide, 0.5, 0.3, 12, 0.7,
             "Project Overview & Current Status",
             font_size=32, color=DARK_BLUE, bold=True)

# Left column - Project info
add_rounded_rect(slide, 0.5, 1.2, 6, 0.5, MED_BLUE, "Project Information", 16, WHITE, True)
add_bullet_slide(slide, 0.7, 1.8, 5.8, 3.5, [
    "Species: Spalangia cameroni (Pteromalidae, Chalcidoidea)",
    "Significance: Key biocontrol agent against house flies & stable flies",
    "Goal: High-quality contig-level de novo genome assembly",
    "No reference genome currently exists for this species",
    "Assembly type: Contig-level (Hi-C not available)",
    "Expected genome size: 200-400 Mb (based on related Chalcidoidea)",
], font_size=15, color=DARK_GRAY)

# Right column - Data status
add_rounded_rect(slide, 6.8, 1.2, 6, 0.5, ACCENT_GREEN, "Available Data (Sample GMCF_3514_04)", 16, WHITE, True)
add_bullet_slide(slide, 7.0, 1.8, 5.8, 2.0, [
    "PacBio Revio HiFi reads (SMRTbell 3.0, 30h movie)",
    "  File: GMCF_3514_04.107_107.fastq",
    "Illumina NovaSeq X paired-end short reads",
    "  Files: GMCF_3514_04_shortread_S309_L007_R1/R2_001.fastq.gz",
], font_size=15, color=DARK_GRAY)

add_rounded_rect(slide, 6.8, 4.0, 6, 0.5, ACCENT_ORANGE, "Public RNA-Seq (BioProject PRJNA252176)", 16, WHITE, True)
add_bullet_slide(slide, 7.0, 4.6, 5.8, 2.0, [
    "Raw reads: SRR1502981 (~8.5M paired-end reads, S. cameroni)",
    "TSA transcripts: GBVV01000000 (27,735 contigs, ~25.7 Mb)",
    "Must cite original BioProject in methods",
], font_size=15, color=DARK_GRAY)

# Status box
add_rounded_rect(slide, 0.5, 5.5, 12.3, 0.6, LIGHT_BLUE,
                 "STATUS: Data available. Ready to begin Phase 1 (QC & Genome Survey).", 16, WHITE, True)

# Unknown items
add_text_box(slide, 0.5, 6.3, 12, 0.5,
             "To determine: Read type confirmation (HiFi vs CLR)  |  Sample sex (haploid male vs diploid female)  |  Exact sequencing depth",
             font_size=13, color=MED_GRAY)

# ============================================================
# SLIDE 3: Pipeline Overview
# ============================================================
slide = prs.slides.add_slide(prs.slide_layouts[6])
add_bg(slide, WHITE)

add_text_box(slide, 0.5, 0.3, 12, 0.7,
             "Assembly Pipeline Overview",
             font_size=32, color=DARK_BLUE, bold=True)

# Pipeline boxes - arranged as flowchart
phases = [
    ("Phase 1", "QC & Genome Survey", MED_BLUE, 0.5, 1.3),
    ("Phase 2", "Contig Assembly", MED_BLUE, 3.2, 1.3),
    ("Phase 3", "Polishing", MED_BLUE, 5.9, 1.3),
    ("Phase 4", "Decontamination", MED_BLUE, 8.6, 1.3),
    ("Phase 5", "Hi-C Scaffolding", RGBColor(0x99, 0x99, 0x99), 11.3, 1.3),
]

for phase_name, phase_desc, color, left, top in phases:
    add_rounded_rect(slide, left, top, 2.4, 0.45, color, phase_name, 14, WHITE, True)
    add_text_box(slide, left, top + 0.5, 2.4, 0.35, phase_desc,
                 font_size=12, color=DARK_GRAY, alignment=PP_ALIGN.CENTER)

phases2 = [
    ("Phase 6", "Quality Assessment", ACCENT_GREEN, 0.5, 2.5),
    ("Phase 7", "Genome Annotation", ACCENT_GREEN, 3.2, 2.5),
    ("Phase 8", "Biological Analyses", ACCENT_GREEN, 5.9, 2.5),
]
for phase_name, phase_desc, color, left, top in phases2:
    add_rounded_rect(slide, left, top, 2.4, 0.45, color, phase_name, 14, WHITE, True)
    add_text_box(slide, left, top + 0.5, 2.4, 0.35, phase_desc,
                 font_size=12, color=DARK_GRAY, alignment=PP_ALIGN.CENTER)

# Note about Hi-C
add_text_box(slide, 11.0, 1.9, 2.8, 0.4, "(Not planned - optional)",
             font_size=11, color=MED_GRAY, alignment=PP_ALIGN.CENTER)

# Detailed tool mapping
add_rounded_rect(slide, 0.5, 3.5, 12.3, 0.5, DARK_BLUE, "Tools & Software per Phase", 16, WHITE, True)

tool_data = [
    ("Phase 1: QC", "seqkit, NanoPlot, fastp, FastQC, Jellyfish, GenomeScope 2.0"),
    ("Phase 2: Assembly", "hifiasm (HiFi) or Flye (CLR), purge_dups, minimap2"),
    ("Phase 3: Polish", "NextPolish (2 rounds), BWA-MEM, samtools"),
    ("Phase 4: Decontam.", "BlobTools2, BLAST (nt database), samtools"),
    ("Phase 6: QC", "BUSCO v5 (hymenoptera_odb10), QUAST, Merqury, meryl"),
    ("Phase 7: Annotate", "RepeatModeler2, RepeatMasker, HISAT2, BRAKER3, eggNOG-mapper, InterProScan"),
    ("Phase 8: Biology", "MITOS2 (mitogenome), MCScanX/GENESPACE (synteny)"),
]

for i, (phase, tools) in enumerate(tool_data):
    y = 4.15 + i * 0.4
    add_text_box(slide, 0.7, y, 2.5, 0.35, phase, font_size=13, color=MED_BLUE, bold=True)
    add_text_box(slide, 3.2, y, 9.5, 0.35, tools, font_size=13, color=DARK_GRAY)

# ============================================================
# SLIDE 4: Phase 1 - QC & Genome Survey
# ============================================================
slide = prs.slides.add_slide(prs.slide_layouts[6])
add_bg(slide, WHITE)

add_text_box(slide, 0.5, 0.3, 12, 0.7,
             "Phase 1: Raw Data QC & Genome Survey",
             font_size=32, color=DARK_BLUE, bold=True)

# Step 1.1
add_rounded_rect(slide, 0.5, 1.2, 3.8, 0.45, MED_BLUE, "Step 1.1: PacBio Read QC", 14, WHITE, True)
add_bullet_slide(slide, 0.7, 1.75, 3.6, 2.0, [
    "Confirm HiFi vs CLR read type",
    "Read length distribution & quality",
    "Total yield & depth estimation",
    "Tools: seqkit stats, NanoPlot",
    "Target: >=30x HiFi depth",
], font_size=13, color=DARK_GRAY, spacing=Pt(3))

# Step 1.2
add_rounded_rect(slide, 4.6, 1.2, 3.8, 0.45, MED_BLUE, "Step 1.2: Illumina Read QC", 14, WHITE, True)
add_bullet_slide(slide, 4.8, 1.75, 3.6, 2.0, [
    "Quality assessment & adapter trimming",
    "Remove low-quality bases",
    "Clean reads for k-mer profiling",
    "Tools: FastQC, fastp",
    "Output: trimmed_R1/R2.fastq.gz",
], font_size=13, color=DARK_GRAY, spacing=Pt(3))

# Step 1.3
add_rounded_rect(slide, 8.7, 1.2, 4.1, 0.45, MED_BLUE, "Step 1.3: K-mer Genome Survey", 14, WHITE, True)
add_bullet_slide(slide, 8.9, 1.75, 3.9, 2.0, [
    "K-mer counting (k=21) from Illumina",
    "Model genome properties:",
    "  - Genome size estimate",
    "  - Heterozygosity level",
    "  - Repetitive content %",
    "  - Ploidy (haploid vs diploid)",
    "Tools: Jellyfish + GenomeScope 2.0",
], font_size=13, color=DARK_GRAY, spacing=Pt(3))

# Key decisions box
add_rounded_rect(slide, 0.5, 4.5, 12.3, 0.45, ACCENT_ORANGE,
                 "Key Decisions After Phase 1", 14, WHITE, True)
add_bullet_slide(slide, 0.7, 5.1, 12, 2.0, [
    "If HiFi confirmed: proceed with hifiasm (expected path based on Revio + SMRTbell 3.0 protocol)",
    "If CLR: switch to Flye/NextDenovo, plan additional polishing rounds",
    "If high heterozygosity: thorough haplotig purging will be essential",
    "If low depth (<30x): assembly may be fragmented; consider if additional sequencing is needed",
], font_size=14, color=DARK_GRAY, spacing=Pt(4))

# ============================================================
# SLIDE 5: Phase 2 & 3 - Assembly & Polishing
# ============================================================
slide = prs.slides.add_slide(prs.slide_layouts[6])
add_bg(slide, WHITE)

add_text_box(slide, 0.5, 0.3, 12, 0.7,
             "Phase 2-3: Contig Assembly & Polishing",
             font_size=32, color=DARK_BLUE, bold=True)

# Assembly
add_rounded_rect(slide, 0.5, 1.2, 6, 0.45, MED_BLUE, "Phase 2: Contig Assembly", 15, WHITE, True)
add_bullet_slide(slide, 0.7, 1.8, 5.8, 3.5, [
    "Step 2.1 - Primary Assembly:",
    "  HiFi path: hifiasm (gold standard for HiFi data)",
    "  CLR path: Flye or NextDenovo (fallback)",
    "  hifiasm resolves heterozygosity natively",
    "",
    "Step 2.2 - Haplotig Purging:",
    "  Tool: purge_dups",
    "  Remove redundant alternate allelic contigs",
    "  Checkpoint: assembly size vs GenomeScope estimate",
    "  Success = within 10% agreement",
], font_size=14, color=DARK_GRAY, spacing=Pt(3))

# Polishing
add_rounded_rect(slide, 6.8, 1.2, 6, 0.45, ACCENT_GREEN, "Phase 3: Illumina Polishing", 15, WHITE, True)
add_bullet_slide(slide, 7.0, 1.8, 5.8, 3.5, [
    "Step 3.1 - Error Correction (2 rounds):",
    "  Tool: NextPolish (preferred) or Pilon",
    "  Corrects indels & single-base errors",
    "  Even HiFi (~Q30) has homopolymer errors",
    "  Illumina reads (Q30-Q40) provide orthogonal accuracy",
    "",
    "  Round 1: Major error correction",
    "  Round 2: Residual cleanup",
    "",
    "  Note: For HiFi, 1 round may suffice",
    "  For CLR, 2 rounds strongly recommended",
], font_size=14, color=DARK_GRAY, spacing=Pt(3))

# Expected output
add_rounded_rect(slide, 0.5, 5.8, 12.3, 0.5, DARK_BLUE,
                 "Expected Output: Polished, purged contig assembly (est. 200-400 Mb, N50 in Mb range)",
                 14, WHITE, True)

# ============================================================
# SLIDE 6: Phase 4 & 6 - Decontamination & QC
# ============================================================
slide = prs.slides.add_slide(prs.slide_layouts[6])
add_bg(slide, WHITE)

add_text_box(slide, 0.5, 0.3, 12, 0.7,
             "Phase 4 & 6: Decontamination & Quality Assessment",
             font_size=32, color=DARK_BLUE, bold=True)

# Decontamination
add_rounded_rect(slide, 0.5, 1.2, 6, 0.45, ACCENT_RED, "Phase 4: Contamination Screening", 15, WHITE, True)
add_bullet_slide(slide, 0.7, 1.8, 5.8, 3.0, [
    "Why: Parasitoid wasps harbor Wolbachia, Cardinium",
    "   & other endosymbionts that contaminate assembly",
    "",
    "Pipeline:",
    "  1. Map PacBio reads back (minimap2) for coverage",
    "  2. BLAST contigs vs NCBI nt database",
    "  3. BlobTools2: GC + coverage + taxonomy plots",
    "",
    "Actions:",
    "  - Remove bacterial/endosymbiont contigs",
    "  - Separate mitochondrial contigs (for mitogenome)",
    "  - Flag contigs with aberrant GC content",
], font_size=14, color=DARK_GRAY, spacing=Pt(2))

# QC
add_rounded_rect(slide, 6.8, 1.2, 6, 0.45, ACCENT_GREEN, "Phase 6: Quality Assessment", 15, WHITE, True)
add_bullet_slide(slide, 7.0, 1.8, 5.8, 3.0, [
    "BUSCO v5 (hymenoptera_odb10):",
    "  - Target: >=95% completeness",
    "  - Measures gene-level assembly quality",
    "",
    "QUAST:",
    "  - N50, L50, total size, # contigs, GC%",
    "  - Contiguity statistics",
    "",
    "Merqury (k-mer completeness):",
    "  - QV score (target: >=40 = 1 error/10,000 bp)",
    "  - Assembly completeness independent of genes",
], font_size=14, color=DARK_GRAY, spacing=Pt(2))

# Quality targets
add_rounded_rect(slide, 0.5, 5.5, 12.3, 0.5, DARK_BLUE,
                 "Quality Targets: BUSCO >=95%  |  QV >=40  |  Assembly size matching k-mer estimate",
                 14, WHITE, True)

# ============================================================
# SLIDE 7: Phase 7 - Annotation
# ============================================================
slide = prs.slides.add_slide(prs.slide_layouts[6])
add_bg(slide, WHITE)

add_text_box(slide, 0.5, 0.3, 12, 0.7,
             "Phase 7: Genome Annotation",
             font_size=32, color=DARK_BLUE, bold=True)

# Repeat annotation
add_rounded_rect(slide, 0.5, 1.2, 4.0, 0.45, MED_BLUE, "7.1: Repeat Masking", 14, WHITE, True)
add_bullet_slide(slide, 0.7, 1.75, 3.8, 1.8, [
    "RepeatModeler2: de novo TE library",
    "RepeatMasker: soft-mask genome",
    "Expected: 20-55% repetitive",
    "Output: masked genome for BRAKER",
], font_size=13, color=DARK_GRAY, spacing=Pt(3))

# RNA-Seq
add_rounded_rect(slide, 4.7, 1.2, 4.0, 0.45, ACCENT_ORANGE,
                 "7.2-7.3: RNA-Seq Evidence", 14, WHITE, True)
add_bullet_slide(slide, 4.9, 1.75, 3.8, 1.8, [
    "Download SRR1502981 (S. cameroni)",
    "  + TSA contigs GBVV01000000",
    "QC with fastp",
    "Align: HISAT2 (reads) + minimap2 (TSA)",
    "Cite BioProject PRJNA252176",
], font_size=13, color=DARK_GRAY, spacing=Pt(3))

# Gene prediction
add_rounded_rect(slide, 8.9, 1.2, 3.9, 0.45, ACCENT_GREEN, "7.4: Gene Prediction", 14, WHITE, True)
add_bullet_slide(slide, 9.1, 1.75, 3.7, 1.8, [
    "BRAKER3: 3 evidence streams",
    "  1. RNA-Seq BAM alignments",
    "  2. Protein homology (Hymenoptera)",
    "  3. Ab initio (GeneMark-ETP)",
    "Re-run when own RNA-Seq arrives",
], font_size=13, color=DARK_GRAY, spacing=Pt(3))

# Functional annotation
add_rounded_rect(slide, 0.5, 3.8, 12.3, 0.45, MED_BLUE, "7.5: Functional Annotation", 14, WHITE, True)
add_bullet_slide(slide, 0.7, 4.35, 12, 1.5, [
    "eggNOG-mapper: GO terms, KEGG pathways, COG categories",
    "InterProScan: Protein domains (Pfam, PANTHER, etc.)",
    "Diamond vs UniProt/Swiss-Prot: Curated functional assignments",
], font_size=14, color=DARK_GRAY, spacing=Pt(4))

# ============================================================
# SLIDE 8: Phase 8 - Biological Analyses
# ============================================================
slide = prs.slides.add_slide(prs.slide_layouts[6])
add_bg(slide, WHITE)

add_text_box(slide, 0.5, 0.3, 12, 0.7,
             "Phase 8: Biological Analyses & Comparative Genomics",
             font_size=32, color=DARK_BLUE, bold=True)

# Three columns
add_rounded_rect(slide, 0.5, 1.2, 3.8, 0.45, MED_BLUE, "8.1: Mitogenome", 14, WHITE, True)
add_bullet_slide(slide, 0.7, 1.8, 3.6, 2.0, [
    "Circularize mito contig",
    "  (identified in Phase 4)",
    "Annotate with MITOS2",
    "Useful phylogenetic marker",
    "Separate data resource",
], font_size=14, color=DARK_GRAY, spacing=Pt(3))

add_rounded_rect(slide, 4.6, 1.2, 3.8, 0.45, ACCENT_ORANGE, "8.2: Endosymbionts", 14, WHITE, True)
add_bullet_slide(slide, 4.8, 1.8, 3.6, 2.0, [
    "If Wolbachia/Cardinium found:",
    "  Assemble separately",
    "  Annotate symbiont genome",
    "  Biologically informative",
    "  (host-symbiont interactions)",
], font_size=14, color=DARK_GRAY, spacing=Pt(3))

add_rounded_rect(slide, 8.7, 1.2, 4.1, 0.45, ACCENT_GREEN, "8.3: Comparative Genomics", 14, WHITE, True)
add_bullet_slide(slide, 8.9, 1.8, 3.9, 2.0, [
    "Synteny with related genomes:",
    "  - Nasonia vitripennis (297 Mb)",
    "  - Eretmocerus hayati (692 Mb)",
    "Tools: MCScanX / GENESPACE",
    "Gene family expansions/contractions",
], font_size=14, color=DARK_GRAY, spacing=Pt(3))

# Comparative table
add_rounded_rect(slide, 0.5, 4.2, 12.3, 0.45, DARK_BLUE,
                 "Reference Assemblies for Comparison", 14, WHITE, True)

headers = ["Species", "Superfamily", "Size (Mb)", "Scaffold N50", "BUSCO %", "Chromosomes"]
col_widths = [2.8, 2.0, 1.2, 1.8, 1.2, 1.5]
x_start = 1.0
for i, (header, w) in enumerate(zip(headers, col_widths)):
    add_text_box(slide, x_start, 4.75, w, 0.3, header,
                 font_size=12, color=MED_BLUE, bold=True)
    x_start += w

rows = [
    ["Nasonia vitripennis", "Chalcidoidea", "297", "7.0 Mb", "98.4", "Yes"],
    ["Eretmocerus hayati", "Chalcidoidea", "692.1", "192.5 Mb", "95.9", "Yes (n=4)"],
    ["Chelonus formosanus", "Ichneumonoidea", "139.6", "24.16 Mb", "99.0", "Yes (n=7)"],
    ["Aenasius arizonensis", "Chalcidoidea", "398.7", "35.96 Mb", "97.1", "Yes (n=11)"],
]
for j, row in enumerate(rows):
    x_start = 1.0
    for i, (val, w) in enumerate(zip(row, col_widths)):
        add_text_box(slide, x_start, 5.1 + j * 0.35, w, 0.3, val,
                     font_size=11, color=DARK_GRAY)
        x_start += w

# ============================================================
# SLIDE 9: Summary & Next Steps
# ============================================================
slide = prs.slides.add_slide(prs.slide_layouts[6])
add_bg(slide, DARK_BLUE)

add_text_box(slide, 0.5, 0.4, 12, 0.7,
             "Summary & Next Steps",
             font_size=32, color=WHITE, bold=True)

# Current status
add_rounded_rect(slide, 0.5, 1.3, 5.9, 0.45, ACCENT_GREEN, "What We Have", 15, WHITE, True)
add_bullet_slide(slide, 0.7, 1.9, 5.7, 2.2, [
    "PacBio Revio HiFi reads (sample 04)",
    "Illumina NovaSeq X paired-end reads (sample 04)",
    "Public RNA-Seq from S. cameroni (SRR1502981)",
    "TSA assembled transcripts (GBVV01000000)",
    "Comprehensive assembly plan (8 phases)",
], font_size=14, color=RGBColor(0xDD, 0xDD, 0xDD), spacing=Pt(4))

# What's needed
add_rounded_rect(slide, 6.8, 1.3, 5.9, 0.45, ACCENT_ORANGE, "To Determine / Decide", 15, WHITE, True)
add_bullet_slide(slide, 7.0, 1.9, 5.7, 2.2, [
    "Confirm HiFi read type (expected from Revio protocol)",
    "Sample sex: haploid male or diploid female?",
    "Actual sequencing depth (Phase 1 will reveal)",
    "Future: own RNA-Seq for improved annotation",
    "Future: Hi-C for chromosome-level (if desired)",
], font_size=14, color=RGBColor(0xDD, 0xDD, 0xDD), spacing=Pt(4))

# Immediate next steps
add_rounded_rect(slide, 0.5, 4.5, 12.3, 0.45, WHITE,
                 "Immediate Next Steps", 15, DARK_BLUE, True)
add_bullet_slide(slide, 0.7, 5.1, 12, 2.0, [
    "1. Run seqkit stats + NanoPlot on PacBio reads to confirm read type and depth",
    "2. Run fastp on Illumina reads for trimming/QC",
    "3. Run Jellyfish + GenomeScope 2.0 for genome size estimation",
    "4. Begin hifiasm assembly (once HiFi confirmed and depth verified)",
], font_size=15, color=RGBColor(0xCC, 0xCC, 0xCC), spacing=Pt(5))


# Save
output_path = "/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly/Spalangia_cameroni_assembly_plan.pptx"
prs.save(output_path)
print(f"Presentation saved to: {output_path}")
