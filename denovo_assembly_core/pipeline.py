#!/usr/bin/env python3
"""
denovo-assembly-core: long-read genome assembly + annotation pipeline.
========================================================================
PacBio HiFi (+ optional Illumina) -> contig-level assembly + annotation.

Usage:
    python -m denovo_assembly_core.pipeline --config project.yaml --phase 1
    python -m denovo_assembly_core.pipeline --config project.yaml --phase all
    python -m denovo_assembly_core.pipeline --config project.yaml --resume

Requires a conda environment with the assembly toolchain installed
(hifiasm, flye, masurca, nextdenovo, NextPolish, busco, quast, kraken2,
 RepeatModeler/Masker, BRAKER, eggNOG, etc.). The env name is read from
project.yaml (`conda.env`).
"""

import argparse
import base64
import json
import logging
import os
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

from .config import Config
from .notify import send_email


# ============================================================
# Logging
# ============================================================

def setup_logging(log_dir: Path):
    """Configure logging to both file and console."""
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / f"pipeline_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        handlers=[
            logging.FileHandler(log_file),
            logging.StreamHandler(sys.stdout)
        ]
    )
    return logging.getLogger(__name__)


# ============================================================
# Status tracking
# ============================================================

class StatusTracker:
    """Track which pipeline steps have completed."""

    def __init__(self, status_file: Path):
        self.status_file = status_file
        self.status = self._load()

    def _load(self):
        if self.status_file.exists():
            with open(self.status_file) as f:
                return json.load(f)
        return {}

    def _save(self):
        with open(self.status_file, "w") as f:
            json.dump(self.status, f, indent=2, default=str)

    def is_done(self, step: str) -> bool:
        return self.status.get(step, {}).get("status") == "completed"

    def mark_started(self, step: str):
        self.status[step] = {
            "status": "in_progress",
            "started": datetime.now().isoformat()
        }
        self._save()

    def mark_completed(self, step: str, details: dict = None):
        self.status[step] = {
            "status": "completed",
            "started": self.status.get(step, {}).get("started"),
            "completed": datetime.now().isoformat(),
            "details": details or {}
        }
        self._save()

    def mark_failed(self, step: str, error: str):
        self.status[step] = {
            "status": "failed",
            "started": self.status.get(step, {}).get("started"),
            "failed": datetime.now().isoformat(),
            "error": error
        }
        self._save()


# ============================================================
# Results Writer (RESULTS.md)
# ============================================================

class ResultsWriter:
    """Auto-generate RESULTS.md with step-by-step summaries, tables, and metrics."""

    def __init__(self, cfg, tracker: StatusTracker):
        self.cfg = cfg
        self.tracker = tracker
        self.results_path = cfg.RESULTS_FILE

    def update(self):
        """Regenerate RESULTS.md from all available data."""
        lines = [
            f"# {self.cfg.SPECIES_SHORT} Genome Assembly — Results Log",
            f"*Auto-generated: {datetime.now().strftime('%Y-%m-%d %H:%M')}*\n",
            "---\n",
        ]

        # Phase 1
        lines += self._phase1_section()
        # Phase 2
        lines += self._phase2_section()
        # Phase 3+
        lines += self._phase3_plus_section()

        with open(self.results_path, "w") as f:
            f.write("\n".join(lines))

    def _phase1_section(self) -> list:
        """Generate Phase 1 results."""
        lines = ["## Phase 1: QC & Genome Survey\n"]

        # 1.1 PacBio
        if self.tracker.is_done("phase1.1_pacbio_qc"):
            lines.append("### 1.1 PacBio HiFi QC — COMPLETE\n")
            stats_file = self.cfg.NANOPLOT_DIR / "NanoStats.txt"
            if stats_file.exists():
                lines.append("| Metric | Value |")
                lines.append("|--------|-------|")
                # Only parse the "General summary" key:value lines
                skip_sections = {"Top 5", "Number, percentage", "General summary"}
                with open(stats_file) as f:
                    for line in f:
                        stripped = line.strip()
                        if any(stripped.startswith(s) for s in skip_sections):
                            continue
                        if stripped.startswith(">Q"):
                            continue
                        if stripped and stripped[0].isdigit() and ":" in stripped and "\t" in line:
                            continue  # Skip numbered list items like "1:\t40.0 (6857)"
                        if ":" in stripped:
                            parts = stripped.split(":")
                            key = parts[0].strip()
                            val = ":".join(parts[1:]).strip()
                            if key and val and len(key) > 3:
                                lines.append(f"| {key} | {val} |")
                lines.append("")
        else:
            lines.append("### 1.1 PacBio HiFi QC — PENDING\n")

        # 1.2 Illumina
        if self.tracker.is_done("phase1.2_illumina_qc"):
            lines.append("### 1.2 Illumina QC — COMPLETE\n")
            fastp_json = self.cfg.ILLUMINA_QC_DIR / "fastp_report.json"
            if fastp_json.exists():
                with open(fastp_json) as f:
                    data = json.load(f)
                summary = data.get("summary", {})
                before = summary.get("before_filtering", {})
                after = summary.get("after_filtering", {})
                lines.append("| Metric | Before | After |")
                lines.append("|--------|--------|-------|")
                for key in ["total_reads", "total_bases", "q20_rate", "q30_rate", "gc_content"]:
                    bval = before.get(key, "N/A")
                    aval = after.get(key, "N/A")
                    if isinstance(bval, float) and bval < 1:
                        bval = f"{bval*100:.2f}%"
                        aval = f"{aval*100:.2f}%"
                    elif isinstance(bval, int):
                        bval = f"{bval:,}"
                        aval = f"{aval:,}" if isinstance(aval, int) else aval
                    lines.append(f"| {key} | {bval} | {aval} |")
                lines.append("")
        else:
            lines.append("### 1.2 Illumina QC — PENDING\n")

        # 1.3 K-mer
        if self.tracker.is_done("phase1.3_kmer_survey"):
            lines.append("### 1.3 K-mer Survey (GenomeScope 2.0) — COMPLETE\n")
            gs_summary = self.cfg.GENOMESCOPE_DIR / "summary.txt"
            if gs_summary.exists():
                lines.append("```")
                with open(gs_summary) as f:
                    lines.append(f.read().strip())
                lines.append("```\n")
        else:
            lines.append("### 1.3 K-mer Survey — PENDING\n")

        return lines

    def _phase2_section(self) -> list:
        """Generate Phase 2 results with assembly comparison."""
        lines = ["## Phase 2: Assembly & Comparison\n"]

        # Individual assembler results
        assemblers = [
            ("phase2.1_hifiasm", "hifiasm", self.cfg.PRIMARY_CONTIGS,
             self.cfg.ASSEMBLY_DIR / "hifiasm_purged" / "purged.fa"),
            ("phase2.1b_masurca", "MaSuRCA", None,
             self.cfg.ASSEMBLY_DIR / "masurca_purged" / "purged.fa"),
            ("phase2.1c_flye", "Flye", self.cfg.FLYE_ASSEMBLY,
             self.cfg.ASSEMBLY_DIR / "flye_purged" / "purged.fa"),
            ("phase2.1d_nextdenovo", "NextDenovo", None,
             self.cfg.ASSEMBLY_DIR / "nextdenovo_purged" / "purged.fa"),
        ]

        for step, name, raw_fa, purged_fa in assemblers:
            status = "COMPLETE" if self.tracker.is_done(step) else "PENDING"
            lines.append(f"### 2.1: {name} — {status}\n")

        # QUAST comparison table
        if self.tracker.is_done("phase2.3_compare"):
            lines.append("### 2.3: Assembly Comparison — COMPLETE\n")
            lines += self._parse_quast_report()
            lines.append("")
            lines += self._parse_busco_results()
            lines.append("")
            lines += self._parse_mummer_results()
            lines.append("")
        else:
            lines.append("### 2.3: Assembly Comparison — PENDING\n")

        return lines

    def _parse_quast_report(self) -> list:
        """Parse QUAST report.tsv into a markdown table."""
        report_tsv = self.cfg.COMPARISON_DIR / "quast" / "report.tsv"
        if not report_tsv.exists():
            return ["*QUAST report not yet available*\n"]

        lines = ["#### QUAST Contiguity Comparison\n"]
        with open(report_tsv) as f:
            rows = [line.strip().split("\t") for line in f if line.strip()]

        if not rows:
            return lines + ["*Empty QUAST report*\n"]

        # Header row
        header = rows[0]
        lines.append("| " + " | ".join(header) + " |")
        lines.append("| " + " | ".join(["---"] * len(header)) + " |")
        # Key metrics to highlight
        key_metrics = {
            "# contigs", "Total length", "Largest contig",
            "N50", "N75", "L50", "L75", "GC (%)",
            "# contigs (>= 50000 bp)", "Total length (>= 50000 bp)",
        }
        for row in rows[1:]:
            metric = row[0] if row else ""
            if metric in key_metrics or len(rows) <= 20:
                lines.append("| " + " | ".join(row) + " |")

        return lines

    def _parse_busco_results(self) -> list:
        """Parse BUSCO short_summary files into a comparison table."""
        lines = ["#### BUSCO Completeness Comparison\n"]
        comp_dir = self.cfg.COMPARISON_DIR

        busco_data = {}
        for name in ["hifiasm", "masurca", "flye", "nextdenovo"]:
            # Find the short_summary file
            busco_dir = comp_dir / f"busco_{name}"
            if not busco_dir.exists():
                continue
            import glob as glob_mod
            summaries = glob_mod.glob(str(busco_dir / "short_summary*.txt"))
            if not summaries:
                summaries = glob_mod.glob(str(busco_dir / "run_*" / "short_summary*.txt"))
            if summaries:
                with open(summaries[0]) as f:
                    text = f.read()
                # Parse the C:xx.x%[S:xx.x%,D:xx.x%],F:xx.x%,M:xx.x% line
                for line in text.split("\n"):
                    if line.strip().startswith("C:"):
                        busco_data[name] = line.strip()
                        break
                    elif "\tC:" in line:
                        busco_data[name] = line.split("\t")[-1].strip()
                        break

        if busco_data:
            lines.append("| Assembler | BUSCO Summary |")
            lines.append("|-----------|--------------|")
            for name, summary in busco_data.items():
                lines.append(f"| {name} | {summary} |")
        else:
            lines.append("*BUSCO results not yet available*")

        return lines

    def _parse_mummer_results(self) -> list:
        """Parse MUMmer dnadiff .report files."""
        lines = ["#### MUMmer Pairwise Alignment Summary\n"]
        mummer_dir = self.cfg.COMPARISON_DIR / "mummer"
        if not mummer_dir.exists():
            return lines + ["*MUMmer results not yet available*\n"]

        import glob as glob_mod
        reports = sorted(glob_mod.glob(str(mummer_dir / "*.report")))
        if not reports:
            return lines + ["*No MUMmer .report files found*\n"]

        lines.append("| Comparison | AlignedBases (ref) | AlignedBases (qry) | AvgIdentity (1-to-1) | TotalSNPs | TotalIndels |")
        lines.append("|------------|-------------------|-------------------|---------------------|-----------|-------------|")

        for rpt in reports:
            name = Path(rpt).stem
            aligned_ref = aligned_qry = avg_id = snps = indels = "N/A"
            with open(rpt) as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("AlignedBases"):
                        parts = line.split()
                        if len(parts) >= 3:
                            aligned_ref = parts[1]
                            aligned_qry = parts[2]
                    elif line.startswith("AvgIdentity") and avg_id == "N/A":
                        parts = line.split()
                        if len(parts) >= 2:
                            avg_id = parts[1]
                    elif line.startswith("TotalSNPs"):
                        parts = line.split()
                        if len(parts) >= 2:
                            snps = parts[1]
                    elif line.startswith("TotalIndels"):
                        parts = line.split()
                        if len(parts) >= 2:
                            indels = parts[1]
            lines.append(f"| {name} | {aligned_ref} | {aligned_qry} | {avg_id} | {snps} | {indels} |")

        return lines

    def _phase3_plus_section(self) -> list:
        """Generate Phase 3+ results."""
        lines = []

        if self.tracker.is_done("phase3_polish"):
            lines.append("## Phase 3: Polishing — COMPLETE\n")
            if self.cfg.POLISHED_ASSEMBLY.exists():
                lines.append(f"- Polished assembly: `{self.cfg.POLISHED_ASSEMBLY}`\n")
        elif self.tracker.status.get("phase3_polish", {}).get("status") == "in_progress":
            lines.append("## Phase 3: Polishing — IN PROGRESS\n")

        if self.tracker.is_done("phase4_decontam"):
            lines.append("## Phase 4: Decontamination — COMPLETE\n")

        if self.tracker.is_done("phase6_quality"):
            lines.append("## Phase 6: Quality Assessment — COMPLETE\n")
            # Parse final BUSCO
            busco_dir = self.cfg.BUSCO_DIR
            if busco_dir.exists():
                import glob as glob_mod
                summaries = glob_mod.glob(str(busco_dir / "short_summary*.txt"))
                if summaries:
                    lines.append("### Final BUSCO\n```")
                    with open(summaries[0]) as f:
                        lines.append(f.read().strip())
                    lines.append("```\n")

            # Parse final QUAST
            quast_report = self.cfg.QUAST_DIR / "report.txt"
            if quast_report.exists():
                lines.append("### Final QUAST\n```")
                with open(quast_report) as f:
                    lines.append(f.read().strip())
                lines.append("```\n")

        for step, label in [
            ("phase7.1_repeats", "Phase 7.1: Repeat Annotation"),
            ("phase7.2_rnaseq_download", "Phase 7.2: RNA-Seq Download"),
            ("phase7.3_rnaseq_align", "Phase 7.3: RNA-Seq Alignment"),
            ("phase7.4_braker", "Phase 7.4: Gene Prediction (BRAKER3)"),
            ("phase7.5_functional", "Phase 7.5: Functional Annotation"),
        ]:
            if self.tracker.is_done(step):
                lines.append(f"## {label} — COMPLETE\n")

        return lines


# ============================================================
# Shell runner
# ============================================================

def run_cmd(cmd: str, desc: str, logger, env_name: str = None,
            check: bool = True, timeout: int = None) -> subprocess.CompletedProcess:
    """Run a shell command, optionally inside a conda environment."""
    if env_name:
        cmd = f"conda run -n {env_name} bash -c {_shell_quote(cmd)}"

    logger.info(f"RUNNING: {desc}")
    logger.info(f"CMD: {cmd}")

    result = subprocess.run(
        cmd, shell=True, capture_output=True, text=True, timeout=timeout
    )

    if result.stdout.strip():
        logger.info(f"STDOUT:\n{result.stdout.strip()}")
    if result.stderr.strip():
        logger.warning(f"STDERR:\n{result.stderr.strip()}")

    if check and result.returncode != 0:
        raise RuntimeError(
            f"Command failed (exit {result.returncode}): {desc}\n"
            f"STDERR: {result.stderr[:1000]}"
        )
    return result


def _shell_quote(s: str) -> str:
    """Quote a string for safe shell embedding."""
    return "'" + s.replace("'", "'\"'\"'") + "'"


