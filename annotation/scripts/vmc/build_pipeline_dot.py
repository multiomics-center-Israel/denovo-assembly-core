#!/usr/bin/env python3
"""Emit a Graphviz .dot of the full S. cameroni pipeline + a methods markdown.
Rendered to PNG by the driver via `dot -Tpng`."""
import os
PROJ = "/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly"
DOT = os.path.join(PROJ, "annotation/figures/pipeline_diagram.dot")
MD = os.path.join(PROJ, "report/methods_explained.md")

dot = r'''
digraph pipeline {
  rankdir=TB; fontname="Helvetica"; nodesep=0.35; ranksep=0.55;
  node [shape=box style="rounded,filled" fontname="Helvetica" fontsize=11];
  edge [fontname="Helvetica" fontsize=9 color="#555555"];

  subgraph cluster_data {
    label="Raw data"; style="rounded,filled"; color="#eef3fb";
    hifi  [label="PacBio Revio HiFi\n~12x" fillcolor="#cfe2f3"];
    ill   [label="Illumina NovaSeq X\n~80x" fillcolor="#cfe2f3"];
    rna   [label="Public RNA-seq\nSRR1502981 (whole body)" fillcolor="#cfe2f3"];
    tsa   [label="TSA transcriptome\nGBVV01" fillcolor="#cfe2f3"];
    nas   [label="Nasonia vitripennis\nproteome + genome" fillcolor="#d9ead3"];
  }

  subgraph cluster_asm {
    label="1. Assembly (quad-mode)"; style="rounded,filled"; color="#fff2cc";
    hifiasm [label="hifiasm" fillcolor="#ffe599"];
    masurca [label="MaSuRCA" fillcolor="#ffe599"];
    flye    [label="Flye" fillcolor="#ffe599"];
    nextd   [label="NextDenovo" fillcolor="#ffe599"];
    pick    [label="Best assembly\n(hifiasm chosen)" shape=box fillcolor="#f6b26b"];
  }

  subgraph cluster_qc {
    label="2. QC + decontamination"; style="rounded,filled"; color="#f4cccc";
    polish [label="Polish" fillcolor="#ea9999"];
    decon  [label="Kraken2 + Kaiju(nr)\nalignment + insect rescue\n+ Wolbachia bin" fillcolor="#ea9999"];
    final  [label="final_assembly.fa\n4,980 contigs / 650.9 Mb\nN50 273 kb · BUSCO 89.3%" shape=box fillcolor="#e06666"];
  }

  subgraph cluster_mask {
    label="3. Repeat modelling"; style="rounded,filled"; color="#d9d2e9";
    rmod [label="RepeatModeler" fillcolor="#b4a7d6"];
    rmsk [label="RepeatMasker\n42.98% masked" fillcolor="#b4a7d6"];
  }

  subgraph cluster_ann {
    label="4. Gene prediction & annotation"; style="rounded,filled"; color="#d0e0e3";
    hisat [label="HISAT2 (RNA-seq BAM)\nminimap2 (TSA)" fillcolor="#a2c4c9"];
    braker [label="BRAKER3\nGeneMark-ETP + AUGUSTUS\n9,761 genes" fillcolor="#a2c4c9"];
    rescue [label="TSEBRA single-exon rescue\n11,856 genes" fillcolor="#a2c4c9"];
    tib    [label="Tiberius (ab initio, GPU)\n20,388 genes" fillcolor="#a2c4c9"];
    pasa   [label="PASA\ntranscript alignment assemblies" fillcolor="#a2c4c9"];
    evm    [label="EvidenceModeler\nconsensus" fillcolor="#76a5af"];
    evmpasa [label="EVM + PASA update\n12,580 genes  (CANONICAL)" shape=box fillcolor="#45818e" fontcolor=white];
    funan  [label="funannotate annotate\nPFAM/MEROPS/dbCAN/UniProt/GO" fillcolor="#76a5af"];
  }

  subgraph cluster_down {
    label="5. Downstream / targets"; style="rounded,filled"; color="#fce5cd";
    busco  [label="BUSCO across stages\nvs Nasonia" fillcolor="#f9cb9c"];
    venom  [label="Venom-gland catalogue\nminiprot/DIAMOND vs venom ref" fillcolor="#f9cb9c"];
    mito   [label="Mitochondrial contig\ntblastn mito proteins" fillcolor="#f9cb9c"];
  }

  hifi -> hifiasm; hifi -> flye; hifi -> nextd; ill -> masurca; ill -> polish;
  hifiasm -> pick; masurca -> pick; flye -> pick; nextd -> pick;
  pick -> polish -> decon -> final;
  final -> rmod -> rmsk;
  rmsk -> braker; rna -> hisat -> braker; tsa -> pasa; nas -> braker;
  braker -> rescue; rmsk -> tib;
  braker -> evm; rescue -> evm; pasa -> evm; nas -> evm;
  evm -> evmpasa; pasa -> evmpasa; evmpasa -> funan;
  funan -> busco; nas -> busco; tib -> busco;
  funan -> venom; nas -> venom; final -> mito;
}
'''
with open(DOT, "w") as f:
    f.write(dot)
