#!/usr/bin/env python3
"""
Add GenomeScope 2.0 k-mer survey results slides to Spalangia cameroni assembly plan.
Adds 4 new slides (14-17) with GenomeScope results, plots, NanoPlot images, and Phase 1 summary.
"""

from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.enum.shapes import MSO_SHAPE
import os

# ── Constants ──────────────────────────────────────────────────────────────
PPTX_FILE = "Spalangia_cameroni_assembly_plan.pptx"
BASE_DIR = "/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly"

DARK_BLUE  = RGBColor(0x1B, 0x3A, 0x5C)
MED_BLUE   = RGBColor(0x2E, 0x6B, 0x9E)
ACCENT_GREEN  = RGBColor(0x27, 0xAE, 0x60)
ACCENT_ORANGE = RGBColor(0xE6, 0x7E, 0x22)
ACCENT_RED    = RGBColor(0xC0, 0x39, 0x2B)
WHITE      = RGBColor(0xFF, 0xFF, 0xFF)
DARK_GRAY  = RGBColor(0x33, 0x33, 0x33)
LIGHT_GRAY = RGBColor(0xF0, 0xF0, 0xF0)
TABLE_HEADER_BG = RGBColor(0x1B, 0x3A, 0x5C)
TABLE_ALT_BG    = RGBColor(0xE8, 0xF0, 0xF8)

FONT_NAME = "Calibri"

# Plot paths
GENOMESCOPE_LINEAR = os.path.join(BASE_DIR, "qc/genomescope/linear_plot.png")
GENOMESCOPE_LOG    = os.path.join(BASE_DIR, "qc/genomescope/log_plot.png")
NANOPLOT_HIST      = os.path.join(BASE_DIR, "qc/nanoplot_pacbio/WeightedHistogramReadlength.png")
NANOPLOT_KDE       = os.path.join(BASE_DIR, "qc/nanoplot_pacbio/LengthvsQualityScatterPlot_kde.png")


# ── Helpers ────────────────────────────────────────────────────────────────
def add_slide(prs):
    """Add a blank slide."""
    layout = prs.slide_layouts[6]  # Blank
    return prs.slides.add_slide(layout)


def add_title(slide, text, left=457200, top=274320, width=10972800, height=640080):
    """Add slide title text box matching existing style."""
    txBox = slide.shapes.add_textbox(left, top, width, height)
    tf = txBox.text_frame
    tf.word_wrap = True
    p = tf.paragraphs[0]
    p.text = text
    p.font.name = FONT_NAME
    p.font.size = Pt(28)
    p.font.bold = True
    p.font.color.rgb = DARK_BLUE
    return txBox


def add_rounded_rect(slide, text, left, top, width, height, fill_color=DARK_BLUE, font_size=Pt(14)):
    """Add a rounded rectangle header/badge."""
    shape = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, left, top, width, height)
    shape.fill.solid()
    shape.fill.fore_color.rgb = fill_color
    shape.line.fill.background()
    tf = shape.text_frame
    tf.word_wrap = True
    tf.paragraphs[0].alignment = PP_ALIGN.CENTER
    p = tf.paragraphs[0]
    p.text = text
    p.font.name = FONT_NAME
    p.font.size = font_size
    p.font.bold = True
    p.font.color.rgb = WHITE
    return shape


def add_textbox(slide, text, left, top, width, height, font_size=Pt(11),
                color=DARK_GRAY, bold=False, alignment=PP_ALIGN.LEFT):
    """Add a text box with consistent styling."""
    txBox = slide.shapes.add_textbox(left, top, width, height)
    tf = txBox.text_frame
    tf.word_wrap = True
    p = tf.paragraphs[0]
    p.text = text
    p.font.name = FONT_NAME
    p.font.size = font_size
    p.font.color.rgb = color
    p.font.bold = bold
    p.alignment = alignment
    return txBox