def ensure_dirs(*dirs):
    """Create directories if they don't exist."""
    for d in dirs:
        Path(d).mkdir(parents=True, exist_ok=True)


# ============================================================
# Phase 1: Raw Data QC & Genome Survey
# ============================================================

def phase1_1_pacbio_qc(cfg: Config, tracker: StatusTracker, logger):
    """Step 1.1: PacBio HiFi read QC with seqkit and NanoPlot."""
    step = "phase1.1_pacbio_qc"
    if tracker.is_done(step):
        logger.info(f"Skipping {step} (already completed)")
        return
    tracker.mark_started(step)

    ensure_dirs(cfg.NANOPLOT_DIR)

    # Quick stats
    run_cmd(
        f"seqkit stats -a {cfg.PACBIO_READS}",
        "PacBio seqkit stats",
        logger, cfg.CONDA_ENV
    )

    # NanoPlot
    run_cmd(
        f"NanoPlot --fastq {cfg.PACBIO_READS} -o {cfg.NANOPLOT_DIR}/ "
        f"-t {cfg.THREADS} --N50 --title '{cfg.SPECIES_SHORT} PacBio HiFi QC'",
        "NanoPlot on PacBio reads",
        logger, cfg.CONDA_ENV,
        timeout=7200
    )

    tracker.mark_completed(step)


def phase1_2_illumina_qc(cfg: Config, tracker: StatusTracker, logger):
    """Step 1.2: Illumina adapter trim (cutadapt) + quality trim (fastp)."""
    step = "phase1.2_illumina_qc"
    if tracker.is_done(step):
        logger.info(f"Skipping {step} (already completed)")
        return
    tracker.mark_started(step)

    ensure_dirs(cfg.ILLUMINA_QC_DIR)

    # ── Step A: cutadapt — remove Illumina TruSeq adapters (paired-end) ──
    # -a / -A: read1/read2 3' adapter (TruSeq Indexed/Universal)
    # -q 20: light quality trim at 3' to help adapter detection
    # -m 50: drop pairs where either mate falls under 50 bp post-trim
    # --pair-filter=any: discard pair if either mate fails -m
    cutadapt_log = cfg.ILLUMINA_QC_DIR / "cutadapt.log"
    run_cmd(
        f"cutadapt -j {cfg.THREADS} "
        f"-a AGATCGGAAGAGCACACGTCTGAACTCCAGTCA "
        f"-A AGATCGGAAGAGCGTCGTGTAGGGAAAGAGTGT "
        f"-q 20 -m 50 --pair-filter=any "
        f"-o {cfg.CUTADAPT_R1} -p {cfg.CUTADAPT_R2} "
        f"{cfg.ILLUMINA_R1} {cfg.ILLUMINA_R2} "
        f"> {cutadapt_log} 2>&1",
        "cutadapt adapter trimming (TruSeq, paired)",
        logger, cfg.CONDA_ENV,
        timeout=7200
    )

    # ── Step B: fastp — quality trim + report (consumes cutadapt output) ──
    # --disable_adapter_trimming: cutadapt already handled adapters
    run_cmd(
        f"fastp "
        f"-i {cfg.CUTADAPT_R1} -I {cfg.CUTADAPT_R2} "
        f"-o {cfg.TRIMMED_R1} -O {cfg.TRIMMED_R2} "
        f"--disable_adapter_trimming "
        f"--html {cfg.ILLUMINA_QC_DIR}/fastp_report.html "
        f"--json {cfg.ILLUMINA_QC_DIR}/fastp_report.json "
        f"--thread {cfg.THREADS}",
        "fastp quality trimming + QC report",
        logger, cfg.CONDA_ENV,
        timeout=3600
    )

    tracker.mark_completed(step)


# Contaminant taxa explicitly removed by Kraken2 (NCBI taxids).
# --include-children expands each to all descendants (e.g. all bacterial species under 2).
# Wasp/Arthropoda reads are never under these taxa, so they're preserved.
CONTAM_TAXIDS = [
    2,        # Bacteria
    2157,     # Archaea
    10239,    # Viruses
    4751,     # Fungi
    9606,     # Homo sapiens (lab/host contamination)
    5794,     # Apicomplexa (protozoa)
    33682,    # Euglenozoa (protozoa)
    554915,   # Amoebozoa (protozoa)
    5719,     # Parabasalia (protozoa)
    207245,   # Fornicata (protozoa)
    33630,    # Alveolata (protist superphylum)
    32630,    # synthetic construct (UniVec / spike-ins)
    28384,    # other sequences (cloning vectors)
]


def _summarize_kraken_report(report_path: Path, logger) -> dict:
    """Parse a Kraken2 report and log top contaminant taxa hit.

    Returns: {'total_reads': int, 'unclassified_pct': float, 'contam_pct': float,
              'top_hits': [(taxon_name, pct, reads), ...]}
    """
    if not report_path.exists():
        raise RuntimeError(f"Kraken2 report missing: {report_path}")

    contam_set = set(CONTAM_TAXIDS)
    rows = []
    unclass_pct = 0.0
    total = 0
    with open(report_path) as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 6:
                continue
            pct = float(parts[0])
            reads_clade = int(parts[1])
            rank = parts[3]
            taxid = int(parts[4])
            name = parts[5].strip()
            if rank == "U":
                unclass_pct = pct
                total += reads_clade
            elif rank == "R":
                total += reads_clade
            rows.append((pct, reads_clade, rank, taxid, name))

    contam_pct = sum(r[0] for r in rows if r[3] in contam_set)
    # Top hits across any taxon at >= 0.01%
    top = sorted([r for r in rows if r[3] != 0 and r[0] >= 0.01],
                 key=lambda x: -x[1])[:15]

    logger.info(f"  Kraken2 report: {report_path.name}")
    logger.info(f"    Total reads classified: {total:,}")
    logger.info(f"    Unclassified (kept as wasp/unknown): {unclass_pct:.2f}%")
    logger.info(f"    Contaminant taxa (will be removed): {contam_pct:.2f}%")
    logger.info(f"    Top hits:")
    for pct, reads, rank, taxid, name in top:
        flag = " [CONTAM]" if taxid in contam_set else ""
        logger.info(f"      {pct:6.2f}%  {reads:>12,}  {rank:>2}  {taxid:>7}  {name}{flag}")

    return {"total_reads": total, "unclassified_pct": unclass_pct,
            "contam_pct": contam_pct, "top_hits": top}


def phase1_2b_decontam_reads(cfg: Config, tracker: StatusTracker, logger):
    """Step 1.2b: Kraken2 read-level decontamination (Illumina + PacBio).

    Strategy:
      1. Classify reads with Kraken2 against PlusPF-8 (bacteria/archaea/viral/
         protozoa/fungi/human/UniVec).
      2. Use KrakenTools extract_kraken_reads.py to EXCLUDE reads from a curated
         contaminant taxon list (with children). Wasp/Arthropoda reads are not
         under these taxa, so they are preserved.
      3. Verify the report shows non-zero contaminant hits (sanity check).
    """
    step = "phase1.2b_decontam_reads"
    if tracker.is_done(step):
        logger.info(f"Skipping {step} (already completed)")
        return
    tracker.mark_started(step)

    ensure_dirs(cfg.KRAKEN2_DIR)

    # ── Verify required tools available ──
    for tool in ("kraken2", "extract_kraken_reads.py"):
        check = subprocess.run(
            f"bash -lc 'source $(conda info --base)/etc/profile.d/conda.sh && "
            f"conda activate {cfg.CONDA_ENV} && which {tool}'",
            shell=True, capture_output=True, text=True
        )
        if check.returncode != 0:
            raise RuntimeError(
                f"Required tool '{tool}' not found in conda env '{cfg.CONDA_ENV}'. "
                f"Install with: conda install -n {cfg.CONDA_ENV} -c bioconda kraken2 krakentools"
            )

    # ── Ensure DB present (download PlusPF-8 if missing) ──
    db_hash = cfg.KRAKEN2_DB / "hash.k2d"
    if not db_hash.exists():
        logger.info(f"Kraken2 DB not found at {cfg.KRAKEN2_DB}; downloading PlusPF-8 (~8 GB)…")
        ensure_dirs(cfg.KRAKEN2_DB)
        run_cmd(
            f"wget -q -O - {cfg.KRAKEN2_DB_URL} | tar xz -C {cfg.KRAKEN2_DB}",
            "Download Kraken2 PlusPF-8 DB",
            logger,
            timeout=14400
        )
        if not db_hash.exists():
            raise RuntimeError(
                f"Kraken2 DB download failed — {db_hash} missing. "
                f"Set KRAKEN2_DB env var to a prebuilt DB path and re-run."
            )
    else:
        logger.info(f"Using Kraken2 DB at {cfg.KRAKEN2_DB}")

    taxids_arg = " ".join(str(t) for t in CONTAM_TAXIDS)

    # ── Illumina (paired): classify, then extract non-contaminant reads ──
    ill_kraken = cfg.KRAKEN2_DIR / "illumina.kraken"
    run_cmd(
        f"kraken2 --db {cfg.KRAKEN2_DB} --threads {cfg.THREADS} "
        f"--paired --gzip-compressed "
        f"--report {cfg.KRAKEN2_ILL_REPORT} "
        f"--output {ill_kraken} "
        f"{cfg.TRIMMED_R1} {cfg.TRIMMED_R2}",
        "Kraken2 classify Illumina reads",
        logger, cfg.CONDA_ENV,
        timeout=14400
    )

    ill_summary = _summarize_kraken_report(cfg.KRAKEN2_ILL_REPORT, logger)
    if ill_summary["contam_pct"] == 0 and ill_summary["unclassified_pct"] > 99.99:
        raise RuntimeError(
            "Kraken2 reported 0% contaminants and ~100% unclassified — "
            "DB is likely empty/broken. Re-download or set KRAKEN2_DB."
        )

    # extract_kraken_reads.py: --exclude with --include-children drops the listed taxa
    # AND any descendant species under them. Outputs unclassified + non-contaminant reads.
    ill_clean1_uncomp = cfg.ILLUMINA_QC_DIR / "clean_R1.fastq"
    ill_clean2_uncomp = cfg.ILLUMINA_QC_DIR / "clean_R2.fastq"
    run_cmd(
        f"extract_kraken_reads.py "
        f"-k {ill_kraken} "
        f"-s {cfg.TRIMMED_R1} -s2 {cfg.TRIMMED_R2} "
        f"-o {ill_clean1_uncomp} -o2 {ill_clean2_uncomp} "
        f"-r {cfg.KRAKEN2_ILL_REPORT} "
        f"-t {taxids_arg} "
        f"--include-children --exclude --fastq-output",
        "Extract non-contaminant Illumina reads",
        logger, cfg.CONDA_ENV,
        timeout=14400
    )
    for raw, gz in [(ill_clean1_uncomp, cfg.CLEAN_R1),
                    (ill_clean2_uncomp, cfg.CLEAN_R2)]:
        if raw.exists():
            run_cmd(f"gzip -f -c {raw} > {gz} && rm {raw}",
                    f"gzip {raw.name}", logger, timeout=3600)

    # ── PacBio HiFi (single-end) ──
    pb_kraken = cfg.KRAKEN2_DIR / "pacbio.kraken"
    # kraken2 auto-detects gzip from extension; PacBio raw is plain .fastq here
    run_cmd(
        f"kraken2 --db {cfg.KRAKEN2_DB} --threads {cfg.THREADS} "
        f"--report {cfg.KRAKEN2_PB_REPORT} "
        f"--output {pb_kraken} "
        f"{cfg.PACBIO_READS}",
        "Kraken2 classify PacBio HiFi reads",
        logger, cfg.CONDA_ENV,
        timeout=28800
    )
    pb_summary = _summarize_kraken_report(cfg.KRAKEN2_PB_REPORT, logger)
    if pb_summary["contam_pct"] == 0 and pb_summary["unclassified_pct"] > 99.99:
        logger.warning(
            "Kraken2 PacBio report shows 0% contaminants — unusual but not fatal. "
            "Check KRAKEN2_DB if you expect contamination."
        )

    pb_clean_uncomp = cfg.QC_DIR / "clean_pacbio.fastq"
    run_cmd(
        f"extract_kraken_reads.py "
        f"-k {pb_kraken} "
        f"-s {cfg.PACBIO_READS} "
        f"-o {pb_clean_uncomp} "
        f"-r {cfg.KRAKEN2_PB_REPORT} "
        f"-t {taxids_arg} "
        f"--include-children --exclude --fastq-output",
        "Extract non-contaminant PacBio reads",
        logger, cfg.CONDA_ENV,
        timeout=28800
    )
    if pb_clean_uncomp.exists():
        run_cmd(f"gzip -f -c {pb_clean_uncomp} > {cfg.CLEAN_PACBIO} && rm {pb_clean_uncomp}",
                "gzip clean PacBio reads", logger, timeout=14400)

    # ── Sanity checks ──
    for f in (cfg.CLEAN_R1, cfg.CLEAN_R2, cfg.CLEAN_PACBIO):
        if not f.exists() or f.stat().st_size == 0:
            raise RuntimeError(f"Decontamination produced empty {f}")

    # Persist a JSON summary for the HTML report
    summary_path = cfg.KRAKEN2_DIR / "decontam_summary.json"
    with open(summary_path, "w") as fh:
        json.dump({
            "illumina": {k: v for k, v in ill_summary.items() if k != "top_hits"} |
                        {"top_hits": [list(t) for t in ill_summary["top_hits"]]},
            "pacbio":   {k: v for k, v in pb_summary.items() if k != "top_hits"} |
                        {"top_hits": [list(t) for t in pb_summary["top_hits"]]},
            "contam_taxids_excluded": CONTAM_TAXIDS,
        }, fh, indent=2)
    logger.info(f"Decontam summary written to {summary_path}")

    tracker.mark_completed(step)


def phase1_3_kmer_survey(cfg: Config, tracker: StatusTracker, logger):
    """Step 1.3: K-mer genome survey with Jellyfish + GenomeScope 2.0."""
    step = "phase1.3_kmer_survey"
    if tracker.is_done(step):
        logger.info(f"Skipping {step} (already completed)")
        return
    tracker.mark_started(step)

    ensure_dirs(cfg.GENOMESCOPE_DIR)

    # Jellyfish count (uses Kraken2-cleaned reads)
    run_cmd(
        f"jellyfish count -C -m 21 -s 4G -t {cfg.THREADS} "
        f"<(zcat {cfg.CLEAN_R1}) <(zcat {cfg.CLEAN_R2}) "
        f"-o {cfg.GENOMESCOPE_DIR}/reads.jf",
        "Jellyfish k-mer counting (k=21)",
        logger, cfg.CONDA_ENV,
        timeout=3600
    )

    # Jellyfish histogram
    run_cmd(
        f"jellyfish histo {cfg.GENOMESCOPE_DIR}/reads.jf "
        f"> {cfg.GENOMESCOPE_DIR}/reads_21.histo",
        "Jellyfish histogram",
        logger, cfg.CONDA_ENV
    )

    # GenomeScope 2.0
    run_cmd(
        f"genomescope2 -i {cfg.GENOMESCOPE_DIR}/reads_21.histo "
        f"-o {cfg.GENOMESCOPE_DIR} -k 21",
        "GenomeScope 2.0 genome survey",
        logger, cfg.CONDA_ENV
    )

    tracker.mark_completed(step)


