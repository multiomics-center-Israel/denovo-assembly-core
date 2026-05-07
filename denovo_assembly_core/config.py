"""Project configuration loaded from a YAML file.

The Config object exposes uppercase attributes so the rest of the pipeline can
reference them as `cfg.PROJECT_DIR`, `cfg.PACBIO_READS`, etc., matching the
flat-class layout the pipeline used before parameterization.
"""

import os
from pathlib import Path

import yaml


DEFAULT_KRAKEN2_DB_URL = (
    "https://genome-idx.s3.amazonaws.com/kraken/k2_pluspf_08gb_20240904.tar.gz"
)


class Config:
    """Pipeline configuration. Construct with a path to project.yaml."""

    def __init__(self, yaml_path):
        yaml_path = Path(yaml_path).resolve()
        if not yaml_path.exists():
            raise FileNotFoundError(f"Project config not found: {yaml_path}")
        with open(yaml_path) as f:
            data = yaml.safe_load(f) or {}

        self._yaml_path = yaml_path

        # ── Project ─────────────────────────────────────────────
        proj = data.get("project", {}) or {}
        if "dir" not in proj:
            raise ValueError(f"{yaml_path}: project.dir is required")
        self.PROJECT_DIR = Path(proj["dir"]).expanduser().resolve()
        self.THREADS = int(proj.get("threads", 16))

        # ── Species ─────────────────────────────────────────────
        sp = data.get("species", {}) or {}
        self.SPECIES_DISPLAY = sp.get("display_name", "Unknown species")
        self.SPECIES_SHORT = sp.get("short_name", self.SPECIES_DISPLAY)
        self.SPECIES_SLUG = sp.get("slug", "genome")
        # Backwards-compat alias used in older code paths
        self.SPECIES = self.SPECIES_SLUG

        # ── Sample ─────────────────────────────────────────────
        self.SAMPLE_ID = (data.get("sample", {}) or {}).get("id", "sample")

        # ── Conda env ──────────────────────────────────────────
        self.CONDA_ENV = (data.get("conda", {}) or {}).get("env", "genome_assembly")

        # ── Inputs ─────────────────────────────────────────────
        inp = data.get("inputs", {}) or {}
        self.PACBIO_READS = self._resolve(inp.get("pacbio_reads"))
        self.ILLUMINA_R1 = self._resolve(inp.get("illumina_r1"))
        self.ILLUMINA_R2 = self._resolve(inp.get("illumina_r2"))

        # ── Kraken2 ────────────────────────────────────────────
        kr = data.get("kraken2", {}) or {}
        env_db = os.environ.get("KRAKEN2_DB")
        if env_db:
            self.KRAKEN2_DB = Path(env_db)
        else:
            self.KRAKEN2_DB = self._resolve(kr.get("db", "qc/kraken2/pluspf_08gb"))
        self.KRAKEN2_DB_URL = kr.get("db_url", DEFAULT_KRAKEN2_DB_URL)

        # ── RNA-Seq for annotation ─────────────────────────────
        rs = data.get("rnaseq", {}) or {}
        self.RNASEQ_SRA = rs.get("sra")
        self.RNASEQ_BIOPROJECT = rs.get("bioproject")
        self.TSA_ACCESSION = rs.get("tsa_accession")
        self.TSA_RANGE = rs.get("tsa_range")

        # ── Email notification ─────────────────────────────────
        nt = data.get("notification", {}) or {}
        self.NOTIFY_ENABLED = bool(nt.get("enabled", True))
        self.SMTP_HOST = nt.get("smtp_host", "localhost")
        self.SMTP_PORT = int(nt.get("smtp_port", 25))
        self.FROM_ADDR = nt.get("from_addr", "")
        self.TO_ADDR = nt.get("to_addr", "")

        # ── PPTX (optional) ────────────────────────────────────
        rep = data.get("report", {}) or {}
        pptx = rep.get("pptx_filename")
        self.PPTX_FILE = (self.PROJECT_DIR / pptx) if pptx else None

        # ── Output directories (mirror legacy layout) ──────────
        self.QC_DIR = self.PROJECT_DIR / "qc"
        self.ASSEMBLY_DIR = self.PROJECT_DIR / "assembly"
        self.POLISH_DIR = self.PROJECT_DIR / "polish"
        self.DECONTAM_DIR = self.PROJECT_DIR / "decontamination"
        self.ANNOTATION_DIR = self.PROJECT_DIR / "annotation"
        self.RNASEQ_DIR = self.PROJECT_DIR / "rnaseq"

        # Phase 1 outputs
        self.NANOPLOT_DIR = self.QC_DIR / "nanoplot_pacbio"
        self.ILLUMINA_QC_DIR = self.QC_DIR / "illumina"
        self.GENOMESCOPE_DIR = self.QC_DIR / "genomescope"
        self.CUTADAPT_R1 = self.ILLUMINA_QC_DIR / "cutadapt_R1.fastq.gz"
        self.CUTADAPT_R2 = self.ILLUMINA_QC_DIR / "cutadapt_R2.fastq.gz"
        self.TRIMMED_R1 = self.ILLUMINA_QC_DIR / "trimmed_R1.fastq.gz"
        self.TRIMMED_R2 = self.ILLUMINA_QC_DIR / "trimmed_R2.fastq.gz"

        # Phase 1.2b: Kraken2 read decontamination
        self.KRAKEN2_DIR = self.QC_DIR / "kraken2"
        self.CLEAN_R1 = self.ILLUMINA_QC_DIR / "clean_R1.fastq.gz"
        self.CLEAN_R2 = self.ILLUMINA_QC_DIR / "clean_R2.fastq.gz"
        self.CLEAN_PACBIO = self.QC_DIR / "clean_pacbio.fastq.gz"
        self.KRAKEN2_ILL_REPORT = self.KRAKEN2_DIR / "illumina.kreport"
        self.KRAKEN2_PB_REPORT = self.KRAKEN2_DIR / "pacbio.kreport"

        # Phase 2 — Mode 1 (hifiasm)
        self.HIFIASM_DIR = self.ASSEMBLY_DIR / "hifiasm"
        self.HIFIASM_PREFIX = self.HIFIASM_DIR / f"{self.SPECIES_SLUG}_asm"
        self.PRIMARY_CONTIGS = self.HIFIASM_DIR / f"{self.SPECIES_SLUG}_asm.p_ctg.fa"
        self.PURGED_ASSEMBLY_HIFI = self.ASSEMBLY_DIR / "hifiasm_purged" / "purged.fa"

        # Phase 2 — Mode 2 (MaSuRCA)
        self.MASURCA_DIR = self.ASSEMBLY_DIR / "masurca"
        self.MASURCA_CONFIG = self.MASURCA_DIR / "sr_config.txt"
        self.MASURCA_ASSEMBLY = (
            self.MASURCA_DIR / "CA.mr.99.17.15.0.02" / "primary.genome.scf.fasta"
        )
        self.PURGED_ASSEMBLY_HYBRID = self.ASSEMBLY_DIR / "masurca_purged" / "purged.fa"

        # Phase 2 — Mode 3 (Flye)
        self.FLYE_DIR = self.ASSEMBLY_DIR / "flye"
        self.FLYE_ASSEMBLY = self.FLYE_DIR / "assembly.fasta"
        self.PURGED_ASSEMBLY_FLYE = self.ASSEMBLY_DIR / "flye_purged" / "purged.fa"

        # Phase 2 — Mode 4 (NextDenovo)
        self.NEXTDENOVO_DIR = self.ASSEMBLY_DIR / "nextdenovo"
        self.NEXTDENOVO_CONFIG = self.NEXTDENOVO_DIR / "run.cfg"
        self.NEXTDENOVO_ASSEMBLY = (
            self.NEXTDENOVO_DIR / "03.ctg_graph" / "nd.asm.fasta"
        )
        self.PURGED_ASSEMBLY_NEXTDENOVO = (
            self.ASSEMBLY_DIR / "nextdenovo_purged" / "purged.fa"
        )

        # Phase 2 — comparison/selection
        self.BEST_ASSEMBLY = self.ASSEMBLY_DIR / "best_assembly.fa"

        # Phase 3 / 4 / 6
        self.POLISHED_ASSEMBLY = self.POLISH_DIR / "genome.nextpolish.fasta"
        self.CLEAN_ASSEMBLY = self.DECONTAM_DIR / "clean_assembly.fa"
        self.BUSCO_DIR = self.QC_DIR / "busco_results"
        self.QUAST_DIR = self.QC_DIR / "quast_output"
        self.MERQURY_DIR = self.QC_DIR / "merqury_output"

        # Phase 7
        self.REPEAT_DIR = self.ANNOTATION_DIR / "repeats"
        self.BRAKER_DIR = self.ANNOTATION_DIR / "braker"
        self.FUNCTIONAL_DIR = self.ANNOTATION_DIR / "functional"

        # Final outputs and tracking files
        self.FINAL_ASSEMBLY = self.PROJECT_DIR / "final_assembly.fa"
        self.STATUS_FILE = self.PROJECT_DIR / "pipeline_status.json"
        self.RESULTS_FILE = self.PROJECT_DIR / "RESULTS.md"
        self.COMPARISON_DIR = self.ASSEMBLY_DIR / "comparison"

    def _resolve(self, p):
        if p is None:
            return None
        path = Path(p).expanduser()
        if path.is_absolute():
            return path
        return (self.PROJECT_DIR / path).resolve()
