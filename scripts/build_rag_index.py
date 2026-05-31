#!/usr/bin/env python3
"""Build a BM25 retrieval index over project text artifacts.

Defaults match the lab-host (`bi-delllinux`) layout. Override via env for
other contexts (e.g. the FASTA-only laptop demo):

  PROJECT_DIR      project root (default: lab-host wasp_genome_assembly tree)
  RAG_OUT_DIR      output directory for chunks.jsonl
  RAG_SOURCES      colon-separated paths relative to PROJECT_DIR; if unset,
                   uses the lab-host source list below
"""
import json
import os
import re
from pathlib import Path

PROJECT_DIR = Path(os.environ.get(
    "PROJECT_DIR", "/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly"))
OUT_DIR = Path(os.environ.get(
    "RAG_OUT_DIR", str(PROJECT_DIR / "webapp" / "build" / "data" / "agent" / "rag")))
OUT_DIR.mkdir(parents=True, exist_ok=True)

_DEFAULT_SOURCES = [
    "RESULTS.md",
    "PLAN_decontam_v3.md",
    "PIPELINE_RESUME_20260420.md",
    "annotation/repeats/final_assembly.fa.tbl",
    "annotation/repeats/spalangia_db-rmod.log",
    "pipeline_status.json",
]
_src_env = os.environ.get("RAG_SOURCES")
SOURCES = [
    PROJECT_DIR / s
    for s in (_src_env.split(":") if _src_env else _DEFAULT_SOURCES)
]

CHUNK_TOKENS = 350
OVERLAP = 50


def chunk_text(text: str) -> list[str]:
    words = re.split(r"\s+", text.strip())
    chunks, i = [], 0
    while i < len(words):
        chunks.append(" ".join(words[i:i + CHUNK_TOKENS]))
        if i + CHUNK_TOKENS >= len(words):
            break
        i += CHUNK_TOKENS - OVERLAP
    return chunks


def main() -> None:
    out_path = OUT_DIR / "chunks.jsonl"
    written = 0
    with out_path.open("w") as fh:
        for src in SOURCES:
            if not src.exists():
                print(f"  SKIP (missing): {src}")
                continue
            try:
                text = src.read_text(errors="replace")
            except Exception as e:
                print(f"  SKIP ({e}): {src}")
                continue
            for chunk in chunk_text(text):
                fh.write(json.dumps({"source": str(src.relative_to(PROJECT_DIR)), "text": chunk}) + "\n")
                written += 1
            print(f"  OK: {src} ({len(text)} chars)")
    print(f"Wrote {written} chunks to {out_path}")


if __name__ == "__main__":
    main()
