#!/usr/bin/env python3
"""Generate pipeline_report.html for S. cameroni genome assembly QC."""

import base64
import os
from pathlib import Path

BASE = Path("/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly")

def img_to_base64(relpath):
    p = BASE / relpath
    if not p.exists():
        return ""
    with open(p, "rb") as f:
        data = base64.b64encode(f.read()).decode()
    return f"data:image/png;base64,{data}"

# Load all images
pacbio_imgs = {
    "weighted_hist": img_to_base64("qc/nanoplot_pacbio/WeightedHistogramReadlength.png"),
    "length_vs_qual": img_to_base64("qc/nanoplot_pacbio/LengthvsQualityScatterPlot_kde.png"),
    "non_weighted_hist": img_to_base64("qc/nanoplot_pacbio/Non_weightedHistogramReadlength.png"),
    "yield_by_length": img_to_base64("qc/nanoplot_pacbio/Yield_By_Length.png"),
}

genomescope_imgs = {
    "linear": img_to_base64("qc/genomescope/linear_plot.png"),
    "log": img_to_base64("qc/genomescope/log_plot.png"),
    "transformed_linear": img_to_base64("qc/genomescope/transformed_linear_plot.png"),
    "transformed_log": img_to_base64("qc/genomescope/transformed_log_plot.png"),
}

