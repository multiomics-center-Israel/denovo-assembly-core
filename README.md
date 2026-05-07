# denovo-assembly-core

Reproducible long-read genome assembly + annotation pipeline driven by a single
`project.yaml`. Built around PacBio HiFi (with optional Illumina polishing) and
covers QC, multi-assembler comparison, polishing, decontamination, and
annotation.

## Phases

| Phase | What it does |
|------:|---|
| 1.1   | PacBio HiFi QC (NanoPlot) |
| 1.2   | Illumina QC (cutadapt + fastp) |
| 1.2b  | Read-level decontamination (Kraken2 PlusPF-8) |
| 1.3   | K-mer survey (Jellyfish + GenomeScope2) |
| 2.1   | hifiasm (HiFi-only) |
| 2.1b  | MaSuRCA (HiFi + Illumina hybrid) |
| 2.1c  | Flye (HiFi) |
| 2.1d  | NextDenovo (HiFi) |
| 2.2   | Haplotig purging (purge_dups) on each assembly |
| 2.3   | Cross-assembly comparison (QUAST, BUSCO, MUMmer) → pick best |
| 3     | Illumina polishing (NextPolish) |
| 4     | Contig-level decontamination (Kraken2) |
| 6     | Final QC: BUSCO + QUAST + Merqury |
| 7.1   | Repeat annotation (RepeatModeler2 + RepeatMasker) |
| 7.2   | Public RNA-Seq download (SRA / TSA) |
| 7.3   | RNA-Seq alignment (HISAT2 + minimap2 splice) |
| 7.4   | Gene prediction (BRAKER) |
| 7.5   | Functional annotation (eggNOG-mapper) |

Phases 2.1–2.1d are fault-tolerant: an assembler that fails is logged and the
pipeline continues with the others.

## Requirements

- A conda env with the assembly toolchain installed. The default name is
  `genome_assembly`; override via `conda.env` in `project.yaml`. PyYAML is the
  only Python dependency the pipeline itself adds.
- `bash`, `python3` (3.10+), `conda` on PATH.

## Quickstart

```bash
git clone https://github.com/multiomics-center-Israel/denovo-assembly-core.git
cd denovo-assembly-core

# Set up a project directory
mkdir -p /path/to/myproject
cp config/project.template.yaml /path/to/myproject/project.yaml
# Edit project.dir, species, inputs, etc.

# Run
bin/run_pipeline.sh --project-dir /path/to/myproject all
```

`run_pipeline.sh` runs in the background under `nohup`, emails on
completion/failure, and resumes correctly if interrupted (completed phases are
skipped via `pipeline_status.json`).

## Commands

```bash
bin/run_pipeline.sh --project-dir DIR <command>

  all              Run every phase
  <phase>          Run specific phase(s): '2', '2-3', '1.3'
  from <phase>     Run from <phase> to the end
  resume           Continue from first incomplete phase
  status           Show step status
  list             List available phases
  tail             Live-follow the log
  report           Regenerate HTML / RESULTS.md / PPTX
  stop             Stop the running pipeline
  logs             Print recent log lines
```

If `--project-dir` is omitted it defaults to `$PWD`. If `--config` is omitted it
defaults to `<project-dir>/project.yaml` (or `$PROJECT_CONFIG`).

## Configuration

See `config/project.template.yaml` for the full schema. The required fields:

```yaml
project:
  dir: /abs/path/to/project
species:
  display_name: "Genus species"
  short_name:   "G. species"
  slug:         genome
inputs:
  pacbio_reads: reads/sample.fastq
  illumina_r1:  reads/sample_R1.fastq.gz
  illumina_r2:  reads/sample_R2.fastq.gz
```

Relative paths under `inputs:` and `kraken2.db` are resolved against
`project.dir`.

## Layout

```
denovo-assembly-core/
├── denovo_assembly_core/    # Python package (pipeline, config, notify)
├── bin/run_pipeline.sh      # nohup wrapper / CLI
├── config/project.template.yaml
└── examples/spalangia_cameroni/   # Worked example: parasitoid wasp run
```

## License

TBD.