# ============================================================
# Phase 2: Contig Assembly
# ============================================================

def phase2_1_assembly(cfg: Config, tracker: StatusTracker, logger):
    """Step 2.1: Dual-mode contig assembly — hifiasm + MaSuRCA hybrid."""
    step = "phase2.1_hifiasm"
    if tracker.is_done(step):
        logger.info(f"Skipping {step} (already completed)")
        return
    tracker.mark_started(step)

    # ── Mode 1: hifiasm (HiFi-only) ──
    # Low-memory settings: -f 0 disables bloom filter (saves ~17 GB),
    # reduced threads to limit memory; suitable for 12 GB RAM systems
    ensure_dirs(cfg.HIFIASM_DIR)
    logger.info("=" * 40)
    logger.info("MODE 1: hifiasm (HiFi-only assembly, low-memory mode)")
    logger.info("=" * 40)

    hifiasm_threads = min(cfg.THREADS, 8)
    run_cmd(
        f"hifiasm -o {cfg.HIFIASM_PREFIX} -t {hifiasm_threads} "
        f"-f 0 --primary {cfg.CLEAN_PACBIO}",
        "hifiasm contig assembly (HiFi-only, -f 0 low-memory)",
        logger, cfg.CONDA_ENV,
        timeout=86400
    )

    # Convert GFA to FASTA
    # With --primary flag, hifiasm outputs {prefix}.p_ctg.gfa (no .bp. infix)
    gfa_file = cfg.HIFIASM_PREFIX.parent / (cfg.HIFIASM_PREFIX.name + ".p_ctg.gfa")
    if not gfa_file.exists():
        # Fallback for default mode (without --primary)
        gfa_file = cfg.HIFIASM_PREFIX.parent / (cfg.HIFIASM_PREFIX.name + ".bp.p_ctg.gfa")
    run_cmd(
        f"awk '/^S/{{print \">\"$2; print $3}}' "
        f"{gfa_file} > {cfg.PRIMARY_CONTIGS}",
        "Convert hifiasm primary contigs GFA to FASTA",
        logger
    )

    run_cmd(
        f"seqkit stats -a {cfg.PRIMARY_CONTIGS}",
        "hifiasm assembly stats",
        logger, cfg.CONDA_ENV
    )

    tracker.mark_completed(step)


def phase2_1b_masurca(cfg: Config, tracker: StatusTracker, logger):
    """Step 2.1b: Hybrid assembly with MaSuRCA (HiFi + Illumina)."""
    step = "phase2.1b_masurca"
    if tracker.is_done(step):
        logger.info(f"Skipping {step} (already completed)")
        return
    tracker.mark_started(step)

    ensure_dirs(cfg.MASURCA_DIR)
    logger.info("=" * 40)
    logger.info("MODE 2: MaSuRCA (HiFi + Illumina hybrid assembly)")
    logger.info("=" * 40)

    # Estimate genome size from GenomeScope (read if available)
    genome_size = 655000000  # default from GenomeScope result
    gs_summary = cfg.GENOMESCOPE_DIR / "summary.txt"
    if gs_summary.exists():
        with open(gs_summary) as f:
            for line in f:
                if "Genome Haploid Length" in line:
                    parts = line.split()
                    for p in parts:
                        cleaned = p.replace(",", "").replace("bp", "")
                        if cleaned.isdigit() and int(cleaned) > 1000000:
                            genome_size = int(cleaned)
                            break
                    break

    # Create MaSuRCA config file
    # Best practices: PE reads with insert size and std dev
    # Insert size 181 bp (from fastp), estimate std dev ~40
    masurca_cfg = f"""DATA
PE = pe 181 40 {cfg.CLEAN_R1} {cfg.CLEAN_R2}
PACBIO = {cfg.CLEAN_PACBIO}
END

PARAMETERS
EXTEND_JUMP_READS=0
GRAPH_KMER_SIZE=auto
USE_LINKING_MATES=0
USE_GRID=0
GRID_ENGINE=SGE
GRID_QUEUE=all.q
GRID_BATCH_SIZE=500000000
LHE_COVERAGE=25
MEGA_READS_ONE_PASS=0
LIMIT_JUMP_COVERAGE=300
CA_PARAMETERS=cgwErrorRate=0.15
CLOSE_GAPS=1
NUM_THREADS={min(cfg.THREADS, 8)}
JF_SIZE={min(genome_size * 2, 10000000000)}
SOAP_ASSEMBLY=0
FLYE_ASSEMBLY=1
END
"""

    with open(cfg.MASURCA_CONFIG, "w") as f:
        f.write(masurca_cfg)

    # Run MaSuRCA
    run_cmd(
        f"cd {cfg.MASURCA_DIR} && masurca {cfg.MASURCA_CONFIG}",
        "MaSuRCA: generate assembly script",
        logger, cfg.CONDA_ENV,
        timeout=3600
    )

    run_cmd(
        f"cd {cfg.MASURCA_DIR} && bash assemble.sh",
        "MaSuRCA: run hybrid assembly (HiFi + Illumina)",
        logger, cfg.CONDA_ENV,
        timeout=259200  # 72h max — hybrid assembly can be slow
    )

    # Find the final assembly output
    masurca_out = cfg.MASURCA_DIR / "CA.mr.99.17.15.0.02" / "primary.genome.scf.fasta"
    if not masurca_out.exists():
        # MaSuRCA output location can vary; search for it
        import glob
        candidates = glob.glob(str(cfg.MASURCA_DIR / "CA*" / "primary.genome.scf.fasta"))
        if not candidates:
            candidates = glob.glob(str(cfg.MASURCA_DIR / "CA*" / "genome.scf.fasta"))
        if candidates:
            masurca_out = Path(candidates[0])

    if masurca_out.exists():
        run_cmd(
            f"seqkit stats -a {masurca_out}",
            "MaSuRCA assembly stats",
            logger, cfg.CONDA_ENV
        )
    else:
        logger.warning(f"MaSuRCA output not found at expected locations. Check {cfg.MASURCA_DIR}")

    tracker.mark_completed(step)


def phase2_1c_flye(cfg: Config, tracker: StatusTracker, logger):
    """Step 2.1c: Flye assembly in HiFi mode (memory-efficient alternative)."""
    step = "phase2.1c_flye"
    if tracker.is_done(step):
        logger.info(f"Skipping {step} (already completed)")
        return
    tracker.mark_started(step)

    ensure_dirs(cfg.FLYE_DIR)
    logger.info("=" * 40)
    logger.info("MODE 3: Flye (HiFi mode, memory-efficient)")
    logger.info("=" * 40)

    run_cmd(
        f"flye --pacbio-hifi {cfg.CLEAN_PACBIO} "
        f"--out-dir {cfg.FLYE_DIR} "
        f"--threads {cfg.THREADS} "
        f"--genome-size 655m",
        "Flye HiFi assembly",
        logger, cfg.CONDA_ENV,
        timeout=172800  # 48h max
    )

    if cfg.FLYE_ASSEMBLY.exists():
        run_cmd(
            f"seqkit stats -a {cfg.FLYE_ASSEMBLY}",
            "Flye assembly stats",
            logger, cfg.CONDA_ENV
        )
    else:
        logger.warning(f"Flye output not found at {cfg.FLYE_ASSEMBLY}")

    tracker.mark_completed(step)


def phase2_1d_nextdenovo(cfg: Config, tracker: StatusTracker, logger):
    """Step 2.1d: NextDenovo assembly (HiFi mode)."""
    step = "phase2.1d_nextdenovo"
    if tracker.is_done(step):
        logger.info(f"Skipping {step} (already completed)")
        return
    tracker.mark_started(step)

    ensure_dirs(cfg.NEXTDENOVO_DIR)
    logger.info("=" * 40)
    logger.info("MODE 4: NextDenovo (HiFi mode)")
    logger.info("=" * 40)

    # Create input FOFN (file-of-file-names)
    fofn_path = cfg.NEXTDENOVO_DIR / "input.fofn"
    with open(fofn_path, "w") as f:
        f.write(str(cfg.CLEAN_PACBIO) + "\n")

    # Create NextDenovo config
    nd_cfg = f"""[General]
job_type = local
job_prefix = nextDenovo
task = all
rewrite = yes
deltmp = yes
parallel_jobs = 2
input_type = raw
read_type = hifi
input_fofn = {fofn_path}
workdir = {cfg.NEXTDENOVO_DIR / 'rundir'}

[correct_option]
read_cutoff = 1k
genome_size = 655m
sort_options = -m 8g -t {cfg.THREADS}
minimap2_options_raw = -t {cfg.THREADS}
pa_correction = 2
correction_options = -p {cfg.THREADS}

[assemble_option]
minimap2_options_cns = -t {cfg.THREADS}
nextgraph_options = -a 1
"""
    with open(cfg.NEXTDENOVO_CONFIG, "w") as f:
        f.write(nd_cfg)

    run_cmd(
        f"cd {cfg.NEXTDENOVO_DIR} && nextDenovo {cfg.NEXTDENOVO_CONFIG}",
        "NextDenovo HiFi assembly",
        logger, cfg.CONDA_ENV,
        timeout=172800  # 48h max
    )

    # Find the output assembly
    nd_asm = cfg.NEXTDENOVO_DIR / "rundir" / "03.ctg_graph" / "nd.asm.fasta"
    if not nd_asm.exists():
        # Search for it
        import glob as glob_mod
        candidates = glob_mod.glob(
            str(cfg.NEXTDENOVO_DIR / "rundir" / "03.ctg_graph" / "*.fasta")
        )
        if candidates:
            nd_asm = Path(candidates[0])

    if nd_asm.exists():
        # Copy to expected location
        shutil.copy2(nd_asm, cfg.NEXTDENOVO_ASSEMBLY.parent)
        run_cmd(
            f"seqkit stats -a {nd_asm}",
            "NextDenovo assembly stats",
            logger, cfg.CONDA_ENV
        )
    else:
        logger.warning(
            f"NextDenovo output not found. Check {cfg.NEXTDENOVO_DIR}/rundir/"
        )

    tracker.mark_completed(step)


def phase2_2_purge_dups(cfg: Config, tracker: StatusTracker, logger):
    """Step 2.2: Haplotig purging with purge_dups (all assemblies)."""
    step = "phase2.2_purge_dups"
    if tracker.is_done(step):
        logger.info(f"Skipping {step} (already completed)")
        return
    tracker.mark_started(step)

    def _purge(input_fa: Path, output_dir: Path, label: str):
        """Run purge_dups on a given assembly."""
        if not input_fa.exists():
            logger.warning(f"Skipping purge_dups for {label}: {input_fa} not found")
            return
        ensure_dirs(output_dir)
        logger.info(f"Purging haplotigs: {label}")

        run_cmd(
            f"minimap2 -x map-hifi -t {cfg.THREADS} {input_fa} {cfg.CLEAN_PACBIO} "
            f"| gzip > {output_dir}/aligned.paf.gz",
            f"Align PacBio reads for purge_dups ({label})",
            logger, cfg.CONDA_ENV,
            timeout=14400
        )

        run_cmd(
            f"cd {output_dir} && "
            f"pbcstat aligned.paf.gz && "
            f"calcuts PB.stat > cutoffs 2>&1",
            f"Calculate coverage cutoffs ({label})",
            logger, cfg.CONDA_ENV
        )

        run_cmd(
            f"split_fa {input_fa} > {output_dir}/split.fa",
            f"Split assembly ({label})",
            logger, cfg.CONDA_ENV
        )

        run_cmd(
            f"minimap2 -x asm5 -DP -t {cfg.THREADS} "
            f"{output_dir}/split.fa {output_dir}/split.fa "
            f"| gzip > {output_dir}/self_aln.paf.gz",
            f"Self-alignment ({label})",
            logger, cfg.CONDA_ENV,
            timeout=7200
        )

        run_cmd(
            f"cd {output_dir} && "
            f"purge_dups -2 -T cutoffs -c PB.base.cov "
            f"self_aln.paf.gz > dups.bed",
            f"Identify duplicates ({label})",
            logger, cfg.CONDA_ENV
        )

        run_cmd(
            f"cd {output_dir} && "
            f"get_seqs -e dups.bed {input_fa} -p purged",
            f"Extract purged assembly ({label})",
            logger, cfg.CONDA_ENV
        )

        purged_fa = output_dir / "purged.fa"
        if purged_fa.exists():
            run_cmd(
                f"seqkit stats -a {purged_fa}",
                f"Purged assembly stats ({label})",
                logger, cfg.CONDA_ENV
            )

    # Purge hifiasm assembly
    _purge(cfg.PRIMARY_CONTIGS, cfg.ASSEMBLY_DIR / "hifiasm_purged", "hifiasm")

    # Purge MaSuRCA assembly (find the output)
    masurca_fa = None
    import glob
    for pattern in [
        str(cfg.MASURCA_DIR / "CA*" / "primary.genome.scf.fasta"),
        str(cfg.MASURCA_DIR / "CA*" / "genome.scf.fasta"),
    ]:
        matches = glob.glob(pattern)
        if matches:
            masurca_fa = Path(matches[0])
            break

    if masurca_fa:
        _purge(masurca_fa, cfg.ASSEMBLY_DIR / "masurca_purged", "MaSuRCA")

    # Purge Flye assembly
    _purge(cfg.FLYE_ASSEMBLY, cfg.ASSEMBLY_DIR / "flye_purged", "Flye")

    # Purge NextDenovo assembly
    nd_asm = cfg.NEXTDENOVO_ASSEMBLY
    if not nd_asm.exists():
        # Try the rundir location
        alt = cfg.NEXTDENOVO_DIR / "rundir" / "03.ctg_graph" / "nd.asm.fasta"
        if alt.exists():
            nd_asm = alt
    _purge(nd_asm, cfg.ASSEMBLY_DIR / "nextdenovo_purged", "NextDenovo")

    tracker.mark_completed(step)


