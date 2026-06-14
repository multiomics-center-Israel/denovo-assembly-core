# Coelastrella sp. WT-2 — Pipeline Scripts (29 steps)

Numbered by execution order. Ready for conversion to neatseq-flow.

## Pipeline stages

| # | Stage | Scripts |
|---|-------|---------|
| 1 | Pre-processing (basecalling, trimming) | 01-02 |
| 2 | Read QC + contamination screening | 03-06 |
| 3 | Genome size estimation | 07 |
| 4 | De novo assembly + comparison | 08-10 |
| 5 | Polishing round 1 (ONT + Illumina) | 11-14 |
| 6 | Decontamination (BlobTools + BLAST) | 15-18 |
| 7 | Haplotig purging + polish round 2 | 19-25 |
| 8 | Final decontamination (Tiara + FCS-GX) | 26-29 |

## Final outputs

- **Assembly**: `09.polypolish/Coelastrella_FINAL.fa`
  - 28 contigs, 105.04 Mb, N50 6.12 Mb
  - BUSCO C:96.0% [S:89.5%, D:6.5%]
  - FCS-GX clean (0 contamination flags)

- **Documentation**: `00.PROJECT_DOC/01.assembly_workflow_michal.docx`

## Dependencies (conda envs)

| Stage | Env path |
|-------|----------|
| QC, assembly, polishing | `/gpfs0/system/conda/miniconda2/envs/Omics_QC` |
| seqkit (utility) | `/gpfs0/system/conda/miniconda2/envs/Mamba/envs/seqkit` |
| btk (BlobTools) | `/gpfs0/system/conda/miniconda2/envs/btk` |
| purge_dups | `/gpfs0/system/conda/miniconda2/envs/Mamba/envs/purge_dups` |
| nextpolish (Python 3.10!) | `/gpfs0/system/conda/miniconda2/envs/Mamba/envs/nextpolish` |
| polypolish + pypolca | `/gpfs0/system/conda/miniconda2/envs/Mamba/envs/polypolish` |
| tiara (Python 3.9 + pip) | `/gpfs0/system/conda/miniconda2/envs/Mamba/envs/tiara` |
| fcsgx (bioconda) | `/gpfs0/system/conda/miniconda2/envs/Mamba/envs/fcsgx` |

## Notes for neatseq-flow conversion

- Scripts 03 (ONT Kaiju) is ALREADY a neatseq-flow workflow — use it as a reference.
- Scripts 21 (NextPolish) requires Python 3.10 — pin in conda env definition.
- Scripts 28-29 (FCS-GX) require ~465 GB DB downloaded once, then run takes 1-3 hours.
- All SGE submissions use `bioinfo.q`, varying threads (8-32) and memory.

## Pipeline DAG

01 (ONT basecall) ──┐
02 (Illumina QC)  ──┤
▼
03-06 (read contamination checks)
│
▼
07 (GenomeScope2)
│
▼
08 (Hifiasm) ──┬──► 10 (eval) ──► 12 (Medaka) ──► 13 (Pilon)
09 (Flye)    ──┘                                    │
▼
15-16 (BlobTools)
│
▼
18 (BLAST vs Boris refs)
│
▼
19 (purge_dups + rescue)
│
▼
21 (NextPolish ×2)
│
▼
24 (Polypolish + Pypolca)
│
▼
26 (Tiara) ──► 29 (FCS-GX)
│
▼
Coelastrella_FINAL.fa
