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

## Annotation pipeline (structural + functional)

Beyond the BRAKER prediction in phase 7.4, the project carries a full
evidence-based annotation pipeline driven by standalone scripts under `bin/`
(orchestration) with reusable Python/shell helpers under `annotation/scripts/`.
The canonical gene set is produced by combining multiple predictors via
EVidenceModeler, then refining with PASA and functional annotation:

```
RNA-Seq + protein evidence
        │
        ▼
  EVM consensus  ──►  PASA UTR/isoform update  ──►  funannotate functional
 (bin/run_evm_consensus.sh)   (annotation/scripts/run_pasa.sh)   annotation
        │                                              │   (canonical set,
        │                                              │    ~12,580 genes)
        │                                              ▼
        │                              optional: Tiberius ab-initio graft
        │                              (bin/merge_tiberius_rescue.sh —
        │                               add-only, BUSCO/homology-gated)
        ▼
  venom / mito comparison + cross-stage BUSCO + slides
  (bin/run_venom_mito_compare.sh)
```

### Driver scripts (`bin/`)

| Script | What it does |
|---|---|
| `run_evm_pasa_funannotate.sh` | EVM consensus → PASA UTR/isoform update → funannotate functional annotation. Produces the **canonical ~12,580-gene set**. |
| `merge_tiberius_rescue.sh` | Add-only, evidence-gated graft of Tiberius ab-initio genes into the EVM+PASA canonical set. Gate = BUSCO rescue OR Nasonia homology, dup-protected. Idempotent. |
| `run_venom_mito_compare.sh` | Venom/mito comparison, mitochondrial-contig ID, cross-stage BUSCO vs *Nasonia*, pipeline diagram + results slides. |
| `run_evm_consensus.sh` | Standalone EVidenceModeler consensus re-run. |
| `run_funannotate.sh` | Standalone funannotate functional-annotation stage. |
| `run_model_refinement.sh` | Gene-model refinement / rescue scoring. |
| `run_reprediction.sh` | Re-run gene prediction on a revised genome. |
| `run_aed_refresh.sh` | Recompute cross-stage AED summary (folds the EVM stage in). |
| `run_finish_annotation.sh` | One-shot detached driver: BRAKER3 (7.4) ‖ funannotate (7.5) + figures (7.6) + BigWig tracks (7.7) + report. |
| `run_resume_annotation.sh` | Idempotent resume of remaining annotation steps (RNA-Seq acquire/trim → align 7.3 → BRAKER 7.4 → functional 7.5). |

### Helpers (`annotation/scripts/`)

- `analysis_suite.py` — post-annotation analysis utilities.
- `make_figures.py` — annotation/QC figures.
- `compare_gene_structure.py`, `refine_rescue.py`, `refine_score.py` — gene-model
  comparison and rescue scoring (also mirrored in `bin/`).
- `run_pasa.sh` — PASA alignment + annotation-compare.
- `run_ncrna.sh` — ncRNA annotation (Infernal/tRNAscan).
- `run_repeats_track.sh` — repeat track build.
- `run_structure_compare.sh` — gene-structure comparison vs *Nasonia*.
- `vmc/` — venom/mito/comparison package: `build_comparison.py`,
  `venom_summary.py`, `mito_summary.py`, `build_pipeline_dot.py`,
  `build_slides.py`, `merge_tib.py`, `normalize_tib_gtf.py`.

### Conda envs

The annotation drivers expect three conda envs (override the names inside each
driver if yours differ):

- `genome_assembly` — EVM, PASA, BRAKER, BUSCO, diamond, bedtools, seqkit,
  samtools, miniprot, mafft (the main toolchain).
- `funannotate` — funannotate + its DB (`FUNANNOTATE_DB`), plus `graphviz` (dot)
  for the pipeline diagram.
- `evm` — optional dedicated EVidenceModeler env where used.

### Key inputs / outputs

- **Inputs:** assembly FASTA (`final_assembly.fa` and a ≤16-char-contig copy for
  funannotate/tbl2asn), EVM consensus GFF3, a loaded PASA SQLite (reuses existing
  transcript alignments), eggNOG annotations, a *Nasonia* protein DIAMOND DB, and
  (for the graft) Tiberius GTF/AA + BUSCO full tables.
- **Outputs:** PASA-updated EVM models, funannotate `annotate_results/` (canonical
  proteins + GFF3), the merged EVM+Tiberius set, BUSCO summaries, and the
  comparison slides/diagram.

