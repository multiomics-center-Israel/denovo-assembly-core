#!/usr/bin/env python3
"""Emit a JBrowse 2 config.json for the web deploy.

ALL external URLs come from env so nothing host-specific is baked in:
  TRACK_BASE   public base URL for genome + track files (e.g. Supabase Storage
               public bucket URL, no trailing slash). Required.
  AGENT_BASE   public base URL of the agent service (for the live blast_hits
               track). Optional; if unset the blast_hits track is omitted.
  ASSEMBLY_NAME  default 'spalangia_cameroni'
  CONFIG_OUT     output path (default build/jbrowse-config/config.json)

Run after prep_web_bundle.sh and after the files are uploaded to TRACK_BASE.
"""
import json
import os
from pathlib import Path

BASE = os.environ["TRACK_BASE"].rstrip("/")
AGENT = os.environ.get("AGENT_BASE", "").rstrip("/")
ASM = os.environ.get("ASSEMBLY_NAME", "spalangia_cameroni")
OUT = Path(os.environ.get("CONFIG_OUT", "build/jbrowse-config/config.json"))


def uri(name):
    return {"uri": f"{BASE}/{name}"}


def gff3_tabix(name):
    return {"type": "Gff3TabixAdapter",
            "gffGzLocation": uri(name),
            "index": {"location": uri(name + ".tbi"), "indexType": "TBI"}}


def gtf_tabix(name):
    return {"type": "GtfTabixAdapter",
            "gtfGzLocation": uri(name),
            "index": {"location": uri(name + ".tbi"), "indexType": "TBI"}}


def bed_tabix(name):
    return {"type": "BedTabixAdapter",
            "bedGzLocation": uri(name),
            "index": {"location": uri(name + ".tbi"), "indexType": "TBI"}}


def bigwig(name):
    return {"type": "BigWigAdapter", "bigWigLocation": uri(name)}


def feat(track_id, name, category, adapter, ttype="FeatureTrack"):
    return {"type": ttype, "trackId": track_id, "name": name,
            "category": [category], "assemblyNames": [ASM], "adapter": adapter}


assembly = {
    "name": ASM,
    "sequence": {
        "type": "ReferenceSequenceTrack",
        "trackId": f"{ASM}-ref",
        "adapter": {
            "type": "BgzipFastaAdapter",
            "fastaLocation": uri("final_assembly.fa.gz"),
            "faiLocation": uri("final_assembly.fa.gz.fai"),
            "gziLocation": uri("final_assembly.fa.gz.gzi"),
        },
    },
}

tracks = [
    feat("spalangia_genes", "Gene models (funannotate v2)", "Annotation",
         gff3_tabix("genes.gff3.gz")),
    feat("stringtie", "RNA-Seq transcripts (StringTie)", "Annotation",
         gtf_tabix("stringtie_merged.gtf.gz")),
    feat("repeats", "Repeats (RepeatMasker)", "Annotation",
         bed_tabix("repeats.bed.gz")),
    feat("ncRNA", "ncRNA (tRNAscan)", "Annotation",
         bed_tabix("ncRNA.sorted.bed.gz")),
    feat("rnaseq_coverage", "RNA-Seq coverage", "Coverage",
         bigwig("rnaseq_coverage.bw"), ttype="QuantitativeTrack"),
    feat("rnaseq_coverage_rp10m", "RNA-Seq coverage (RP10M)", "Coverage",
         bigwig("rnaseq_coverage.rp10m.bw"), ttype="QuantitativeTrack"),
    feat("tsa_coverage", "TSA coverage", "Coverage",
         bigwig("tsa_coverage.bw"), ttype="QuantitativeTrack"),
    feat("nvit_tblastn", "Nvit proteins (close homologs)", "Homology",
         gff3_tabix("nvit_tblastn.gff.gz")),
    feat("nvit_orthologs", "Nvit proteins (strict orthologs)", "Homology",
         gff3_tabix("nvit_orthologs.gff.gz")),
]

# Live BLAST-hits track served by the agent (plain GFF3, overwritten per upload)
if AGENT:
    tracks.append(feat(
        "blast_hits", "BLAST hits (latest local upload)", "BLAST",
        {"type": "Gff3Adapter",
         "gffLocation": {"uri": f"{AGENT}/blast-results/latest.gff3"}}))

config = {
    "assemblies": [assembly],
    "tracks": tracks,
    "defaultSession": {"name": "Spalangia cameroni"},
    "configuration": {},
}

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(json.dumps(config, indent=2))
print(f"Wrote {OUT} ({len(tracks)} tracks, TRACK_BASE={BASE}, AGENT_BASE={AGENT or '(none)'})")