def add_multiline_textbox(slide, lines, left, top, width, height, font_size=Pt(11),
                          color=DARK_GRAY):
    """Add a text box with multiple lines."""
    txBox = slide.shapes.add_textbox(left, top, width, height)
    tf = txBox.text_frame
    tf.word_wrap = True
    for i, line in enumerate(lines):
        if i == 0:
            p = tf.paragraphs[0]
        else:
            p = tf.add_paragraph()
        p.text = line
        p.font.name = FONT_NAME
        p.font.size = font_size
        p.font.color.rgb = color
        p.space_after = Pt(4)
    return txBox


def set_cell(cell, text, font_size=Pt(10), bold=False, color=DARK_GRAY,
             fill_color=None, alignment=PP_ALIGN.LEFT):
    """Format a table cell."""
    cell.text = ""
    p = cell.text_frame.paragraphs[0]
    p.text = text
    p.font.name = FONT_NAME
    p.font.size = font_size
    p.font.bold = bold
    p.font.color.rgb = color
    p.alignment = alignment
    cell.vertical_anchor = MSO_ANCHOR.MIDDLE
    if fill_color:
        cell.fill.solid()
        cell.fill.fore_color.rgb = fill_color
    # Margins
    cell.margin_left = Emu(91440)
    cell.margin_right = Emu(91440)
    cell.margin_top = Emu(45720)
    cell.margin_bottom = Emu(45720)


def add_table(slide, rows, cols, left, top, width, height):
    """Add a table shape."""
    table_shape = slide.shapes.add_table(rows, cols, left, top, width, height)
    return table_shape.table


