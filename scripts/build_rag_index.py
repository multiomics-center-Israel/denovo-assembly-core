#!/usr/bin/env python3
"""Build a BM25 retrieval index over project text artifacts.

Output: webapp/build/data/agent/rag/chunks.jsonl  (one JSON per chunk)
"""
import json
import re
from pathlib import Path

PROJECT_DIR = Path("/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly")
OUT_DIR = PROJECT_DIR / "webapp" / "build" / "data" / "agent" / "rag"
OUT_DIR.mkdir(parents=True, exist_ok=True)

SOURCES = [
    PROJECT_DIR / "RESULTS.md",
    PROJECT_DIR / "PLAN_decontam_v3.md",
    PROJECT_DIR / "PIPELINE_RESUME_20260420.md",
    PROJECT_DIR / "annotation" / "repeats" / "final_assembly.fa.tbl",
    PROJECT_DIR / "annotation" / "repeats" / "spalangia_db-rmod.log",
    PROJECT_DIR / "pipeline_status.json",
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