> **Note:** these drivers are project-specific and hardcode the
> `PROJECT=/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly` root (and a few
> external reference paths under `/mnt/data/genomes/`). They are committed here as
> the version-controlled source of truth; adapt the `PROJECT=` / env / reference
> lines at the top of each driver before reuse on another project.

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

## Alternative entry point: NeatSeq-Flow

The same phases are also available as a [NeatSeq-Flow](https://github.com/bioinfo-core-BGU/neatseq_flow)
workflow that emits one qsub job per step under SGE. Use it when you want each
phase scheduled independently on the cluster instead of the local nohup wrapper.

```bash
# 1. Copy the template + sample file
cp config/neatseq_flow/genome_assembly_workflow.template.yaml /path/to/myproject/workflow.yaml
cp config/neatseq_flow/sample_file.template.nsf               /path/to/myproject/sample_file.nsf

# 2. Edit the Vars: block in workflow.yaml (project.dir, repo.dir, input.*,
#    kraken2.db, rnaseq.*) and the sample paths in sample_file.nsf.

# 3. Generate scripts and submit
cd /path/to/myproject
neatseq_flow.py -s sample_file.nsf -p workflow.yaml -d $PWD/scripts
bash scripts/00.workflow.commands.sh
```

Output paths in the workflow mirror `denovo_assembly_core.config.Config`, so a
project can be started with NeatSeq-Flow and resumed with `bin/run_pipeline.sh`
(or vice versa). A worked, fully-populated copy lives at
`examples/spalangia_cameroni/neatseq_flow/`.

The workflow shells out to `bin/filter_contigs_by_lineage.py` for the Phase 4
contig-lineage filter; point `Vars.repo.dir` at this repo's checkout.

## Layout

```
denovo-assembly-core/
├── denovo_assembly_core/                          # Python package (pipeline, config, notify)
├── bin/
│   ├── run_pipeline.sh                            # nohup wrapper / CLI
│   ├── filter_contigs_by_lineage.py               # Kraken2 nodes.dmp lineage walker (Phase 4)
│   ├── sync_scripts.sh                            # refresh tracked scripts from the working dir (see below)
│   └── run_*.sh / merge_tiberius_rescue.sh        # annotation drivers (EVM→PASA→funannotate, graft, compare)
├── annotation/scripts/                            # reusable annotation helpers
│   ├── busco_rescue/                               # BUSCO-completion graft + ncRNA merge helpers
│   └── vmc/                                        # venom/mito/comparison package (+ Tiberius graft helpers)
├── cluster/                                        # HPC job scripts (athena SLURM / zeus PBS): tiberius_athena*
├── experiments/                                    # one-off decision-probe drivers (provenance, not standing stages)
├── config/
│   ├── project.template.yaml                      # for bin/run_pipeline.sh
│   └── neatseq_flow/
│       ├── genome_assembly_workflow.template.yaml # for NeatSeq-Flow
│       └── sample_file.template.nsf
└── examples/spalangia_cameroni/                   # Worked example: parasitoid wasp run
    ├── project.yaml                               # for bin/run_pipeline.sh
    └── neatseq_flow/                              # same run, NeatSeq-Flow style
        ├── genome_assembly_workflow.yaml
        └── sample_file.nsf
```

## Keeping the repo in sync (source of truth)

This repo is the **canonical source of truth** for all driver/runner scripts. Scripts are developed
live in the project working dir, then synced back here and committed. Conventions:

- **Shell drivers keep their hardcoded `PROJECT=` header** (committed as the reference version;
  adapt the `PROJECT=` / ref lines before reuse on another project).
- **Layout mirrors the working dir** — annotation helpers under `annotation/scripts/{,vmc,busco_rescue}`,
  standing drivers under `bin/`, HPC job scripts under `cluster/`, one-off decision probes under
  `experiments/`.
- **`bin/sync_scripts.sh`** refreshes every *already-tracked* script from the working dir (matched by
  basename; the two working-dir shims `run_pipeline.sh`/`run_annotation.sh` are skipped). Run it, review
  `git status`/`git diff`, then commit. A new script is placed + `git add`-ed once (classified into the
  right dir), and stays in sync thereafter.
- **No data is ever committed** — `.gitignore` excludes all sequence/alignment/index formats
  (`*.fa/.gff3/.gtf/.bam/.cm/.sqlite/.bw/…`); only code lives here.

## License

TBD.