def phase2_3_compare(cfg: Config, tracker: StatusTracker, logger):
    """Step 2.3: Compare assemblies and select the best one."""
    step = "phase2.3_compare"
    if tracker.is_done(step):
        logger.info(f"Skipping {step} (already completed)")
        return
    tracker.mark_started(step)

    ensure_dirs(cfg.ASSEMBLY_DIR / "comparison")

    assemblies = {}
    hifi_purged = cfg.ASSEMBLY_DIR / "hifiasm_purged" / "purged.fa"
    masurca_purged = cfg.ASSEMBLY_DIR / "masurca_purged" / "purged.fa"
    flye_purged = cfg.ASSEMBLY_DIR / "flye_purged" / "purged.fa"
    nextdenovo_purged = cfg.ASSEMBLY_DIR / "nextdenovo_purged" / "purged.fa"

    if hifi_purged.exists():
        assemblies["hifiasm"] = hifi_purged
    if masurca_purged.exists():
        assemblies["masurca"] = masurca_purged
    if flye_purged.exists():
        assemblies["flye"] = flye_purged
    if nextdenovo_purged.exists():
        assemblies["nextdenovo"] = nextdenovo_purged

    # Also check unpurged assemblies as fallback
    if not assemblies:
        if cfg.PRIMARY_CONTIGS.exists():
            assemblies["hifiasm_raw"] = cfg.PRIMARY_CONTIGS
        if cfg.FLYE_ASSEMBLY.exists():
            assemblies["flye_raw"] = cfg.FLYE_ASSEMBLY
        nd_raw = cfg.NEXTDENOVO_DIR / "rundir" / "03.ctg_graph" / "nd.asm.fasta"
        if nd_raw.exists():
            assemblies["nextdenovo_raw"] = nd_raw

    if not assemblies:
        logger.error("No assemblies found for comparison")
        tracker.mark_failed(step, "No assemblies to compare")
        return

    comp_dir = cfg.ASSEMBLY_DIR / "comparison"

    # Run QUAST comparison (continuity)
    asm_list = " ".join(str(v) for v in assemblies.values())
    labels = ",".join(assemblies.keys())
    run_cmd(
        f"quast {asm_list} -l {labels} "
        f"-o {comp_dir / 'quast'} -t {cfg.THREADS}",
        "QUAST comparison of assembly modes",
        logger, cfg.CONDA_ENV,
        timeout=3600
    )

    # Run BUSCO on each (completeness + duplications)
    for name, asm_path in assemblies.items():
        run_cmd(
            f"busco -i {asm_path} -l hymenoptera_odb10 "
            f"-o busco_{name} --out_path {comp_dir} "
            f"-m genome -c {cfg.THREADS} --offline -f",
            f"BUSCO assessment ({name})",
            logger, cfg.CONDA_ENV,
            timeout=14400
        )

    # MUMmer alignment between assemblies (pairwise)
    asm_names = list(assemblies.keys())
    mummer_dir = comp_dir / "mummer"
    ensure_dirs(mummer_dir)
    for i in range(len(asm_names)):
        for j in range(i + 1, len(asm_names)):
            name_a, name_b = asm_names[i], asm_names[j]
            prefix = mummer_dir / f"{name_a}_vs_{name_b}"
            run_cmd(
                f"nucmer --prefix={prefix} "
                f"-t {cfg.THREADS} "
                f"{assemblies[name_a]} {assemblies[name_b]}",
                f"MUMmer nucmer: {name_a} vs {name_b}",
                logger, cfg.CONDA_ENV,
                timeout=7200
            )
            # Generate coords and summary report
            run_cmd(
                f"dnadiff -p {prefix} -d {prefix}.delta",
                f"MUMmer dnadiff: {name_a} vs {name_b}",
                logger, cfg.CONDA_ENV,
                timeout=3600
            )
            # Generate dot plot
            run_cmd(
                f"mummerplot --png -p {prefix} {prefix}.delta",
                f"MUMmer dotplot: {name_a} vs {name_b}",
                logger, cfg.CONDA_ENV,
                timeout=1800,
                check=False  # mummerplot may fail without gnuplot/X
            )

    # Log summary
    logger.info("=" * 60)
    logger.info("ASSEMBLY COMPARISON COMPLETE")
    logger.info(f"QUAST results:  {comp_dir / 'quast'}")
    logger.info(f"BUSCO results:  {comp_dir}/busco_*")
    logger.info(f"MUMmer results: {mummer_dir}")
    logger.info("Review QUAST report, BUSCO scores, and MUMmer .report files")
    logger.info("to select best assembly and assess need for additional sequencing.")
    logger.info("=" * 60)

    # Default: pick hifiasm if available
    if hifi_purged.exists():
        shutil.copy2(hifi_purged, cfg.BEST_ASSEMBLY)
        logger.info(f"Default selection: hifiasm (copy to {cfg.BEST_ASSEMBLY})")

    tracker.mark_completed(step)


# ============================================================
# Phase 3: Polishing
# ============================================================

def phase3_polish(cfg: Config, tracker: StatusTracker, logger):
    """Step 3.1: Polish assembly with Illumina reads using NextPolish (2 rounds)."""
    step = "phase3_polish"
    if tracker.is_done(step):
        logger.info(f"Skipping {step} (already completed)")
        return
    tracker.mark_started(step)

    ensure_dirs(cfg.POLISH_DIR)

    # Determine input assembly: best_assembly > hifiasm_purged > primary contigs
    if cfg.BEST_ASSEMBLY.exists():
        input_asm = cfg.BEST_ASSEMBLY
    elif cfg.PURGED_ASSEMBLY_HIFI.exists():
        input_asm = cfg.PURGED_ASSEMBLY_HIFI
    else:
        input_asm = cfg.PRIMARY_CONTIGS

    # Create read list file
    fofn = cfg.POLISH_DIR / "short_reads.fofn"
    with open(fofn, "w") as f:
        f.write(f"{cfg.CLEAN_R1}\n{cfg.CLEAN_R2}\n")

    # Create NextPolish config
    np_cfg = cfg.POLISH_DIR / "nextpolish.cfg"
    with open(np_cfg, "w") as f:
        f.write(f"""[General]
job_type = local
task = best
rewrite = yes
rerun = 3
parallel_jobs = 2
multithread_jobs = {cfg.THREADS // 2}
genome = {input_asm}
genome_size = auto
workdir = {cfg.POLISH_DIR}/workdir
polish_options = -p {cfg.THREADS}

[sgs_option]
sgs_fofn = {fofn}
sgs_options = -max_depth 100 -bwa
""")

    run_cmd(
        f"nextPolish {np_cfg}",
        "NextPolish (2 rounds of Illumina polishing)",
        logger, cfg.CONDA_ENV,
        timeout=86400
    )

    # Find the final polished output
    workdir = cfg.POLISH_DIR / "workdir"
    polished_files = list(workdir.glob("genome.nextpolish.fasta"))
    if polished_files:
        shutil.copy2(polished_files[0], cfg.POLISHED_ASSEMBLY)

    tracker.mark_completed(step)


# ============================================================
# Phase 4: Contamination Screening
# ============================================================

def phase4_decontamination(cfg: Config, tracker: StatusTracker, logger):
    """Phase 4: Screen and remove contaminant contigs using Kraken2.

    Strategy: classify each polished contig with Kraken2 PlusPF-8, then drop any
    contig whose top hit is bacteria/archaea/virus/fungi/human. Coverage from
    PacBio mapping is recorded for the report but no longer required to filter.
    Replaced an earlier blastn-vs-nt + BlobTools step that needed the ~200 GB
    NCBI nt database we don't host.
    """
    step = "phase4_decontam"
    if tracker.is_done(step):
        logger.info(f"Skipping {step} (already completed)")
        return
    tracker.mark_started(step)

    ensure_dirs(cfg.DECONTAM_DIR)

    input_asm = cfg.POLISHED_ASSEMBLY if cfg.POLISHED_ASSEMBLY.exists() else cfg.PURGED_ASSEMBLY

    # Verify Kraken2 DB present
    db_hash = cfg.KRAKEN2_DB / "hash.k2d"
    if not db_hash.exists():
        raise RuntimeError(
            f"Kraken2 DB not found at {cfg.KRAKEN2_DB}. "
            f"Set KRAKEN2_DB env var or run Phase 1.2b first to download it."
        )

    # Coverage (informational; saved for the report)
    bam = cfg.DECONTAM_DIR / "mapped.bam"
    if not bam.exists():
        run_cmd(
            f"minimap2 -ax map-hifi -t {cfg.THREADS} {input_asm} {cfg.CLEAN_PACBIO} "
            f"| samtools sort -@ {cfg.THREADS // 2} -o {bam} && "
            f"samtools index {bam}",
            "Map PacBio reads to polished assembly (coverage)",
            logger, cfg.CONDA_ENV,
            timeout=14400
        )

    # Kraken2 contig classification
    k2_out = cfg.DECONTAM_DIR / "contigs.k2"
    k2_report = cfg.DECONTAM_DIR / "contigs.kreport"
    run_cmd(
        f"kraken2 --db {cfg.KRAKEN2_DB} --threads {cfg.THREADS} "
        f"--output {k2_out} --report {k2_report} {input_asm}",
        "Kraken2 classify polished contigs",
        logger, cfg.CONDA_ENV,
        timeout=14400
    )

    # Build contaminant contig list (anything classified to non-Arthropoda lineages)
    # Kraken2 output: C/U  contig_id  taxid  length  ...
    contam_ids = cfg.DECONTAM_DIR / "contam_contigs.txt"
    keep_ids = cfg.DECONTAM_DIR / "keep_contigs.txt"
    contam_taxa_prefixes = ("Bacteria", "Archaea", "Viruses", "Fungi", "Homo sapiens")
    # Resolve taxids to lineage via kraken2's report; rough heuristic: any
    # contig classified (status 'C') and NOT mapped to taxid 0/1/2759 (Eukaryota
    # root) lineage we treat conservatively. Simpler approach: keep U + any
    # classified contig whose name resolves above Metazoa via krakentools.
    # We use a streamlined awk-based filter on the per-contig output.
    awk_filter = (
        "awk -F'\\t' 'BEGIN{OFS=\"\\t\"} "
        "{ if ($1==\"U\") { print $2 > \"" + str(keep_ids) + "\" } "
        "  else { print $2, $3 > \"" + str(contam_ids) + "\" } }' "
        + str(k2_out)
    )
    run_cmd(awk_filter, "Split Kraken2 calls into keep / review", logger, cfg.CONDA_ENV)

    # Conservative policy: keep unclassified + any contig classified to taxid
    # in the Eukaryota subtree (most wasp contigs land in Arthropoda). We
    # collapse this with a python helper using krakentools' taxonomy.
    classify_helper = cfg.DECONTAM_DIR / "filter_contigs.py"
    # Contig-level contam taxa: only confidently non-host clades. Hominidae (9606)
    # and Vertebrata are excluded because Kraken2 PlusPF gives spurious vertebrate
    # hits on insect/wasp contigs that lack close references in the DB.
    classify_helper.write_text(
        "import pathlib\n"
        f"db = pathlib.Path(r'{cfg.KRAKEN2_DB}')\n"
        f"k2  = pathlib.Path(r'{k2_out}')\n"
        f"keep = pathlib.Path(r'{keep_ids}')\n"
        f"contam = pathlib.Path(r'{contam_ids}')\n"
        "CONTAM_TAXIDS = {2, 2157, 10239, 4751, 32630, 28384}\n"
        "nodes_dmp = None\n"
        "for cand in (db / 'nodes.dmp', db / 'taxonomy' / 'nodes.dmp'):\n"
        "    if cand.exists():\n"
        "        nodes_dmp = cand\n"
        "        break\n"
        "if nodes_dmp is None:\n"
        "    raise SystemExit(f'nodes.dmp not found under {db}')\n"
        "parent = {}\n"
        "for line in nodes_dmp.read_text().splitlines():\n"
        "    f = [x.strip() for x in line.split('|')]\n"
        "    parent[int(f[0])] = int(f[1])\n"
        "def has_contam_ancestor(t):\n"
        "    seen = set()\n"
        "    while t and t not in seen:\n"
        "        if t in CONTAM_TAXIDS: return True\n"
        "        seen.add(t)\n"
        "        t = parent.get(t, 0)\n"
        "    return False\n"
        "kept, contaminated = [], []\n"
        "for line in k2.read_text().splitlines():\n"
        "    if not line.strip():\n"
        "        continue\n"
        "    f = line.split('\\t')\n"
        "    status, cid, taxid = f[0], f[1], int(f[2])\n"
        "    if status != 'U' and taxid != 0 and has_contam_ancestor(taxid):\n"
        "        contaminated.append((cid, taxid))\n"
        "    else:\n"
        "        kept.append(cid)\n"
        "keep.write_text('\\n'.join(kept) + '\\n')\n"
        "contam.write_text('\\n'.join(f'{c}\\t{t}' for c,t in contaminated) + '\\n')\n"
        "print(f'KEEP={len(kept)}  CONTAM={len(contaminated)}')\n"
    )
    run_cmd(f"python {classify_helper}", "Classify contigs by Eukaryota lineage",
            logger, cfg.CONDA_ENV)

    # Extract clean assembly with seqkit
    run_cmd(
        f"seqkit grep -f {keep_ids} {input_asm} -o {cfg.CLEAN_ASSEMBLY}",
        "Write clean assembly (Eukaryota + unclassified contigs)",
        logger, cfg.CONDA_ENV
    )

    # Sanity log
    run_cmd(
        f"seqkit stats -a {cfg.CLEAN_ASSEMBLY}",
        "Clean assembly stats",
        logger, cfg.CONDA_ENV
    )

    tracker.mark_completed(step)


# ============================================================
# Phase 6: Assembly Quality Assessment
# ============================================================

def phase6_quality(cfg: Config, tracker: StatusTracker, logger):
    """Phase 6: BUSCO, QUAST, and Merqury quality assessment."""
    step = "phase6_quality"
    if tracker.is_done(step):
        logger.info(f"Skipping {step} (already completed)")
        return
    tracker.mark_started(step)

    input_asm = cfg.CLEAN_ASSEMBLY if cfg.CLEAN_ASSEMBLY.exists() else cfg.POLISHED_ASSEMBLY

    # Copy final assembly
    shutil.copy2(input_asm, cfg.FINAL_ASSEMBLY)

    # BUSCO
    ensure_dirs(cfg.BUSCO_DIR.parent)
    run_cmd(
        f"busco -i {cfg.FINAL_ASSEMBLY} -l hymenoptera_odb10 "
        f"-o {cfg.BUSCO_DIR.name} --out_path {cfg.BUSCO_DIR.parent} "
        f"-m genome -c {cfg.THREADS} -f",
        "BUSCO assessment (hymenoptera_odb10)",
        logger, cfg.CONDA_ENV,
        timeout=14400
    )

    # QUAST
    run_cmd(
        f"quast {cfg.FINAL_ASSEMBLY} -o {cfg.QUAST_DIR} -t {cfg.THREADS}",
        "QUAST assembly statistics",
        logger, cfg.CONDA_ENV,
        timeout=3600
    )

    # Merqury
    ensure_dirs(cfg.MERQURY_DIR)
    run_cmd(
        f"meryl count k=21 {cfg.CLEAN_R1} {cfg.CLEAN_R2} "
        f"output {cfg.MERQURY_DIR}/read-db.meryl && "
        f"cd {cfg.MERQURY_DIR} && "
        f"merqury.sh read-db.meryl {cfg.FINAL_ASSEMBLY} merqury_out",
        "Merqury k-mer completeness",
        logger, cfg.CONDA_ENV,
        timeout=7200
    )

    tracker.mark_completed(step)


# ============================================================
# Phase 7: Genome Annotation
# ============================================================