# ── Slide 14: GenomeScope Results + Coverage ──────────────────────────────
def add_genomescope_results_slide(prs):
    slide = add_slide(prs)

    add_title(slide, "GenomeScope 2.0 K-mer Survey Results (k=21)")

    # -- Left side: GenomeScope table --
    add_rounded_rect(slide, "Genome Properties (Illumina k-mer model)",
                     457200, 1097280, 5486400, 411480)

    genomescope_data = [
        ("Property", "Min", "Max"),
        ("Haploid Length", "654,013,404 bp", "655,911,420 bp"),
        ("Homozygous (%)", "99.43%", "99.46%"),
        ("Heterozygous (%)", "0.54%", "0.57%"),
        ("Repeat Length", "228 Mb (~35%)", "229 Mb (~35%)"),
        ("Unique Length", "426 Mb", "427 Mb"),
        ("Model Fit", "68.1%", "95.9%"),
        ("Read Error Rate", "0.148%", "0.148%"),
        ("K-mer Coverage", "30.7x", "30.7x"),
    ]

    tbl = add_table(slide, len(genomescope_data), 3,
                    457200, 1645920, 5486400, len(genomescope_data) * 365760)

    # Set column widths
    tbl.columns[0].width = Emu(2194560)
    tbl.columns[1].width = Emu(1645920)
    tbl.columns[2].width = Emu(1645920)

    for r, row_data in enumerate(genomescope_data):
        for c, val in enumerate(row_data):
            if r == 0:
                set_cell(tbl.cell(r, c), val, font_size=Pt(10), bold=True,
                         color=WHITE, fill_color=TABLE_HEADER_BG,
                         alignment=PP_ALIGN.CENTER)
            else:
                bg = TABLE_ALT_BG if r % 2 == 0 else WHITE
                bold = (c == 0)
                set_cell(tbl.cell(r, c), val, font_size=Pt(10), bold=bold,
                         color=DARK_GRAY, fill_color=bg,
                         alignment=PP_ALIGN.CENTER if c > 0 else PP_ALIGN.LEFT)

    # -- Right side: Coverage Analysis --
    add_rounded_rect(slide, "Coverage Analysis",
                     6217920, 1097280, 5486400, 411480)

    coverage_data = [
        ("Data Type", "Total Bases", "Est. Coverage", "Status"),
        ("PacBio HiFi", "7.88 Gb", "~12x", "LOW"),
        ("Illumina", "52.33 Gb", "~80x", "GOOD"),
    ]

    tbl2 = add_table(slide, len(coverage_data), 4,
                     6217920, 1645920, 5486400, len(coverage_data) * 411480)

    tbl2.columns[0].width = Emu(1371600)
    tbl2.columns[1].width = Emu(1371600)
    tbl2.columns[2].width = Emu(1371600)
    tbl2.columns[3].width = Emu(1371600)

    for r, row_data in enumerate(coverage_data):
        for c, val in enumerate(row_data):
            if r == 0:
                set_cell(tbl2.cell(r, c), val, font_size=Pt(10), bold=True,
                         color=WHITE, fill_color=TABLE_HEADER_BG,
                         alignment=PP_ALIGN.CENTER)
            else:
                color = DARK_GRAY
                if c == 3 and val == "LOW":
                    color = ACCENT_RED
                elif c == 3 and val == "GOOD":
                    color = ACCENT_GREEN
                set_cell(tbl2.cell(r, c), val, font_size=Pt(10),
                         bold=(c == 0 or c == 3),
                         color=color, fill_color=WHITE,
                         alignment=PP_ALIGN.CENTER)

    # WARNING badge for low PacBio coverage
    add_rounded_rect(slide, "WARNING: PacBio HiFi coverage ~12x is LOW (ideal: 30x+)",
                     6217920, 2743200, 5486400, 457200,
                     fill_color=ACCENT_RED, font_size=Pt(12))

    # Coverage notes
    add_multiline_textbox(slide, [
        "PacBio HiFi: 7.88 Gb / 655 Mb = ~12x coverage",
        "  Ideal HiFi coverage: 25-30x for de novo assembly",
        "  12x may produce fragmented contigs",
        "",
        "Illumina: 52.33 Gb / 655 Mb = ~80x coverage",
        "  Excellent depth for polishing & k-mer analysis",
        "",
        "Recommendation: Proceed with assembly, but expect",
        "  reduced contiguity. Consider additional sequencing.",
    ], 6217920, 3383280, 5486400, 2743200, font_size=Pt(10))

    # Key findings box at bottom
    add_rounded_rect(slide, "Key Findings: ~655 Mb genome  |  Very low heterozygosity (0.55%)  |  ~35% repeats  |  HiFi coverage is limiting factor",
                     457200, 6217920, 11247120, 457200,
                     fill_color=MED_BLUE, font_size=Pt(11))


# ── Slide 15: GenomeScope Plots ───────────────────────────────────────────
def add_genomescope_plots_slide(prs):
    slide = add_slide(prs)

    add_title(slide, "GenomeScope 2.0 K-mer Frequency Plots")

    # Left plot: linear
    add_rounded_rect(slide, "Linear Scale K-mer Plot",
                     457200, 1097280, 5486400, 411480)

    if os.path.exists(GENOMESCOPE_LINEAR):
        slide.shapes.add_picture(GENOMESCOPE_LINEAR,
                                 457200, 1600200, 5486400, 4389120)
    else:
        add_textbox(slide, "[linear_plot.png not found]",
                    457200, 3200400, 5486400, 457200, font_size=Pt(14),
                    color=ACCENT_RED, alignment=PP_ALIGN.CENTER)

    # Right plot: log
    add_rounded_rect(slide, "Log Scale K-mer Plot",
                     6217920, 1097280, 5486400, 411480)

    if os.path.exists(GENOMESCOPE_LOG):
        slide.shapes.add_picture(GENOMESCOPE_LOG,
                                 6217920, 1600200, 5486400, 4389120)
    else:
        add_textbox(slide, "[log_plot.png not found]",
                    6217920, 3200400, 5486400, 457200, font_size=Pt(14),
                    color=ACCENT_RED, alignment=PP_ALIGN.CENTER)

    # Caption
    add_multiline_textbox(slide, [
        "Illumina reads used for k-mer counting (k=21, Jellyfish 2.0). "
        "GenomeScope 2.0 models heterozygosity, repeat content, and genome size from the k-mer frequency spectrum.",
        "The main peak at ~31x represents homozygous k-mers. "
        "No visible heterozygous peak, consistent with very low heterozygosity (0.55%).",
    ], 457200, 6080760, 11247120, 640080, font_size=Pt(9))


