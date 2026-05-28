#!/usr/bin/env python3
"""Build a unified gffutils SQLite database from all available annotation GFFs.

Inputs (merged into one DB):
  - annotation/repeats/final_assembly.fa.out.gff      (RepeatMasker)
  - annotation/braker/braker.gff3                     (BRAKER3 — Phase 7.4)
  - BUSCO derived BED converted to GFF on the fly

Output: webapp/build/data/agent/gff.sqlite
"""
import os
from pathlib import Path

import gffutils

PROJECT_DIR = Path("/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly")
OUT = PROJECT_DIR / "webapp" / "build" / "data" / "agent" / "gff.sqlite"
OUT.parent.mkdir(parents=True, exist_ok=True)

INPUTS = [
    PROJECT_DIR / "annotation" / "repeats" / "final_assembly.fa.out.gff",
    PROJECT_DIR / "annotation" / "braker" / "braker.gff3",
]


def main() -> None:
    present = [p for p in INPUTS if p.exists()]
    if not present:
        raise SystemExit("No GFF inputs found.")

    if OUT.exists():
        OUT.unlink()

    db = gffutils.create_db(
        str(present[0]),
        dbfn=str(OUT),
        force=True,
        keep_order=False,
        merge_strategy="create_unique",
        sort_attribute_values=False,
        disable_infer_genes=True,
        disable_infer_transcripts=True,
    )
    print(f"Created DB with {present[0].name}")

    for extra in present[1:]:
        db.update(str(extra), make_backup=False, merge_strategy="create_unique")
        print(f"Merged {extra.name}")

    print(f"Done: {OUT}")


if __name__ == "__main__":
    main()