html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>S. cameroni Genome Assembly Pipeline Report</title>
<style>
* {{ margin: 0; padding: 0; box-sizing: border-box; }}
body {{ font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #f0f2f5; color: #2c3e50; line-height: 1.6; }}
.header {{ background: linear-gradient(135deg, #1B3A5C 0%, #2c5f8a 100%); color: white; padding: 40px 0; text-align: center; }}
.header h1 {{ font-size: 2.2em; font-weight: 700; letter-spacing: -0.5px; }}
.header .subtitle {{ font-size: 1.1em; opacity: 0.85; margin-top: 8px; }}
.header .date {{ font-size: 0.95em; opacity: 0.7; margin-top: 4px; }}
.container {{ max-width: 1200px; margin: 0 auto; padding: 30px 20px; }}

/* Progress Tracker */
.progress-tracker {{ display: flex; justify-content: center; gap: 0; margin: -25px auto 30px; background: white; border-radius: 12px; box-shadow: 0 2px 12px rgba(0,0,0,0.08); padding: 20px 30px; max-width: 900px; position: relative; }}
.progress-step {{ flex: 1; text-align: center; position: relative; }}
.progress-step:not(:last-child)::after {{ content: ''; position: absolute; top: 18px; right: -50%; width: 100%; height: 3px; background: #27ae60; z-index: 0; }}
.progress-step .step-circle {{ width: 36px; height: 36px; border-radius: 50%; display: inline-flex; align-items: center; justify-content: center; font-weight: 700; font-size: 0.9em; position: relative; z-index: 1; }}
.progress-step.complete .step-circle {{ background: #27ae60; color: white; }}
.progress-step.pending .step-circle {{ background: #bdc3c7; color: white; }}
.progress-step:not(:last-child).pending::after {{ background: #bdc3c7; }}
.progress-step .step-label {{ display: block; font-size: 0.78em; color: #7f8c8d; margin-top: 6px; }}

/* Key Findings */
.key-findings {{ background: white; border-radius: 12px; box-shadow: 0 2px 12px rgba(0,0,0,0.08); padding: 28px 32px; margin-bottom: 30px; border-left: 5px solid #1B3A5C; }}
.key-findings h2 {{ font-size: 1.4em; color: #1B3A5C; margin-bottom: 16px; }}
.finding-item {{ display: flex; align-items: flex-start; gap: 12px; margin-bottom: 12px; padding: 10px 14px; border-radius: 8px; background: #f8f9fa; }}
.finding-item:last-child {{ margin-bottom: 0; }}

/* Badges */
.badge {{ display: inline-block; padding: 3px 12px; border-radius: 20px; font-size: 0.78em; font-weight: 700; text-transform: uppercase; letter-spacing: 0.5px; white-space: nowrap; }}
.badge-pass {{ background: #d4edda; color: #155724; }}
.badge-warning {{ background: #fff3cd; color: #856404; }}
.badge-fail {{ background: #f8d7da; color: #721c24; }}
.badge-info {{ background: #d1ecf1; color: #0c5460; }}

/* Cards */
.card {{ background: white; border-radius: 12px; box-shadow: 0 2px 12px rgba(0,0,0,0.08); margin-bottom: 30px; overflow: hidden; }}
.card-header {{ background: linear-gradient(135deg, #1B3A5C, #2c5f8a); color: white; padding: 18px 28px; font-size: 1.25em; font-weight: 600; display: flex; justify-content: space-between; align-items: center; }}
.card-body {{ padding: 28px; }}

/* Tables */
table {{ width: 100%; border-collapse: collapse; font-size: 0.92em; }}
th {{ background: #1B3A5C; color: white; text-align: left; padding: 12px 16px; font-weight: 600; }}
td {{ padding: 10px 16px; border-bottom: 1px solid #eee; }}
tr:nth-child(even) td {{ background: #f8f9fb; }}
tr:hover td {{ background: #edf2f7; }}
.metric-name {{ font-weight: 600; color: #1B3A5C; min-width: 180px; }}
.metric-value {{ font-family: 'Courier New', monospace; font-weight: 600; font-size: 1.05em; }}
.metric-desc {{ color: #7f8c8d; font-size: 0.88em; font-style: italic; }}

/* Images */
.plot-grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(480px, 1fr)); gap: 20px; margin-top: 20px; }}
.plot-container {{ background: #fafbfc; border: 1px solid #e8ecef; border-radius: 8px; padding: 12px; text-align: center; }}
.plot-container img {{ max-width: 100%; height: auto; border-radius: 4px; }}
.plot-container .plot-caption {{ font-size: 0.85em; color: #7f8c8d; margin-top: 8px; font-weight: 500; }}

/* Sub-sections */
.subsection {{ margin-top: 24px; }}
.subsection h3 {{ font-size: 1.05em; color: #1B3A5C; margin-bottom: 12px; padding-bottom: 6px; border-bottom: 2px solid #eee; }}

/* Coverage bar */
.cov-bar-wrap {{ width: 100%; background: #eee; border-radius: 6px; height: 22px; overflow: hidden; margin: 4px 0; }}
.cov-bar {{ height: 100%; border-radius: 6px; display: flex; align-items: center; padding-left: 8px; color: white; font-size: 0.8em; font-weight: 700; }}

/* Responsive */
@media (max-width: 768px) {{
    .plot-grid {{ grid-template-columns: 1fr; }}
    .header h1 {{ font-size: 1.5em; }}
    .progress-tracker {{ flex-direction: column; gap: 10px; }}
    .progress-step:not(:last-child)::after {{ display: none; }}
}}

/* Footer */
.footer {{ text-align: center; padding: 30px; color: #95a5a6; font-size: 0.85em; }}
</style>
</head>
<body>

<!-- HEADER -->
<div class="header">
    <h1>S. cameroni Genome Assembly Pipeline Report</h1>
    <div class="subtitle">Sample GMCF_3514_04 &nbsp;|&nbsp; PacBio Revio HiFi + Illumina NovaSeq X</div>
    <div class="date">April 2026</div>
</div>

<div class="container">

<!-- PROGRESS TRACKER -->
<div class="progress-tracker">
    <div class="progress-step complete">
        <span class="step-circle">1.1</span>
        <span class="step-label">PacBio HiFi QC</span>
    </div>
    <div class="progress-step complete">
        <span class="step-circle">1.2</span>
        <span class="step-label">Illumina QC</span>
    </div>
    <div class="progress-step complete">
        <span class="step-circle">1.3</span>
        <span class="step-label">K-mer Survey</span>
    </div>
    <div class="progress-step pending">
        <span class="step-circle">2</span>
        <span class="step-label">Assembly</span>
    </div>
    <div class="progress-step pending">
        <span class="step-circle">3</span>
        <span class="step-label">Polishing</span>
    </div>
    <div class="progress-step pending">
        <span class="step-circle">4</span>
        <span class="step-label">Scaffolding</span>
    </div>
</div>

<!-- KEY FINDINGS -->
<div class="key-findings">
    <h2>Key Findings</h2>
    <div class="finding-item">
        <span class="badge badge-pass">PASS</span>
        <div><strong>PacBio HiFi quality is excellent.</strong> 96.1% of reads are Q20+ and 76.1% are Q30+. Mean read length of 9,096 bp is suitable for genome assembly.</div>
    </div>
    <div class="finding-item">
        <span class="badge badge-pass">PASS</span>
        <div><strong>Illumina data is high quality.</strong> 98.76% of reads passed filtering. Q30 rates above 96% after trimming.</div>
    </div>
    <div class="finding-item">
        <span class="badge badge-warning">WARNING</span>
        <div><strong>PacBio HiFi coverage is low (~12x).</strong> Typical HiFi assemblies require 25-40x coverage. This may result in fragmented contigs. Consider supplementing with additional sequencing.</div>
    </div>
    <div class="finding-item">
        <span class="badge badge-pass">PASS</span>
        <div><strong>Illumina coverage is excellent (~80x).</strong> More than sufficient for polishing and error correction.</div>
    </div>
    <div class="finding-item">
        <span class="badge badge-info">INFO</span>
        <div><strong>Estimated genome size: ~655 Mb.</strong> Heterozygosity of 0.55% indicates a diploid genome with moderate divergence between haplotypes. Repeat content is ~35%.</div>
    </div>
</div>

<!-- PHASE 1.1: PacBio HiFi QC -->
<div class="card">
    <div class="card-header">
        Phase 1.1: PacBio HiFi QC
        <span class="badge badge-pass">PASS</span>
    </div>
    <div class="card-body">
        <table>
            <thead><tr><th>Metric</th><th>Value</th><th>Description</th></tr></thead>
            <tbody>
                <tr><td class="metric-name">Total Reads</td><td class="metric-value">866,363</td><td class="metric-desc">Number of CCS/HiFi reads generated from PacBio Revio</td></tr>
                <tr><td class="metric-name">Total Bases</td><td class="metric-value">7.88 Gb</td><td class="metric-desc">Total sequencing yield in gigabases</td></tr>
                <tr><td class="metric-name">Mean Read Length</td><td class="metric-value">9,096 bp</td><td class="metric-desc">Average length across all reads</td></tr>
                <tr><td class="metric-name">Median Read Length</td><td class="metric-value">8,678 bp</td><td class="metric-desc">Middle value of read length distribution</td></tr>
                <tr><td class="metric-name">Read N50</td><td class="metric-value">9,578 bp</td><td class="metric-desc">50% of total bases are in reads longer than this value</td></tr>
                <tr><td class="metric-name">Max Read Length</td><td class="metric-value">35,538 bp</td><td class="metric-desc">Longest read in the dataset</td></tr>
                <tr><td class="metric-name">Mean Quality</td><td class="metric-value">Q28.2</td><td class="metric-desc">Average Phred quality score (~0.15% error rate)</td></tr>
                <tr><td class="metric-name">Median Quality</td><td class="metric-value">Q37.1</td><td class="metric-desc">Median Phred quality (~0.02% error rate)</td></tr>
                <tr><td class="metric-name">Q20 Reads</td><td class="metric-value">96.1%</td><td class="metric-desc">Percentage of reads with accuracy &ge;99% (error rate &le;1%)</td></tr>
                <tr><td class="metric-name">Q30 Reads</td><td class="metric-value">76.1%</td><td class="metric-desc">Percentage of reads with accuracy &ge;99.9% (error rate &le;0.1%)</td></tr>
                <tr><td class="metric-name">GC Content</td><td class="metric-value">36.73%</td><td class="metric-desc">Fraction of G and C bases; indicates AT-rich genome typical of Hymenoptera</td></tr>
                <tr><td class="metric-name">Read Type</td><td class="metric-value">HiFi (CCS) &mdash; CONFIRMED</td><td class="metric-desc">Circular Consensus Sequencing reads with multiple passes for high accuracy</td></tr>
            </tbody>
        </table>

        <div class="plot-grid">
            <div class="plot-container">
                <img src="{pacbio_imgs['weighted_hist']}" alt="Weighted Histogram of Read Lengths">
                <div class="plot-caption">Weighted Histogram of Read Lengths</div>
            </div>
            <div class="plot-container">
                <img src="{pacbio_imgs['length_vs_qual']}" alt="Length vs Quality (KDE)">
                <div class="plot-caption">Read Length vs Quality Score (KDE)</div>
            </div>
            <div class="plot-container">
                <img src="{pacbio_imgs['non_weighted_hist']}" alt="Non-weighted Histogram of Read Lengths">
                <div class="plot-caption">Non-weighted Histogram of Read Lengths</div>
            </div>
            <div class="plot-container">
                <img src="{pacbio_imgs['yield_by_length']}" alt="Yield by Length">
                <div class="plot-caption">Cumulative Yield by Read Length</div>
            </div>
        </div>
    </div>
</div>

<!-- PHASE 1.2: Illumina QC -->
<div class="card">
    <div class="card-header">
        Phase 1.2: Illumina QC (fastp)
        <span class="badge badge-pass">PASS</span>
    </div>
    <div class="card-body">
        <div class="subsection">
            <h3>Before Filtering</h3>
            <table>
                <thead><tr><th>Metric</th><th>Value</th><th>Description</th></tr></thead>
                <tbody>
                    <tr><td class="metric-name">Total Reads</td><td class="metric-value">184,452,188 &times;2</td><td class="metric-desc">Paired-end read count (R1 + R2)</td></tr>
                    <tr><td class="metric-name">Total Bases</td><td class="metric-value">55.34 Gb</td><td class="metric-desc">Combined yield from both read pairs</td></tr>
                    <tr><td class="metric-name">Q20 (R1 / R2)</td><td class="metric-value">98.48% / 98.46%</td><td class="metric-desc">Percentage of bases with quality &ge;Q20 for each read direction</td></tr>
                    <tr><td class="metric-name">Q30 (R1 / R2)</td><td class="metric-value">94.70% / 94.97%</td><td class="metric-desc">Percentage of bases with quality &ge;Q30 for each read direction</td></tr>
                </tbody>
            </table>
        </div>

        <div class="subsection">
            <h3>After Filtering</h3>
            <table>
                <thead><tr><th>Metric</th><th>Value</th><th>Description</th></tr></thead>
                <tbody>
                    <tr><td class="metric-name">Total Reads</td><td class="metric-value">182,165,699 &times;2</td><td class="metric-desc">Reads remaining after quality and adapter trimming</td></tr>
                    <tr><td class="metric-name">Total Bases</td><td class="metric-value">52.33 Gb</td><td class="metric-desc">Bases remaining after filtering</td></tr>
                    <tr><td class="metric-name">Q20 (R1 / R2)</td><td class="metric-value">99.19% / 99.29%</td><td class="metric-desc">Post-filter Q20 rates; improved by quality trimming</td></tr>
                    <tr><td class="metric-name">Q30 (R1 / R2)</td><td class="metric-value">96.08% / 96.74%</td><td class="metric-desc">Post-filter Q30 rates; improved by quality trimming</td></tr>
                    <tr><td class="metric-name">Reads Passed</td><td class="metric-value">364,331,398 (98.76%)</td><td class="metric-desc">Total reads passing all filters; very high pass rate</td></tr>
                    <tr><td class="metric-name">Duplication Rate</td><td class="metric-value">7.20%</td><td class="metric-desc">PCR/optical duplicate rate; below 10% is acceptable</td></tr>
                    <tr><td class="metric-name">Insert Size Peak</td><td class="metric-value">181 bp</td><td class="metric-desc">Most frequent fragment length; typical for standard Illumina library</td></tr>
                    <tr><td class="metric-name">Adapter Trimmed</td><td class="metric-value">73,732,466 (20%)</td><td class="metric-desc">Reads with adapter sequences detected and trimmed</td></tr>
                </tbody>
            </table>
        </div>
    </div>
</div>

<!-- PHASE 1.3: K-mer Genome Survey -->
<div class="card">
    <div class="card-header">
        Phase 1.3: K-mer Genome Survey (GenomeScope 2.0)
        <span class="badge badge-pass">PASS</span>
    </div>
    <div class="card-body">
        <div class="subsection">
            <h3>GenomeScope 2.0 Results</h3>
            <table>
                <thead><tr><th>Metric</th><th>Value</th><th>Description</th></tr></thead>
                <tbody>
                    <tr><td class="metric-name">Genome Haploid Length</td><td class="metric-value">~655 Mb (654&ndash;656 Mb)</td><td class="metric-desc">Estimated haploid genome size from k-mer frequency distribution</td></tr>
                    <tr><td class="metric-name">Heterozygosity</td><td class="metric-value">0.55%</td><td class="metric-desc">Rate of heterozygous sites; diploid model confirmed</td></tr>
                    <tr><td class="metric-name">Repeat Content</td><td class="metric-value">~35% (228&ndash;229 Mb)</td><td class="metric-desc">Fraction of genome composed of repetitive elements</td></tr>
                    <tr><td class="metric-name">Unique Length</td><td class="metric-value">~426 Mb</td><td class="metric-desc">Non-repetitive portion of the genome</td></tr>
                    <tr><td class="metric-name">Model Fit</td><td class="metric-value">68.1&ndash;95.9%</td><td class="metric-desc">Goodness of fit of the GenomeScope model to k-mer data</td></tr>
                    <tr><td class="metric-name">K-mer Coverage</td><td class="metric-value">30.7x</td><td class="metric-desc">Average k-mer depth from Illumina reads</td></tr>
                    <tr><td class="metric-name">Read Error Rate</td><td class="metric-value">0.148%</td><td class="metric-desc">Estimated per-base sequencing error rate from k-mer analysis</td></tr>
                </tbody>
            </table>
        </div>

        <div class="subsection">
            <h3>Coverage Analysis</h3>
            <table>
                <thead><tr><th>Platform</th><th>Yield</th><th>Est. Genome</th><th>Coverage</th><th>Status</th></tr></thead>
                <tbody>
                    <tr>
                        <td class="metric-name">PacBio HiFi</td>
                        <td class="metric-value">7.88 Gb</td>
                        <td>655 Mb</td>
                        <td class="metric-value">~12x</td>
                        <td><span class="badge badge-warning">WARNING: LOW</span></td>
                    </tr>
                    <tr>
                        <td class="metric-name">Illumina NovaSeq X</td>
                        <td class="metric-value">52.33 Gb</td>
                        <td>655 Mb</td>
                        <td class="metric-value">~80x</td>
                        <td><span class="badge badge-pass">PASS</span></td>
                    </tr>
                </tbody>
            </table>
            <div style="margin-top: 16px;">
                <div style="margin-bottom: 8px; font-size: 0.9em; font-weight: 600;">PacBio HiFi Coverage (12x / 40x target)</div>
                <div class="cov-bar-wrap">
                    <div class="cov-bar" style="width: 30%; background: linear-gradient(90deg, #e67e22, #f39c12);">12x</div>
                </div>
                <div style="margin-top: 12px; margin-bottom: 8px; font-size: 0.9em; font-weight: 600;">Illumina Coverage (80x / 80x target)</div>
                <div class="cov-bar-wrap">
                    <div class="cov-bar" style="width: 100%; background: linear-gradient(90deg, #27ae60, #2ecc71);">80x</div>
                </div>
            </div>
        </div>

        <div class="plot-grid">
            <div class="plot-container">
                <img src="{genomescope_imgs['linear']}" alt="GenomeScope Linear Plot">
                <div class="plot-caption">K-mer Profile (Linear Scale)</div>
            </div>
            <div class="plot-container">
                <img src="{genomescope_imgs['log']}" alt="GenomeScope Log Plot">
                <div class="plot-caption">K-mer Profile (Log Scale)</div>
            </div>
            <div class="plot-container">
                <img src="{genomescope_imgs['transformed_linear']}" alt="Transformed Linear Plot">
                <div class="plot-caption">Transformed K-mer Profile (Linear)</div>
            </div>
            <div class="plot-container">
                <img src="{genomescope_imgs['transformed_log']}" alt="Transformed Log Plot">
                <div class="plot-caption">Transformed K-mer Profile (Log)</div>
            </div>
        </div>
    </div>
</div>

</div><!-- /container -->

<div class="footer">
    S. cameroni Genome Assembly Pipeline Report &bull; Generated April 2026 &bull; Bioinformatics QC
</div>

</body>
</html>
"""

outpath = BASE / "pipeline_report.html"
with open(outpath, "w") as f:
    f.write(html)

print(f"Report written to {outpath} ({os.path.getsize(outpath) / 1024:.0f} KB)")