# ── Slide 16: NanoPlot Visualizations ─────────────────────────────────────
def add_nanoplot_slide(prs):
    slide = add_slide(prs)

    add_title(slide, "PacBio HiFi Read Quality Visualizations (NanoPlot)")

    # Left: Read length histogram
    add_rounded_rect(slide, "Weighted Read Length Distribution",
                     457200, 1097280, 5486400, 411480)

    if os.path.exists(NANOPLOT_HIST):
        slide.shapes.add_picture(NANOPLOT_HIST,
                                 457200, 1600200, 5486400, 4389120)
    else:
        add_textbox(slide, "[WeightedHistogramReadlength.png not found]",
                    457200, 3200400, 5486400, 457200, font_size=Pt(14),
                    color=ACCENT_RED, alignment=PP_ALIGN.CENTER)

    # Right: Length vs Quality KDE
    add_rounded_rect(slide, "Read Length vs Quality (KDE)",
                     6217920, 1097280, 5486400, 411480)

    if os.path.exists(NANOPLOT_KDE):
        slide.shapes.add_picture(NANOPLOT_KDE,
                                 6217920, 1600200, 5486400, 4389120)
    else:
        add_textbox(slide, "[LengthvsQualityScatterPlot_kde.png not found]",
                    6217920, 3200400, 5486400, 457200, font_size=Pt(14),
                    color=ACCENT_RED, alignment=PP_ALIGN.CENTER)

    # Caption
    add_multiline_textbox(slide, [
        "PacBio HiFi reads from Revio platform (SMRTbell 3.0 library, 30-hour movie). "
        "604,048 reads with mean length 13,043 bp and median quality Q37.1.",
        "Read length distribution peaks ~13 kb. Quality uniformly high (>Q30 for 76% of reads), confirming true HiFi consensus sequences.",
    ], 457200, 6080760, 11247120, 640080, font_size=Pt(9))