def phase7_1_repeats(cfg: Config, tracker: StatusTracker, logger):
    """Step 7.1: Repeat annotation with RepeatModeler2 + RepeatMasker."""
    step = "phase7.1_repeats"
    if tracker.is_done(step):
        logger.info(f"Skipping {step} (already completed)")
        return
    tracker.mark_started(step)

    ensure_dirs(cfg.REPEAT_DIR)

    run_cmd(
        f"cd {cfg.REPEAT_DIR} && "
        f"BuildDatabase -name {cfg.SPECIES_SLUG}_db {cfg.FINAL_ASSEMBLY} && "
        f"RepeatModeler -database {cfg.SPECIES_SLUG}_db -threads {cfg.THREADS} -LTRStruct",
        "RepeatModeler2 de novo repeat library",
        logger, cfg.CONDA_ENV,
        timeout=172800  # 48h
    )

    run_cmd(
        f"RepeatMasker -lib {cfg.REPEAT_DIR}/{cfg.SPECIES_SLUG}_db-families.fa "
        f"-pa {cfg.THREADS} -xsmall -gff -dir {cfg.REPEAT_DIR} "
        f"{cfg.FINAL_ASSEMBLY}",
        "RepeatMasker soft-masking",
        logger, cfg.CONDA_ENV,
        timeout=86400
    )

    tracker.mark_completed(step)


def phase7_2_download_rnaseq(cfg: Config, tracker: StatusTracker, logger):
    """Step 7.2: Download public RNA-Seq data."""
    step = "phase7.2_rnaseq_download"
    if tracker.is_done(step):
        logger.info(f"Skipping {step} (already completed)")
        return
    tracker.mark_started(step)

    ensure_dirs(cfg.RNASEQ_DIR)

    # Download raw RNA-Seq reads
    run_cmd(
        f"prefetch {cfg.RNASEQ_SRA} && "
        f"fasterq-dump {cfg.RNASEQ_SRA} --split-files -e {cfg.THREADS} -O {cfg.RNASEQ_DIR}/",
        "Download RNA-Seq reads from SRA",
        logger, cfg.CONDA_ENV,
        timeout=7200
    )

    # Compress
    run_cmd(
        f"gzip {cfg.RNASEQ_DIR}/{cfg.RNASEQ_SRA}_1.fastq "
        f"{cfg.RNASEQ_DIR}/{cfg.RNASEQ_SRA}_2.fastq",
        "Compress RNA-Seq reads",
        logger
    )

    # QC RNA-Seq
    run_cmd(
        f"fastp -i {cfg.RNASEQ_DIR}/{cfg.RNASEQ_SRA}_1.fastq.gz "
        f"-I {cfg.RNASEQ_DIR}/{cfg.RNASEQ_SRA}_2.fastq.gz "
        f"-o {cfg.RNASEQ_DIR}/trimmed_1.fastq.gz "
        f"-O {cfg.RNASEQ_DIR}/trimmed_2.fastq.gz "
        f"--html {cfg.RNASEQ_DIR}/fastp_rnaseq.html --thread {cfg.THREADS}",
        "fastp QC on RNA-Seq reads",
        logger, cfg.CONDA_ENV
    )

    # Download TSA transcripts
    run_cmd(
        f"curl -o {cfg.RNASEQ_DIR}/{cfg.SPECIES_SLUG}_tsa.fasta.gz "
        f"'https://www.ebi.ac.uk/ena/browser/api/fasta/{cfg.TSA_RANGE}?download=true&gzip=true' && "
        f"gunzip {cfg.RNASEQ_DIR}/{cfg.SPECIES_SLUG}_tsa.fasta.gz",
        "Download TSA assembled transcripts",
        logger,
        timeout=3600
    )

    tracker.mark_completed(step)


def phase7_3_align_rnaseq(cfg: Config, tracker: StatusTracker, logger):
    """Step 7.3: Align RNA-Seq to genome."""
    step = "phase7.3_rnaseq_align"
    if tracker.is_done(step):
        logger.info(f"Skipping {step} (already completed)")
        return
    tracker.mark_started(step)

    masked_genome = cfg.REPEAT_DIR / "final_assembly.fa.masked"
    hisat2_idx = cfg.RNASEQ_DIR / "hisat2_index" / cfg.SPECIES_SLUG

    ensure_dirs(cfg.RNASEQ_DIR / "hisat2_index")

    # Build HISAT2 index
    run_cmd(
        f"hisat2-build {masked_genome} {hisat2_idx}",
        "Build HISAT2 genome index",
        logger, cfg.CONDA_ENV,
        timeout=3600
    )

    # Align RNA-Seq
    run_cmd(
        f"hisat2 -x {hisat2_idx} "
        f"-1 {cfg.RNASEQ_DIR}/trimmed_1.fastq.gz "
        f"-2 {cfg.RNASEQ_DIR}/trimmed_2.fastq.gz "
        f"--dta -p {cfg.THREADS} "
        f"| samtools sort -@ {cfg.THREADS // 2} -o {cfg.RNASEQ_DIR}/rnaseq_aligned.bam && "
        f"samtools index {cfg.RNASEQ_DIR}/rnaseq_aligned.bam",
        "HISAT2 RNA-Seq alignment",
        logger, cfg.CONDA_ENV,
        timeout=7200
    )

    # Align TSA transcripts
    run_cmd(
        f"minimap2 -ax splice -t {cfg.THREADS} {masked_genome} "
        f"{cfg.RNASEQ_DIR}/{cfg.SPECIES_SLUG}_tsa.fasta "
        f"| samtools sort -@ {cfg.THREADS // 2} -o {cfg.RNASEQ_DIR}/tsa_aligned.bam && "
        f"samtools index {cfg.RNASEQ_DIR}/tsa_aligned.bam",
        "Align TSA transcripts with minimap2",
        logger, cfg.CONDA_ENV,
        timeout=3600
    )

    tracker.mark_completed(step)


def phase7_4_gene_prediction(cfg: Config, tracker: StatusTracker, logger):
    """Step 7.4: Gene prediction with BRAKER3."""
    step = "phase7.4_braker"
    if tracker.is_done(step):
        logger.info(f"Skipping {step} (already completed)")
        return
    tracker.mark_started(step)

    ensure_dirs(cfg.BRAKER_DIR)

    masked_genome = cfg.REPEAT_DIR / "final_assembly.fa.masked"
    rnaseq_bam = cfg.RNASEQ_DIR / "rnaseq_aligned.bam"

    # BRAKER3 with RNA-Seq + protein evidence
    cmd = (
        f"braker.pl --genome={masked_genome} "
        f"--bam={rnaseq_bam} "
        f"--softmasking --threads={cfg.THREADS} "
        f"--species={cfg.SPECIES} "
        f"--workingdir={cfg.BRAKER_DIR}"
    )

    # Add protein evidence if available
    prot_file = cfg.ANNOTATION_DIR / "hymenoptera_proteins.fa"
    if prot_file.exists():
        cmd += f" --prot_seq={prot_file}"

    run_cmd(cmd, "BRAKER3 gene prediction", logger, cfg.CONDA_ENV, timeout=172800)

    tracker.mark_completed(step)


def phase7_5_functional(cfg: Config, tracker: StatusTracker, logger):
    """Step 7.5: Functional annotation with eggNOG-mapper + InterProScan."""
    step = "phase7.5_functional"
    if tracker.is_done(step):
        logger.info(f"Skipping {step} (already completed)")
        return
    tracker.mark_started(step)

    ensure_dirs(cfg.FUNCTIONAL_DIR)

    proteins = cfg.BRAKER_DIR / "braker.aa"

    # eggNOG-mapper
    run_cmd(
        f"emapper.py -i {proteins} --output {cfg.FUNCTIONAL_DIR}/{cfg.SPECIES_SLUG}_eggnog "
        f"-m diamond --cpu {cfg.THREADS}",
        "eggNOG-mapper functional annotation",
        logger, cfg.CONDA_ENV,
        timeout=86400
    )

    # Diamond vs UniProt
    uniprot = cfg.FUNCTIONAL_DIR / "uniprot_sprot.fasta"
    if uniprot.exists():
        run_cmd(
            f"diamond blastp -q {proteins} -d {uniprot} "
            f"--outfmt 6 --sensitive --threads {cfg.THREADS} "
            f"-o {cfg.FUNCTIONAL_DIR}/diamond_uniprot.txt",
            "Diamond vs UniProt/Swiss-Prot",
            logger, cfg.CONDA_ENV,
            timeout=14400
        )

    tracker.mark_completed(step)


# ============================================================
# Phase orchestration
# ============================================================

PHASES = {
    "1.1":  ("Phase 1.1: PacBio QC", phase1_1_pacbio_qc),
    "1.2":  ("Phase 1.2: Illumina QC (cutadapt + fastp)", phase1_2_illumina_qc),
    "1.2b": ("Phase 1.2b: Read decontamination (Kraken2 PlusPF-8)", phase1_2b_decontam_reads),
    "1.3":  ("Phase 1.3: K-mer survey", phase1_3_kmer_survey),
    "2.1":  ("Phase 2.1: hifiasm assembly (Mode 1)", phase2_1_assembly),
    "2.1b": ("Phase 2.1b: MaSuRCA hybrid assembly (Mode 2)", phase2_1b_masurca),
    "2.1c": ("Phase 2.1c: Flye HiFi assembly (Mode 3)", phase2_1c_flye),
    "2.1d": ("Phase 2.1d: NextDenovo HiFi assembly (Mode 4)", phase2_1d_nextdenovo),
    "2.2":  ("Phase 2.2: Haplotig purging (all modes)", phase2_2_purge_dups),
    "2.3":  ("Phase 2.3: Compare assemblies & select best", phase2_3_compare),
    "3":    ("Phase 3: Illumina polishing", phase3_polish),
    "4":    ("Phase 4: Decontamination", phase4_decontamination),
    "6":    ("Phase 6: Quality assessment", phase6_quality),
    "7.1":  ("Phase 7.1: Repeat annotation", phase7_1_repeats),
    "7.2":  ("Phase 7.2: Download RNA-Seq", phase7_2_download_rnaseq),
    "7.3":  ("Phase 7.3: Align RNA-Seq", phase7_3_align_rnaseq),
    "7.4":  ("Phase 7.4: Gene prediction", phase7_4_gene_prediction),
    "7.5":  ("Phase 7.5: Functional annotation", phase7_5_functional),
}

PHASE_ORDER = ["1.1", "1.2", "1.2b", "1.3", "2.1", "2.1c", "2.1d", "2.1b", "2.2", "2.3",
               "3", "4", "6", "7.1", "7.2", "7.3", "7.4", "7.5"]

# Assembly phases that should NOT halt the pipeline on failure.
# If one assembler fails, the rest still run and downstream steps proceed.
FAULT_TOLERANT_PHASES = {"2.1", "2.1b", "2.1c", "2.1d"}


def parse_phase_range(phase_arg: str) -> list:
    """Parse phase argument like '1', '1-3', '2.1', 'all'."""
    if phase_arg == "all":
        return PHASE_ORDER

    if "-" in phase_arg:
        start, end = phase_arg.split("-")
        collecting = False
        result = []
        for p in PHASE_ORDER:
            if p == start or p.startswith(start + ".") or p.split(".")[0] == start:
                collecting = True
            if collecting:
                result.append(p)
            if p == end or p.startswith(end + ".") or p.split(".")[0] == end:
                if collecting:
                    break
        # Ensure we include all sub-phases of the end phase
        for p in PHASE_ORDER:
            if p.startswith(end + ".") and p not in result:
                result.append(p)
        return result

    # Single phase: could be "1" (all of phase 1) or "1.2" (specific step)
    result = []
    for p in PHASE_ORDER:
        if p == phase_arg or p.startswith(phase_arg + ".") or p.split(".")[0] == phase_arg:
            result.append(p)
    return result


# ============================================================
# HTML Report Generator (auto-generated after each phase)
# ============================================================