print("wrote", DOT)

md = """# S. cameroni genome — methods explained (for the lab)

## 1. Data
- **PacBio Revio HiFi (~12x)** — primary long reads for contiguity. Low coverage is the main limiter.
- **Illumina NovaSeq X (~80x)** — short reads for polishing and for the MaSuRCA hybrid assembly.
- **Public RNA-seq SRR1502981** — one whole-body library (PRJNA252176), used as transcript evidence. *Not* venom gland.
- **TSA GBVV01** — an assembled S. cameroni transcriptome, used as transcript evidence in PASA.
- **Nasonia vitripennis** proteome + genome — the closest well-annotated relative; protein homology evidence and the comparison yardstick.

## 2. Assembly (quad-mode)
Four assemblers were run and compared: **hifiasm, MaSuRCA, Flye, NextDenovo**. hifiasm gave the best contiguity/BUSCO trade-off and was adopted.

## 3. QC & decontamination
Polishing, then a two-layer decontamination (**Kraken2 + Kaiju against nr**) combined with alignment-based screening and an *insect-rescue* step so true insect contigs are not discarded. *Wolbachia* contigs were split into a separate endosymbiont bin. Result: **final_assembly.fa — 4,980 contigs, 650.9 Mb, N50 273 kb, genome BUSCO 89.3%**.

## 4. Repeats
**RepeatModeler** built a de-novo library; **RepeatMasker** soft-masked **42.98%** of the genome before gene prediction.

## 5. Gene prediction & annotation
- RNA-seq aligned with **HISAT2**; TSA with **minimap2**.
- **BRAKER3** (GeneMark-ETP + AUGUSTUS, with RNA-seq + Nasonia protein hints) → 9,761 genes.
- **TSEBRA single-exon rescue** (RNA-seq/homology-supported) → 11,856 genes ("rescued").
- **Tiberius** ab-initio (deep-learning, GPU on athena) → 20,388 genes — an independent benchmark.
- **PASA** assembled transcript alignments for UTRs/isoforms.
- **EvidenceModeler** combined BRAKER + rescued + PASA + Nasonia homology into a consensus; **PASA update** restored UTRs/isoforms → **canonical 12,580-gene set**.
- **funannotate annotate** added PFAM, MEROPS, dbCAN (CAZymes), UniProt names, GO.

## 6. Downstream / project targets
- **BUSCO** computed at every stage and against Nasonia for an apples-to-apples quality comparison.
- **Venom-gland catalogue** — homology search (miniprot/DIAMOND) against a Nasonia/parasitoid venom reference, because no venom-gland RNA-seq exists yet.
- **Mitochondrial contig** — identified by tblastn of mitochondrial proteins against the assembly.
"""
with open(MD, "w") as f:
    f.write(md)
print("wrote", MD)
