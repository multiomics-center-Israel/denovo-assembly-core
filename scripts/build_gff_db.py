#!/usr/bin/env python3
"""Build a gffutils SQLite database the agent's gff_query tool reads.

Env-driven so it runs both on the lab host and on the local laptop build:
  GFF_INPUTS  colon-separated GFF/GFF3 paths to merge (first creates, rest update)
  GFF_DB_OUT  output SQLite path

Defaults target the local webapp layout: the funannotate annotation GFF3 staged
under tracks/src/, written to data/agent/gff.sqlite (mounted read-only into the
agent container at /data/agent/gff.sqlite via GFF_DB_PATH).
"""
import os
from pathlib import Path

import gffutils

REPO = Path(__file__).resolve().parent.parent

INPUTS = [Path(p) for p in os.environ.get(
    "GFF_INPUTS",
    str(REPO / "tracks" / "src" / "Spalangia_cameroni.gff3"),
).split(":") if p]

OUT = Path(os.environ.get("GFF_DB_OUT", str(REPO / "data" / "agent" / "gff.sqlite")))


def main() -> None:
    present = [p for p in INPUTS if p.exists()]
    if not present:
        raise SystemExit(f"No GFF inputs found among: {INPUTS}")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    if OUT.exists():
        OUT.unlink()

    # The funannotate GFF3 carries explicit gene/mRNA/exon/CDS with ID+Parent,
    # so inference is unnecessary (and faster off).
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
    print(f"Created DB from {present[0].name}")

    for extra in present[1:]:
        db.update(str(extra), make_backup=False, merge_strategy="create_unique")
        print(f"Merged {extra.name}")

    for ft in ("gene", "mRNA", "exon", "CDS"):
        try:
            print(f"  {ft}: {db.count_features_of_type(ft)}")
        except Exception:
            pass
    print(f"Done: {OUT}")


if __name__ == "__main__":
    main()