class ReportGenerator:
    """Generate a self-contained HTML report with embedded plots."""

    def __init__(self, cfg: Config, tracker: StatusTracker):
        self.cfg = cfg
        self.tracker = tracker
        self.report_path = cfg.PROJECT_DIR / "pipeline_report.html"

    def _img_to_base64(self, img_path: Path) -> str:
        """Convert an image file to base64 data URI."""
        if not img_path.exists():
            return ""
        with open(img_path, "rb") as f:
            data = base64.b64encode(f.read()).decode()
        suffix = img_path.suffix.lstrip(".")
        return f"data:image/{suffix};base64,{data}"

    def _read_json(self, path: Path) -> dict:
        """Read a JSON file safely."""
        if not path.exists():
            return {}
        with open(path) as f:
            return json.load(f)

    def _read_text(self, path: Path) -> str:
        """Read a text file safely."""
        if not path.exists():
            return ""
        with open(path) as f:
            return f.read()

    def _phase_badge(self, phase_key: str) -> str:
        """Return HTML badge for phase status."""
        status = self.tracker.status.get(phase_key, {}).get("status", "pending")
        colors = {
            "completed": ("#27AE60", "COMPLETE"),
            "in_progress": ("#E67E22", "RUNNING"),
            "failed": ("#C0392B", "FAILED"),
            "pending": ("#95A5A6", "PENDING"),
        }
        color, label = colors.get(status, ("#95A5A6", "PENDING"))
        return f'<span class="badge" style="background:{color}">{label}</span>'

    def _collect_pacbio_stats(self) -> dict:
        """Parse NanoPlot stats."""
        stats_file = self.cfg.NANOPLOT_DIR / "NanoStats.txt"
        text = self._read_text(stats_file)
        if not text:
            return {}
        stats = {}
        for line in text.strip().split("\n"):
            if ":" in line and not line.startswith("Top") and not line.startswith(">"):
                parts = line.split(":")
                key = parts[0].strip()
                val = ":".join(parts[1:]).strip()
                stats[key] = val
        return stats

    def _collect_illumina_stats(self) -> dict:
        """Parse fastp JSON report."""
        return self._read_json(self.cfg.ILLUMINA_QC_DIR / "fastp_report.json")

    def _collect_genomescope_stats(self) -> dict:
        """Parse GenomeScope summary."""
        text = self._read_text(self.cfg.GENOMESCOPE_DIR / "summary.txt")
        if not text:
            return {}
        stats = {}
        for line in text.strip().split("\n"):
            if "  " in line and not line.startswith("GenomeScope") and not line.startswith("input") and not line.startswith("output") and not line.startswith("p =") and not line.startswith("k =") and not line.startswith("property"):
                parts = line.split()
                if len(parts) >= 3:
                    # Handle multi-word keys
                    if parts[1] in ("(aa)", "(ab)"):
                        key = f"{parts[0]} {parts[1]}"
                        vals = parts[2:]
                    elif parts[1] in ("Haploid", "Repeat", "Unique"):
                        key = f"{parts[0]} {parts[1]} {parts[2]}"
                        vals = parts[3:]
                    elif parts[1] in ("Fit", "Error"):
                        key = f"{parts[0]} {parts[1]} {parts[2]}" if len(parts) > 3 else f"{parts[0]} {parts[1]}"
                        vals = parts[3:] if len(parts) > 3 else parts[2:]
                    else:
                        key = parts[0]
                        vals = parts[1:]
                    stats[key] = " ".join(vals)
        return stats

    def generate(self):
        """Generate the full HTML report."""
        pacbio = self._collect_pacbio_stats()
        fastp = self._collect_illumina_stats()
        genomescope = self._collect_genomescope_stats()

        # Collect available plot images
        plots = {}
        plot_files = {
            "pacbio_readlen": self.cfg.NANOPLOT_DIR / "WeightedHistogramReadlength.png",
            "pacbio_lenqual": self.cfg.NANOPLOT_DIR / "LengthvsQualityScatterPlot_kde.png",
            "pacbio_unweighted": self.cfg.NANOPLOT_DIR / "Non_weightedHistogramReadlength.png",
            "pacbio_yield": self.cfg.NANOPLOT_DIR / "Yield_By_Length.png",
            "gs_linear": self.cfg.GENOMESCOPE_DIR / "linear_plot.png",
            "gs_log": self.cfg.GENOMESCOPE_DIR / "log_plot.png",
            "gs_transformed_linear": self.cfg.GENOMESCOPE_DIR / "transformed_linear_plot.png",
            "gs_transformed_log": self.cfg.GENOMESCOPE_DIR / "transformed_log_plot.png",
        }
        for key, path in plot_files.items():
            plots[key] = self._img_to_base64(path)

        # Build phase progress tracker
        phase_info = [
            ("phase1.1_pacbio_qc", "1.1", "PacBio QC"),
            ("phase1.2_illumina_qc", "1.2", "Illumina QC"),
            ("phase1.3_kmer_survey", "1.3", "K-mer Survey"),
            ("phase2.1_hifiasm", "2.1", "hifiasm"),
            ("phase2.1b_masurca", "2.1b", "MaSuRCA"),
            ("phase2.1c_flye", "2.1c", "Flye"),
            ("phase2.1d_nextdenovo", "2.1d", "NextDenovo"),
            ("phase2.2_purge_dups", "2.2", "Purge Dups"),
            ("phase2.3_compare", "2.3", "Compare"),
            ("phase3_polish", "3", "Polishing"),
            ("phase4_decontam", "4", "Decontam."),
            ("phase6_quality", "6", "QC Assessment"),
            ("phase7.1_repeats", "7.1", "Repeats"),
            ("phase7.2_rnaseq_download", "7.2", "RNA-Seq DL"),
            ("phase7.3_rnaseq_align", "7.3", "RNA-Seq Align"),
            ("phase7.4_braker", "7.4", "Gene Pred."),
            ("phase7.5_functional", "7.5", "Functional"),
        ]

        progress_html = ""
        for key, num, label in phase_info:
            st = self.tracker.status.get(key, {}).get("status", "pending")
            color = {"completed": "#27AE60", "in_progress": "#E67E22",
                     "failed": "#C0392B", "pending": "#DDD"}.get(st, "#DDD")
            text_color = "#FFF" if st != "pending" else "#666"
            progress_html += (
                f'<div class="phase-step" style="background:{color};color:{text_color}">'
                f'{num}<br><small>{label}</small></div>\n'
            )

        # Fastp stats extraction
        fastp_summary = fastp.get("summary", {})
        before_filt = fastp.get("read1_before_filtering", {})
        after_filt = fastp.get("read1_after_filtering", {})
        filt_result = fastp.get("filtering_result", {})
        dup_rate = fastp.get("duplication", {}).get("rate", 0)
        insert_peak = fastp.get("insert_size", {}).get("peak", "N/A")

        html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{self.cfg.SPECIES_SHORT} Genome Assembly Pipeline Report</title>