# ── Slide 17: Phase 1 Complete Summary ────────────────────────────────────
def add_phase1_summary_slide(prs):
    slide = add_slide(prs)

    add_title(slide, "Phase 1 Complete: QC & Genome Survey Summary")

    # Badge
    add_rounded_rect(slide, "PHASE 1 COMPLETE",
                     9601200, 320040, 2103120, 411480,
                     fill_color=ACCENT_GREEN, font_size=Pt(14))

    # -- Left: Key Metrics --
    add_rounded_rect(slide, "Key Metrics",
                     457200, 1097280, 5486400, 411480)

    metrics_data = [
        ("Parameter", "Value"),
        ("Genome Size (haploid)", "~655 Mb"),
        ("Heterozygosity", "0.54-0.57% (very low)"),
        ("Repeat Content", "~35% (~228-229 Mb)"),
        ("Unique Sequence", "~426-427 Mb"),
        ("PacBio HiFi Reads", "604,048 reads, 7.88 Gb"),
        ("PacBio Mean Length", "13,043 bp"),
        ("PacBio Mean Quality", "Q37.1"),
        ("PacBio Coverage", "~12x"),
        ("Illumina Reads", "173.2M pairs, 52.33 Gb"),
        ("Illumina Coverage", "~80x"),
        ("K-mer Error Rate", "0.148%"),
    ]

    tbl = add_table(slide, len(metrics_data), 2,
                    457200, 1645920, 5486400, len(metrics_data) * 320040)

    tbl.columns[0].width = Emu(2468880)
    tbl.columns[1].width = Emu(3017520)

    for r, row_data in enumerate(metrics_data):
        for c, val in enumerate(row_data):
            if r == 0:
                set_cell(tbl.cell(r, c), val, font_size=Pt(9), bold=True,
                         color=WHITE, fill_color=TABLE_HEADER_BG,
                         alignment=PP_ALIGN.CENTER)
            else:
                bg = TABLE_ALT_BG if r % 2 == 0 else WHITE
                set_cell(tbl.cell(r, c), val, font_size=Pt(9),
                         bold=(c == 0), color=DARK_GRAY, fill_color=bg,
                         alignment=PP_ALIGN.LEFT)

    # -- Right top: Implications --
    add_rounded_rect(slide, "Implications for Assembly",
                     6217920, 1097280, 5486400, 411480)

    add_multiline_textbox(slide, [
        "Genome Characteristics:",
        "  - 655 Mb is large for Chalcidoidea (cf. Nasonia 297 Mb)",
        "  - Similar to Eretmocerus hayati (692 Mb)",
        "  - Very low heterozygosity -> simpler haplotype phasing",
        "  - 35% repeats -> moderate repeat challenge",
        "",
        "Coverage Concerns:",
        "  - PacBio HiFi 12x is BELOW recommended 25-30x",
        "  - Will likely produce more fragmented assembly",
        "  - Contigs may break at long repeat regions",
        "  - Illumina 80x is sufficient for polishing",
    ], 6217920, 1645920, 5486400, 2286000, font_size=Pt(10))

    # WARNING badge
    add_rounded_rect(slide,
                     "WARNING: 12x HiFi may yield fragmented assembly",
                     6217920, 3931920, 5486400, 365760,
                     fill_color=ACCENT_RED, font_size=Pt(11))

    # -- Right bottom: Next Steps --
    add_rounded_rect(slide, "Next Steps: Phase 2 (Assembly)",
                     6217920, 4480560, 5486400, 411480,
                     fill_color=MED_BLUE)

    add_multiline_textbox(slide, [
        "1. Run hifiasm with HiFi reads (primary assembly)",
        "   - Use aggressive overlap settings for low coverage",
        "   - Consider: hifiasm -l 0 to disable purging",
        "2. Run purge_dups if needed (check for haplotigs)",
        "3. Assess assembly with QUAST & BUSCO",
        "4. If too fragmented: consider supplementing with",
        "   additional PacBio sequencing or ONT reads",
        "",
        "Alternative: Try Flye with --nano-hq mode as backup",
    ], 6217920, 5029200, 5486400, 1645920, font_size=Pt(10))

    # Bottom status bar
    add_rounded_rect(slide,
                     "Phase 1: COMPLETE  |  Phase 2 (hifiasm assembly): READY TO BEGIN  |  Risk: Low HiFi coverage may limit contiguity",
                     457200, 6400800, 11247120, 411480,
                     fill_color=DARK_BLUE, font_size=Pt(11))


# ── Main ──────────────────────────────────────────────────────────────────
def main():
    pptx_path = os.path.join(BASE_DIR, PPTX_FILE)
    prs = Presentation(pptx_path)

    print(f"Opened {PPTX_FILE} with {len(prs.slides)} slides")

    add_genomescope_results_slide(prs)
    add_genomescope_plots_slide(prs)
    add_nanoplot_slide(prs)
    add_phase1_summary_slide(prs)

    prs.save(pptx_path)
    print(f"Saved {PPTX_FILE} with {len(prs.slides)} slides")

    # Verify plots were embedded
    for name, path in [
        ("GenomeScope linear", GENOMESCOPE_LINEAR),
        ("GenomeScope log", GENOMESCOPE_LOG),
        ("NanoPlot histogram", NANOPLOT_HIST),
        ("NanoPlot KDE", NANOPLOT_KDE),
    ]:
        status = "EMBEDDED" if os.path.exists(path) else "NOT FOUND"
        print(f"  {name}: {status}")


if __name__ == "__main__":
    main()