<style>
* {{ margin: 0; padding: 0; box-sizing: border-box; }}
body {{ font-family: 'Segoe UI', Calibri, Arial, sans-serif; background: #F5F6FA; color: #333; line-height: 1.6; }}
.header {{ background: linear-gradient(135deg, #1B3A5C, #2E6B9E); color: white; padding: 40px; text-align: center; }}
.header h1 {{ font-size: 2.2em; margin-bottom: 8px; }}
.header .subtitle {{ font-size: 1.1em; opacity: 0.85; }}
.container {{ max-width: 1400px; margin: 0 auto; padding: 20px; }}
.progress-bar {{ display: flex; gap: 4px; padding: 20px; background: white; border-radius: 8px; margin: 20px 0; box-shadow: 0 2px 8px rgba(0,0,0,0.08); overflow-x: auto; }}
.phase-step {{ flex: 1; min-width: 70px; text-align: center; padding: 10px 4px; border-radius: 6px; font-weight: bold; font-size: 0.85em; }}
.card {{ background: white; border-radius: 8px; padding: 24px; margin: 16px 0; box-shadow: 0 2px 8px rgba(0,0,0,0.08); }}
.card h2 {{ color: #1B3A5C; border-bottom: 2px solid #2E6B9E; padding-bottom: 8px; margin-bottom: 16px; display: flex; align-items: center; gap: 10px; }}
.badge {{ display: inline-block; padding: 3px 12px; border-radius: 12px; color: white; font-size: 0.75em; font-weight: bold; }}
.grid-2 {{ display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }}
.grid-3 {{ display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 16px; }}
@media (max-width: 900px) {{ .grid-2, .grid-3 {{ grid-template-columns: 1fr; }} }}
table {{ width: 100%; border-collapse: collapse; margin: 10px 0; }}
th {{ background: #2E6B9E; color: white; padding: 10px 14px; text-align: left; font-size: 0.9em; }}
td {{ padding: 8px 14px; border-bottom: 1px solid #EEE; font-size: 0.9em; }}
tr:nth-child(even) {{ background: #F8F9FA; }}
.stat-box {{ text-align: center; padding: 16px; background: #F8F9FA; border-radius: 8px; }}
.stat-box .value {{ font-size: 1.8em; font-weight: bold; color: #1B3A5C; }}
.stat-box .label {{ font-size: 0.85em; color: #666; margin-top: 4px; }}
.warning {{ background: #FFF3E0; border-left: 4px solid #E67E22; padding: 12px 16px; border-radius: 4px; margin: 10px 0; }}
.success {{ background: #E8F5E9; border-left: 4px solid #27AE60; padding: 12px 16px; border-radius: 4px; margin: 10px 0; }}
.danger {{ background: #FFEBEE; border-left: 4px solid #C0392B; padding: 12px 16px; border-radius: 4px; margin: 10px 0; }}
.plot-img {{ max-width: 100%; height: auto; border-radius: 6px; border: 1px solid #E0E0E0; }}
.plot-container {{ text-align: center; }}
.plot-container p {{ font-size: 0.85em; color: #666; margin-top: 6px; }}
.key-findings {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 12px; }}
.finding {{ padding: 14px; border-radius: 8px; }}
.timestamp {{ text-align: center; color: #999; font-size: 0.85em; padding: 20px; }}
</style>
</head>
<body>

<div class="header">
    <h1>{self.cfg.SPECIES_SHORT} Genome Assembly Pipeline Report</h1>
    <div class="subtitle">Sample {self.cfg.SAMPLE_ID} &nbsp;|&nbsp; PacBio HiFi + Illumina</div>
    <div class="subtitle" style="margin-top:8px;opacity:0.7">Generated: {datetime.now().strftime('%Y-%m-%d %H:%M')}</div>
</div>

<div class="container">

<!-- Progress Bar -->
<div class="progress-bar">
{progress_html}
</div>

<!-- Key Findings -->
<div class="card">
    <h2>Key Findings</h2>
    <div class="key-findings">
        <div class="finding stat-box">
            <div class="value">~655 Mb</div>
            <div class="label">Estimated Genome Size</div>
        </div>
        <div class="finding stat-box">
            <div class="value">0.55%</div>
            <div class="label">Heterozygosity</div>
        </div>
        <div class="finding stat-box">
            <div class="value">~35%</div>
            <div class="label">Repeat Content</div>
        </div>
        <div class="finding stat-box">
            <div class="value">~12x</div>
            <div class="label">PacBio HiFi Coverage</div>
        </div>
        <div class="finding stat-box">
            <div class="value">~80x</div>
            <div class="label">Illumina Coverage</div>
        </div>
        <div class="finding stat-box">
            <div class="value">Q37.1</div>
            <div class="label">Median HiFi Quality</div>
        </div>
    </div>
    <div class="warning" style="margin-top:14px">
        <strong>Warning:</strong> PacBio HiFi coverage (~12x) is below the recommended 30x for hifiasm. The assembly may be more fragmented than expected. Consider additional sequencing if high contiguity is critical.
    </div>
</div>
"""

        # Phase 1.1: PacBio QC
        if pacbio:
            html += f"""
<div class="card">
    <h2>Phase 1.1: PacBio HiFi Read QC {self._phase_badge('phase1.1_pacbio_qc')}</h2>
    <div class="success"><strong>Read type confirmed:</strong> HiFi (CCS) from PacBio Revio (SMRTbell 3.0, 30h movie)</div>
    <div class="grid-2">
        <div>
            <table>
                <tr><th>Metric</th><th>Value</th></tr>
                <tr><td>Total Reads</td><td>{pacbio.get('Number of reads', 'N/A')}</td></tr>
                <tr><td>Total Bases</td><td>{pacbio.get('Total bases', 'N/A')}</td></tr>
                <tr><td>Mean Read Length</td><td>{pacbio.get('Mean read length', 'N/A')}</td></tr>
                <tr><td>Median Read Length</td><td>{pacbio.get('Median read length', 'N/A')}</td></tr>
                <tr><td>Read N50</td><td>{pacbio.get('Read length N50', 'N/A')}</td></tr>
                <tr><td>Std Dev Length</td><td>{pacbio.get('STDEV read length', 'N/A')}</td></tr>
                <tr><td>Mean Quality</td><td>{pacbio.get('Mean read quality', 'N/A')}</td></tr>
                <tr><td>Median Quality</td><td>{pacbio.get('Median read quality', 'N/A')}</td></tr>
            </table>
        </div>
        <div>
            <div class="grid-2" style="gap:8px">
                <div class="stat-box">
                    <div class="value" style="font-size:1.4em">9,578 bp</div>
                    <div class="label">Read N50</div>
                </div>
                <div class="stat-box">
                    <div class="value" style="font-size:1.4em">Q37.1</div>
                    <div class="label">Median Quality</div>
                </div>
                <div class="stat-box">
                    <div class="value" style="font-size:1.4em">7.88 Gb</div>
                    <div class="label">Total Yield</div>
                </div>
                <div class="stat-box">
                    <div class="value" style="font-size:1.4em">36.73%</div>
                    <div class="label">GC Content</div>
                </div>
            </div>
        </div>
    </div>
"""
            if plots.get("pacbio_readlen") or plots.get("pacbio_lenqual"):
                html += '    <h3 style="margin-top:20px;color:#1B3A5C">Read Distribution Plots</h3>\n    <div class="grid-2">\n'
                if plots.get("pacbio_readlen"):
                    html += f'        <div class="plot-container"><img class="plot-img" src="{plots["pacbio_readlen"]}"><p>Weighted Read Length Histogram</p></div>\n'
                if plots.get("pacbio_lenqual"):
                    html += f'        <div class="plot-container"><img class="plot-img" src="{plots["pacbio_lenqual"]}"><p>Read Length vs Quality (KDE)</p></div>\n'
                html += "    </div>\n"
            if plots.get("pacbio_unweighted") or plots.get("pacbio_yield"):
                html += '    <div class="grid-2" style="margin-top:12px">\n'
                if plots.get("pacbio_unweighted"):
                    html += f'        <div class="plot-container"><img class="plot-img" src="{plots["pacbio_unweighted"]}"><p>Unweighted Read Length Histogram</p></div>\n'
                if plots.get("pacbio_yield"):
                    html += f'        <div class="plot-container"><img class="plot-img" src="{plots["pacbio_yield"]}"><p>Cumulative Yield by Read Length</p></div>\n'
                html += "    </div>\n"
            html += "</div>\n"

        # Phase 1.2: Illumina QC
        if fastp:
            total_before = fastp_summary.get("before_filtering", {})
            total_after = fastp_summary.get("after_filtering", {})
            html += f"""
<div class="card">
    <h2>Phase 1.2: Illumina NovaSeq X Read QC {self._phase_badge('phase1.2_illumina_qc')}</h2>
    <div class="grid-2">
        <div>
            <h3 style="color:#2E6B9E">Before Filtering</h3>
            <table>
                <tr><th>Metric</th><th>Value</th></tr>
                <tr><td>Total Reads</td><td>{total_before.get('total_reads', 'N/A'):,}</td></tr>
                <tr><td>Total Bases</td><td>{total_before.get('total_bases', 'N/A'):,}</td></tr>
                <tr><td>Q20 Rate</td><td>{total_before.get('q20_rate', 0)*100:.2f}%</td></tr>
                <tr><td>Q30 Rate</td><td>{total_before.get('q30_rate', 0)*100:.2f}%</td></tr>
                <tr><td>GC Content</td><td>{total_before.get('gc_content', 0)*100:.2f}%</td></tr>
            </table>
        </div>
        <div>
            <h3 style="color:#27AE60">After Filtering</h3>
            <table>
                <tr><th>Metric</th><th>Value</th></tr>
                <tr><td>Total Reads</td><td>{total_after.get('total_reads', 'N/A'):,}</td></tr>
                <tr><td>Total Bases</td><td>{total_after.get('total_bases', 'N/A'):,}</td></tr>
                <tr><td>Q20 Rate</td><td>{total_after.get('q20_rate', 0)*100:.2f}%</td></tr>
                <tr><td>Q30 Rate</td><td>{total_after.get('q30_rate', 0)*100:.2f}%</td></tr>
                <tr><td>GC Content</td><td>{total_after.get('gc_content', 0)*100:.2f}%</td></tr>
            </table>
        </div>
    </div>
    <h3 style="margin-top:16px;color:#1B3A5C">Filtering Summary</h3>
    <div class="grid-3" style="margin-top:8px">
        <div class="stat-box">
            <div class="value" style="font-size:1.3em">{filt_result.get('passed_filter_reads', 0):,}</div>
            <div class="label">Reads Passed ({100*filt_result.get('passed_filter_reads',0)/max(total_before.get('total_reads',1),1):.1f}%)</div>
        </div>
        <div class="stat-box">
            <div class="value" style="font-size:1.3em">{dup_rate*100:.2f}%</div>
            <div class="label">Duplication Rate</div>
        </div>
        <div class="stat-box">
            <div class="value" style="font-size:1.3em">{insert_peak} bp</div>
            <div class="label">Insert Size Peak</div>
        </div>
    </div>
</div>
"""

        # Phase 1.3: GenomeScope
        if genomescope:
            html += f"""
<div class="card">
    <h2>Phase 1.3: K-mer Genome Survey (GenomeScope 2.0) {self._phase_badge('phase1.3_kmer_survey')}</h2>
    <div class="grid-2">
        <div>
            <table>
                <tr><th>Property</th><th>Value</th></tr>
"""
            gs_text = self._read_text(self.cfg.GENOMESCOPE_DIR / "summary.txt")
            for line in gs_text.strip().split("\n"):
                if line.startswith("Genome") or line.startswith("Homo") or line.startswith("Hetero") or line.startswith("Model") or line.startswith("Read"):
                    # Parse the property line
                    parts = line.split()
                    if len(parts) >= 3:
                        # Find where values start (they're right-aligned)
                        prop = []
                        vals = []
                        for p in parts:
                            if p.replace(",", "").replace(".", "").replace("%", "").replace("-", "").isdigit() or p.endswith("%") or p.endswith("bp"):
                                vals.append(p)
                            else:
                                if not vals:
                                    prop.append(p)
                                else:
                                    vals.append(p)
                        prop_name = " ".join(prop)
                        val_str = " ".join(vals) if vals else ""
                        html += f'                <tr><td>{prop_name}</td><td>{val_str}</td></tr>\n'

            html += f"""            </table>
        </div>
        <div>
            <div class="grid-2" style="gap:8px">
                <div class="stat-box">
                    <div class="value" style="font-size:1.4em">~655 Mb</div>
                    <div class="label">Genome Size</div>
                </div>
                <div class="stat-box">
                    <div class="value" style="font-size:1.4em">0.55%</div>
                    <div class="label">Heterozygosity</div>
                </div>
                <div class="stat-box">
                    <div class="value" style="font-size:1.4em">~35%</div>
                    <div class="label">Repeat Content</div>
                </div>
                <div class="stat-box">
                    <div class="value" style="font-size:1.4em">30.7x</div>
                    <div class="label">K-mer Coverage</div>
                </div>
            </div>
            <div class="danger" style="margin-top:12px">
                <strong>Low PacBio Coverage:</strong> 7.88 Gb / 655 Mb = ~12x. Recommended: &ge;30x for hifiasm.
            </div>
            <div class="success" style="margin-top:8px">
                <strong>Illumina Coverage:</strong> 52.33 Gb / 655 Mb = ~80x. Sufficient for polishing.
            </div>
        </div>
    </div>
"""
            if plots.get("gs_linear") or plots.get("gs_log"):
                html += '    <h3 style="margin-top:20px;color:#1B3A5C">K-mer Frequency Plots</h3>\n    <div class="grid-2">\n'
                if plots.get("gs_linear"):
                    html += f'        <div class="plot-container"><img class="plot-img" src="{plots["gs_linear"]}"><p>K-mer Profile (Linear Scale)</p></div>\n'
                if plots.get("gs_log"):
                    html += f'        <div class="plot-container"><img class="plot-img" src="{plots["gs_log"]}"><p>K-mer Profile (Log Scale)</p></div>\n'
                html += "    </div>\n"
            if plots.get("gs_transformed_linear") or plots.get("gs_transformed_log"):
                html += '    <div class="grid-2" style="margin-top:12px">\n'
                if plots.get("gs_transformed_linear"):
                    html += f'        <div class="plot-container"><img class="plot-img" src="{plots["gs_transformed_linear"]}"><p>Transformed K-mer Profile (Linear)</p></div>\n'
                if plots.get("gs_transformed_log"):
                    html += f'        <div class="plot-container"><img class="plot-img" src="{plots["gs_transformed_log"]}"><p>Transformed K-mer Profile (Log)</p></div>\n'
                html += "    </div>\n"
            html += "</div>\n"

        # ── Phase 2: Assembly Comparison ──
        html += self._generate_phase2_html()

        # ── Phase 3: Polishing ──
        if self.tracker.is_done("phase3_polish"):
            html += f"""
<div class="card">
    <h2>Phase 3: Polishing {self._phase_badge('phase3_polish')}</h2>
    <div class="success">Assembly polished with NextPolish (2 rounds of Illumina correction)</div>
</div>
"""

        # ── Phase 4: Decontamination ──
        if self.tracker.is_done("phase4_decontam"):
            html += f"""
<div class="card">
    <h2>Phase 4: Decontamination {self._phase_badge('phase4_decontam')}</h2>
    <div class="success">BlobTools screening complete. Clean assembly generated.</div>
</div>
"""

        # ── Phase 6: Final QC ──
        html += self._generate_phase6_html()

        html += f"""
<div class="timestamp">
    Report generated by genome_assembly_pipeline.py &nbsp;|&nbsp; {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
</div>

</div>
</body>
</html>"""

        with open(self.report_path, "w") as f:
            f.write(html)

    def _generate_phase2_html(self) -> str:
        """Generate Phase 2 assembly comparison HTML section."""
        # Check if any assembler has completed
        assemblers_done = any(
            self.tracker.is_done(s) for s in
            ["phase2.1_hifiasm", "phase2.1b_masurca", "phase2.1c_flye", "phase2.1d_nextdenovo"]
        )
        if not assemblers_done:
            return ""

        html = f"""
<div class="card">
    <h2>Phase 2: Assembly {self._phase_badge('phase2.3_compare')}</h2>
    <div class="grid-2" style="margin-bottom:16px">
        <div class="stat-box">
            <div class="value" style="font-size:1.2em">4 Assemblers</div>
            <div class="label">hifiasm, MaSuRCA, Flye, NextDenovo</div>
        </div>
        <div class="stat-box">
            <div class="value" style="font-size:1.2em">6 Pairwise</div>
            <div class="label">MUMmer Alignments</div>
        </div>
    </div>
"""

        # Per-assembler status
        asm_info = [
            ("phase2.1_hifiasm", "hifiasm", "HiFi-only"),
            ("phase2.1b_masurca", "MaSuRCA", "HiFi + Illumina hybrid"),
            ("phase2.1c_flye", "Flye", "HiFi mode"),
            ("phase2.1d_nextdenovo", "NextDenovo", "HiFi mode"),
        ]
        html += '<div class="grid-2" style="margin-bottom:16px">\n'
        for step, name, desc in asm_info:
            badge = self._phase_badge(step)
            html += f'<div class="stat-box"><div class="label">{name} ({desc})</div>{badge}</div>\n'
        html += '</div>\n'

        # QUAST comparison table
        quast_tsv = self.cfg.COMPARISON_DIR / "quast" / "report.tsv"
        if quast_tsv.exists():
            html += '<h3 style="color:#1B3A5C;margin-top:16px">QUAST Contiguity Comparison</h3>\n'
            html += '<table>\n'
            with open(quast_tsv) as f:
                rows = [line.strip().split("\t") for line in f if line.strip()]
            if rows:
                # Header
                html += '<tr>' + ''.join(f'<th>{c}</th>' for c in rows[0]) + '</tr>\n'
                key_metrics = {
                    "# contigs", "# contigs (>= 0 bp)", "# contigs (>= 50000 bp)",
                    "Total length", "Total length (>= 50000 bp)",
                    "Largest contig", "N50", "N75", "L50", "L75", "GC (%)",
                    "# N's per 100 kbp",
                }
                for row in rows[1:]:
                    metric = row[0] if row else ""
                    if metric in key_metrics:
                        html += '<tr>' + ''.join(f'<td>{c}</td>' for c in row) + '</tr>\n'
            html += '</table>\n'

        # BUSCO comparison
        comp_dir = self.cfg.COMPARISON_DIR
        busco_data = {}
        for name in ["hifiasm", "masurca", "flye", "nextdenovo"]:
            busco_dir = comp_dir / f"busco_{name}"
            if not busco_dir.exists():
                continue
            import glob as glob_mod
            summaries = glob_mod.glob(str(busco_dir / "short_summary*.txt"))
            if not summaries:
                summaries = glob_mod.glob(str(busco_dir / "run_*" / "short_summary*.txt"))
            if summaries:
                with open(summaries[0]) as f:
                    for line in f:
                        line = line.strip()
                        if line.startswith("C:") or "\tC:" in line:
                            busco_data[name] = line.split("\t")[-1] if "\t" in line else line
                            break

        if busco_data:
            html += '<h3 style="color:#1B3A5C;margin-top:20px">BUSCO Completeness (hymenoptera_odb10)</h3>\n'
            html += '<table><tr><th>Assembler</th><th>BUSCO Summary</th></tr>\n'
            for name, summary in busco_data.items():
                html += f'<tr><td>{name}</td><td><code>{summary}</code></td></tr>\n'
            html += '</table>\n'

        # MUMmer summary
        mummer_dir = comp_dir / "mummer"
        if mummer_dir.exists():
            import glob as glob_mod
            reports = sorted(glob_mod.glob(str(mummer_dir / "*.report")))
            if reports:
                html += '<h3 style="color:#1B3A5C;margin-top:20px">MUMmer Pairwise Alignment</h3>\n'
                html += '<table><tr><th>Comparison</th><th>Aligned (ref)</th><th>Aligned (qry)</th><th>Avg Identity</th><th>SNPs</th><th>Indels</th></tr>\n'
                for rpt in reports:
                    rpt_name = Path(rpt).stem
                    data = {"aligned_ref": "—", "aligned_qry": "—", "avg_id": "—", "snps": "—", "indels": "—"}
                    with open(rpt) as f:
                        for line in f:
                            line = line.strip()
                            if line.startswith("AlignedBases"):
                                parts = line.split()
                                if len(parts) >= 3:
                                    data["aligned_ref"] = parts[1]
                                    data["aligned_qry"] = parts[2]
                            elif line.startswith("AvgIdentity") and data["avg_id"] == "—":
                                parts = line.split()
                                if len(parts) >= 2:
                                    data["avg_id"] = parts[1]
                            elif line.startswith("TotalSNPs"):
                                parts = line.split()
                                if len(parts) >= 2:
                                    data["snps"] = parts[1]
                            elif line.startswith("TotalIndels"):
                                parts = line.split()
                                if len(parts) >= 2:
                                    data["indels"] = parts[1]
                    html += (f'<tr><td>{rpt_name}</td><td>{data["aligned_ref"]}</td>'
                             f'<td>{data["aligned_qry"]}</td><td>{data["avg_id"]}</td>'
                             f'<td>{data["snps"]}</td><td>{data["indels"]}</td></tr>\n')
                html += '</table>\n'

            # MUMmer dot plots
            pngs = sorted(glob_mod.glob(str(mummer_dir / "*.png")))
            if pngs:
                html += '<h3 style="color:#1B3A5C;margin-top:20px">MUMmer Dot Plots</h3>\n<div class="grid-2">\n'
                for png in pngs:
                    img_data = self._img_to_base64(Path(png))
                    if img_data:
                        html += f'<div class="plot-container"><img class="plot-img" src="{img_data}"><p>{Path(png).stem}</p></div>\n'
                html += '</div>\n'

        html += "</div>\n"
        return html

    def _generate_phase6_html(self) -> str:
        """Generate Phase 6 final QC HTML section."""
        if not self.tracker.is_done("phase6_quality"):
            return ""

        html = f"""
<div class="card">
    <h2>Phase 6: Final Quality Assessment {self._phase_badge('phase6_quality')}</h2>
"""
        # Final QUAST
        quast_report = self.cfg.QUAST_DIR / "report.txt"
        if quast_report.exists():
            html += '<h3 style="color:#1B3A5C">Final Assembly QUAST</h3><pre style="background:#F8F9FA;padding:12px;border-radius:6px;font-size:0.85em">'
            with open(quast_report) as f:
                html += f.read()
            html += '</pre>\n'

        # Final BUSCO
        if self.cfg.BUSCO_DIR.exists():
            import glob as glob_mod
            summaries = glob_mod.glob(str(self.cfg.BUSCO_DIR / "short_summary*.txt"))
            if summaries:
                html += '<h3 style="color:#1B3A5C;margin-top:16px">Final BUSCO</h3><pre style="background:#F8F9FA;padding:12px;border-radius:6px;font-size:0.85em">'
                with open(summaries[0]) as f:
                    html += f.read()
                html += '</pre>\n'

        html += "</div>\n"
        return html

    def update(self):
        """Regenerate the report (called after each phase)."""
        self.generate()


# ============================================================
# PPTX Updater (auto-update slides with results)
# ============================================================

class PptxUpdater:
    """Add or update slides in the PPTX presentation with pipeline results."""

    def __init__(self, cfg, tracker: StatusTracker):
        self.cfg = cfg
        self.tracker = tracker
        self.pptx_path = cfg.PPTX_FILE

    def update(self):
        """Add results slides to the PPTX after assembly comparison."""
        try:
            from pptx import Presentation
            from pptx.util import Inches, Pt, Emu
            from pptx.dml.color import RGBColor
            from pptx.enum.text import PP_ALIGN
        except ImportError:
            return  # python-pptx not installed

        if not self.pptx_path.exists():
            return

        prs = Presentation(str(self.pptx_path))

        # Remove any previously auto-generated results slides (tagged with marker)
        slides_to_keep = []
        marker = "[AUTO-RESULTS]"
        for slide in prs.slides:
            has_marker = False
            for shape in slide.shapes:
                if shape.has_text_frame:
                    for para in shape.text_frame.paragraphs:
                        if marker in para.text:
                            has_marker = True
                            break
                if has_marker:
                    break
            if not has_marker:
                slides_to_keep.append(slide)

        # We can't easily delete slides in python-pptx, so we'll append new ones
        # and use the marker to identify them on re-runs

        # Only add slides if Phase 2 comparison is done
        if not self.tracker.is_done("phase2.3_compare"):
            return

        # ── Slide: Assembly Comparison Summary ──
        self._add_comparison_slide(prs, marker)

        # ── Slide: BUSCO Results ──
        self._add_busco_slide(prs, marker)

        # ── Slide: MUMmer Results ──
        self._add_mummer_slide(prs, marker)

        # ── Slide: Sequencing Decision ──
        self._add_decision_slide(prs, marker)

        prs.save(str(self.pptx_path))

    def _add_text_box(self, slide, left, top, width, height, text,
                      font_size=12, bold=False, color=None, alignment=None):
        """Helper to add a text box to a slide."""
        from pptx.util import Inches, Pt
        from pptx.dml.color import RGBColor
        from pptx.enum.text import PP_ALIGN

        txBox = slide.shapes.add_textbox(
            Inches(left), Inches(top), Inches(width), Inches(height)
        )
        tf = txBox.text_frame
        tf.word_wrap = True
        p = tf.paragraphs[0]
        p.text = text
        p.font.size = Pt(font_size)
        if bold:
            p.font.bold = True
        if color:
            p.font.color.rgb = RGBColor(*color)
        if alignment:
            p.alignment = alignment
        return tf

    def _add_comparison_slide(self, prs, marker):
        """Add QUAST comparison results slide."""
        from pptx.util import Inches, Pt
        from pptx.dml.color import RGBColor
        from pptx.enum.text import PP_ALIGN

        slide_layout = prs.slide_layouts[6]  # Blank
        slide = prs.slides.add_slide(slide_layout)

        # Title
        self._add_text_box(slide, 0.5, 0.3, 9, 0.6,
                           "Phase 2: Assembly Comparison (QUAST)", 24, True, (27, 58, 92))

        # Marker (tiny, hidden)
        self._add_text_box(slide, 9, 7, 1, 0.2, marker, 4, color=(255, 255, 255))

        # Parse QUAST
        quast_tsv = self.cfg.COMPARISON_DIR / "quast" / "report.tsv"
        if quast_tsv.exists():
            with open(quast_tsv) as f:
                rows = [line.strip().split("\t") for line in f if line.strip()]
            if rows:
                key_metrics = [
                    "# contigs", "Total length", "Largest contig",
                    "N50", "N75", "L50", "GC (%)",
                ]
                # Build table text
                header = rows[0]
                table_text = "\t".join(header) + "\n"
                table_text += "─" * 60 + "\n"
                for row in rows[1:]:
                    if row[0] in key_metrics:
                        table_text += "\t".join(row) + "\n"

                self._add_text_box(slide, 0.5, 1.2, 9, 4.5, table_text, 11)
        else:
            self._add_text_box(slide, 0.5, 1.5, 9, 1, "QUAST report not yet available", 14)

        # Timestamp
        self._add_text_box(slide, 0.5, 6.8, 9, 0.3,
                           f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M')}", 8,
                           color=(150, 150, 150))

    def _add_busco_slide(self, prs, marker):
        """Add BUSCO comparison results slide."""
        from pptx.util import Inches, Pt
        from pptx.dml.color import RGBColor

        slide_layout = prs.slide_layouts[6]
        slide = prs.slides.add_slide(slide_layout)

        self._add_text_box(slide, 0.5, 0.3, 9, 0.6,
                           "Phase 2: BUSCO Completeness Comparison", 24, True, (27, 58, 92))
        self._add_text_box(slide, 9, 7, 1, 0.2, marker, 4, color=(255, 255, 255))

        comp_dir = self.cfg.COMPARISON_DIR
        y_pos = 1.3
        for name in ["hifiasm", "masurca", "flye", "nextdenovo"]:
            busco_dir = comp_dir / f"busco_{name}"
            if not busco_dir.exists():
                continue
            import glob as glob_mod
            summaries = glob_mod.glob(str(busco_dir / "short_summary*.txt"))
            if not summaries:
                summaries = glob_mod.glob(str(busco_dir / "run_*" / "short_summary*.txt"))
            if summaries:
                self._add_text_box(slide, 0.5, y_pos, 2, 0.3, f"{name}:", 14, True, (27, 58, 92))
                with open(summaries[0]) as f:
                    text = f.read()
                # Extract the summary line
                for line in text.split("\n"):
                    line = line.strip()
                    if line.startswith("C:") or (line and "\tC:" in line):
                        summary_line = line.split("\t")[-1] if "\t" in line else line
                        self._add_text_box(slide, 2.8, y_pos, 6.5, 0.3, summary_line, 12)
                        break
                y_pos += 0.5

        self._add_text_box(slide, 0.5, 6.0, 9, 0.5,
                           "Lineage: hymenoptera_odb10", 10, color=(100, 100, 100))
        self._add_text_box(slide, 0.5, 6.8, 9, 0.3,
                           f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M')}", 8,
                           color=(150, 150, 150))

    def _add_mummer_slide(self, prs, marker):
        """Add MUMmer pairwise alignment results slide."""
        from pptx.util import Inches, Pt
        from pptx.dml.color import RGBColor

        slide_layout = prs.slide_layouts[6]
        slide = prs.slides.add_slide(slide_layout)

        self._add_text_box(slide, 0.5, 0.3, 9, 0.6,
                           "Phase 2: MUMmer Pairwise Alignments", 24, True, (27, 58, 92))
        self._add_text_box(slide, 9, 7, 1, 0.2, marker, 4, color=(255, 255, 255))

        mummer_dir = self.cfg.COMPARISON_DIR / "mummer"
        if mummer_dir.exists():
            import glob as glob_mod
            reports = sorted(glob_mod.glob(str(mummer_dir / "*.report")))
            y_pos = 1.2
            table_lines = ["Comparison\tAligned(ref)\tAligned(qry)\tIdentity\tSNPs"]
            table_lines.append("─" * 70)
            for rpt in reports:
                rpt_name = Path(rpt).stem
                data = {"aref": "—", "aqry": "—", "id": "—", "snps": "—"}
                with open(rpt) as f:
                    for line in f:
                        line = line.strip()
                        if line.startswith("AlignedBases"):
                            parts = line.split()
                            if len(parts) >= 3:
                                data["aref"] = parts[1]
                                data["aqry"] = parts[2]
                        elif line.startswith("AvgIdentity") and data["id"] == "—":
                            parts = line.split()
                            if len(parts) >= 2:
                                data["id"] = parts[1]
                        elif line.startswith("TotalSNPs"):
                            parts = line.split()
                            if len(parts) >= 2:
                                data["snps"] = parts[1]
                table_lines.append(f'{rpt_name}\t{data["aref"]}\t{data["aqry"]}\t{data["id"]}\t{data["snps"]}')

            self._add_text_box(slide, 0.3, y_pos, 9.4, 5, "\n".join(table_lines), 10)
        else:
            self._add_text_box(slide, 0.5, 1.5, 9, 1, "MUMmer results not yet available", 14)

        self._add_text_box(slide, 0.5, 6.8, 9, 0.3,
                           f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M')}", 8,
                           color=(150, 150, 150))

    def _add_decision_slide(self, prs, marker):
        """Add sequencing decision slide based on results."""
        from pptx.util import Inches, Pt
        from pptx.dml.color import RGBColor

        slide_layout = prs.slide_layouts[6]
        slide = prs.slides.add_slide(slide_layout)

        self._add_text_box(slide, 0.5, 0.3, 9, 0.6,
                           "Assembly Results: Sequencing Decision", 24, True, (27, 58, 92))
        self._add_text_box(slide, 9, 7, 1, 0.2, marker, 4, color=(255, 255, 255))

        self._add_text_box(slide, 0.5, 1.2, 9, 4.5,
                           "Review the QUAST, BUSCO, and MUMmer results above to determine:\n\n"
                           "1. Which assembler produced the best assembly?\n"
                           "   • Highest BUSCO completeness (C%)\n"
                           "   • Lowest duplication (D%)\n"
                           "   • Highest N50 / largest contigs\n"
                           "   • Assembly size closest to ~655 Mb estimate\n\n"
                           "2. Do the assemblers agree on genome structure?\n"
                           "   • High MUMmer identity → consistent assemblies\n"
                           "   • Large structural differences → potential misassemblies or insufficient data\n\n"
                           "3. Is additional sequencing needed?\n"
                           "   • If BUSCO < 90% or assemblies strongly disagree → consider more PacBio\n"
                           "   • If BUSCO > 95% and assemblies agree → proceed with best assembly\n\n"
                           "DECISION: _________________________________ (fill after review)",
                           12)

        self._add_text_box(slide, 0.5, 6.8, 9, 0.3,
                           f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M')}", 8,
                           color=(150, 150, 150))


def main():
    parser = argparse.ArgumentParser(
        description="denovo-assembly-core genome assembly pipeline",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python -m denovo_assembly_core.pipeline --config project.yaml --phase 1
  python -m denovo_assembly_core.pipeline --config project.yaml --phase 1.3
  python -m denovo_assembly_core.pipeline --config project.yaml --phase 1-3
  python -m denovo_assembly_core.pipeline --config project.yaml --phase all
  python -m denovo_assembly_core.pipeline --config project.yaml --phase 2 --force
  python -m denovo_assembly_core.pipeline --config project.yaml --status
        """
    )
    parser.add_argument("--config", type=str, default=None,
                        help="Path to project.yaml (default: $PROJECT_CONFIG, then ./project.yaml)")
    parser.add_argument("--phase", type=str, default=None,
                        help="Phase(s) to run: '1', '1.3', '1-3', 'all'")
    parser.add_argument("--from", dest="from_phase", type=str, default=None,
                        help="Run from this phase to the end (e.g. '3' runs 3 through 7.5)")
    parser.add_argument("--resume", action="store_true",
                        help="Auto-detect first non-completed phase and run from there to end")
    parser.add_argument("--list", action="store_true",
                        help="List available phases and exit")
    parser.add_argument("--force", action="store_true",
                        help="Re-run steps even if already completed (default: skip completed)")
    parser.add_argument("--status", action="store_true",
                        help="Show pipeline status and exit")
    parser.add_argument("--report", action="store_true",
                        help="Generate HTML report + RESULTS.md and exit")
    parser.add_argument("--no-report", action="store_true",
                        help="Skip HTML/RESULTS/PPTX generation after each phase")

    args = parser.parse_args()

    config_path = args.config or os.environ.get("PROJECT_CONFIG") or "project.yaml"
    cfg = Config(config_path)
    logger = setup_logging(cfg.PROJECT_DIR / "logs")
    tracker = StatusTracker(cfg.STATUS_FILE)

    # Initialize output generators
    report = ReportGenerator(cfg, tracker)
    results_writer = ResultsWriter(cfg, tracker)
    pptx_updater = PptxUpdater(cfg, tracker)

    if args.report:
        report.generate()
        results_writer.update()
        pptx_updater.update()
        logger.info(f"HTML report: {report.report_path}")
        logger.info(f"RESULTS.md: {results_writer.results_path}")
        logger.info(f"PPTX updated: {cfg.PPTX_FILE}")
        return

    if args.status:
        print("\n=== Pipeline Status ===")
        for phase_id in PHASE_ORDER:
            name, _ = PHASES[phase_id]
            status = tracker.status.get(f"phase{phase_id.replace('.', '.')}", {})
            st = status.get("status", "pending")
            icon = {"completed": "OK", "in_progress": ">>", "failed": "!!", "pending": "--"}
            print(f"  [{icon.get(st, '??')}] {name}: {st}")
        print()
        return

    if args.list:
        print("\n=== Available Phases (in execution order) ===")
        for phase_id in PHASE_ORDER:
            name, _ = PHASES[phase_id]
            print(f"  {phase_id:<6} {name}")
        print("\nUsage examples:")
        print("  --phase 3          Run only phase 3")
        print("  --phase 3-7        Run phases 3 through 7")
        print("  --from 3           Run phase 3 to end")
        print("  --resume           Continue from first incomplete phase")
        print()
        return

    # --resume: find first non-completed phase
    if args.resume:
        first_pending = None
        for phase_id in PHASE_ORDER:
            step_prefix = f"phase{phase_id}"
            done = any(
                k.startswith(step_prefix) and v.get("status") == "completed"
                for k, v in tracker.status.items()
            )
            if not done:
                first_pending = phase_id
                break
        if first_pending is None:
            logger.info("All phases already completed. Nothing to resume.")
            return
        args.from_phase = first_pending
        logger.info(f"--resume: starting from phase {first_pending}")

    # --from PHASE: convert to a range "PHASE-<last>"
    if args.from_phase:
        last = PHASE_ORDER[-1]
        args.phase = f"{args.from_phase}-{last}"

    if not args.phase:
        parser.print_help()
        return

    # If --force, temporarily clear status for requested phases
    if args.force:
        phases_to_run = parse_phase_range(args.phase)
        for phase_id in phases_to_run:
            # Map phase_id to step keys used in tracker
            for step_key in list(tracker.status.keys()):
                if phase_id in step_key:
                    del tracker.status[step_key]
            tracker._save()
        logger.info("--force: cleared status for requested phases")

    phases_to_run = parse_phase_range(args.phase)
    if not phases_to_run:
        print(f"Error: No matching phases for '{args.phase}'")
        sys.exit(1)

    logger.info(f"{'='*60}")
    logger.info(f"{cfg.SPECIES_SHORT} Genome Assembly Pipeline")
    logger.info(f"Running phases: {', '.join(phases_to_run)}")
    logger.info(f"Completed steps will be skipped (use --force to re-run)")
    logger.info(f"{'='*60}")

    def _notify(subject, body):
        """Send email notification (best-effort, never halts pipeline)."""
        try:
            send_email(cfg, f"[{cfg.SPECIES_SHORT} Pipeline] {subject}", body)
        except Exception as e:
            logger.warning(f"Email notification failed (non-fatal): {e}")

    _notify("Pipeline started",
            f"Running phases: {', '.join(phases_to_run)}\n"
            f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

    failed_phases = []

    for phase_id in phases_to_run:
        name, func = PHASES[phase_id]
        logger.info(f"\n{'='*60}")
        logger.info(f"Starting: {name}")
        logger.info(f"{'='*60}")
        try:
            func(cfg, tracker, logger)
            logger.info(f"Completed: {name}")
            _notify(f"{name} - COMPLETED",
                    f"{name} completed successfully.\n"
                    f"Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        except Exception as e:
            step_key = f"phase{phase_id}"
            tracker.mark_failed(step_key, str(e))
            logger.error(f"FAILED: {name} - {e}")

            if phase_id in FAULT_TOLERANT_PHASES:
                # Assembly phases: log failure, notify, but continue
                logger.warning(f"{name} failed but pipeline continues (fault-tolerant mode)")
                failed_phases.append(name)
                _notify(f"{name} - FAILED (continuing)",
                        f"{name} failed:\n{e}\n\n"
                        f"Pipeline continues — this assembler is independent of the others.")
            else:
                # Critical phase: halt pipeline
                logger.error("Pipeline halted. Fix the error and re-run (completed steps auto-skipped)")
                _notify(f"{name} - FAILED (pipeline halted)",
                        f"{name} failed:\n{e}\n\n"
                        f"Pipeline halted. Fix the error and re-run.")
                if not args.no_report:
                    try:
                        report.update()
                        results_writer.update()
                    except Exception:
                        pass
                sys.exit(1)

        # Auto-generate all outputs after each phase
        if not args.no_report:
            try:
                report.update()
                logger.info(f"HTML report updated: {report.report_path}")
            except Exception as e:
                logger.warning(f"HTML report generation failed (non-fatal): {e}")
            try:
                results_writer.update()
                logger.info(f"RESULTS.md updated: {results_writer.results_path}")
            except Exception as e:
                logger.warning(f"RESULTS.md generation failed (non-fatal): {e}")
            try:
                pptx_updater.update()
                logger.info(f"PPTX updated: {cfg.PPTX_FILE}")
            except Exception as e:
                logger.warning(f"PPTX update failed (non-fatal): {e}")

    # Final summary
    summary = f"Pipeline run complete!\n"
    summary += f"Output files:\n"
    summary += f"  HTML report: {report.report_path}\n"
    summary += f"  RESULTS.md:  {results_writer.results_path}\n"
    summary += f"  PPTX:        {cfg.PPTX_FILE}\n"
    if failed_phases:
        summary += f"\nFailed assemblers (non-fatal): {', '.join(failed_phases)}\n"
        summary += "Downstream steps proceeded with available assemblies."

    logger.info(f"\n{'='*60}")
    logger.info("Pipeline run complete!")
    logger.info(f"Output files:")
    logger.info(f"  HTML report: {report.report_path}")
    logger.info(f"  RESULTS.md:  {results_writer.results_path}")
    logger.info(f"  PPTX:        {cfg.PPTX_FILE}")
    if failed_phases:
        logger.warning(f"Failed assemblers (non-fatal): {', '.join(failed_phases)}")
    logger.info(f"{'='*60}")

    _notify("Pipeline FINISHED", summary)


if __name__ == "__main__":
    main()
