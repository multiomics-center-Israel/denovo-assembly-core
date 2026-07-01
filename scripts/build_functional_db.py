#!/usr/bin/env python3
"""Build a compact functional-annotation SQLite the agent's functional_lookup tool reads.

Two tables, both keyed by transcript id:
  annotations  - funannotate combined table, sequence columns dropped
  eggnog       - eggNOG-mapper output (KEGG / GO / description)

Env:
  FUNANNOTATE_TSV  funannotate_annotations.txt
  EGGNOG_TSV       eggNOG_annotations.txt (## comment lines skipped)
  FUNC_DB_OUT      output sqlite path
"""
import csv
import os
import sqlite3
import sys
from pathlib import Path

csv.field_size_limit(sys.maxsize)

FUNANNOTATE = os.environ["FUNANNOTATE_TSV"]
EGGNOG = os.environ["EGGNOG_TSV"]
OUT = Path(os.environ["FUNC_DB_OUT"])

# funannotate columns to keep (drop bulky sequence cols 23-26)
KEEP = [
    "GeneID", "TranscriptID", "Feature", "Contig", "Start", "Stop", "Strand",
    "Name", "Product", "EC_number", "BUSCO", "PFAM", "InterPro", "EggNog",
    "COG", "GO_Terms", "Secreted", "Membrane", "Protease", "CAZyme", "Notes",
]


def col(name: str) -> str:
    return name.replace(" ", "_").replace("/", "_")


def main() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    if OUT.exists():
        OUT.unlink()
    con = sqlite3.connect(OUT)
    cur = con.cursor()

    # ---- annotations (funannotate) ----
    cur.execute(f"CREATE TABLE annotations ({', '.join(c + ' TEXT' for c in KEEP)})")
    with open(FUNANNOTATE, newline="") as fh:
        r = csv.reader(fh, delimiter="\t")
        header = [col(h) for h in next(r)]
        idx = {h: i for i, h in enumerate(header)}
        keep_idx = [idx[c] for c in KEEP]
        ins = f"INSERT INTO annotations VALUES ({','.join('?' * len(KEEP))})"
        n = 0
        for row in r:
            cur.execute(ins, [row[i] if i < len(row) else "" for i in keep_idx])
            n += 1
    cur.execute("CREATE INDEX ix_ann_tx ON annotations(TranscriptID)")
    cur.execute("CREATE INDEX ix_ann_gene ON annotations(GeneID)")
    print(f"annotations: {n} rows")

    # ---- eggnog ----
    with open(EGGNOG) as fh:
        lines = [ln for ln in fh if not ln.startswith("##")]
    rr = csv.reader(lines, delimiter="\t")
    eheader = [col(h.lstrip("#")) for h in next(rr)]
    cur.execute(f"CREATE TABLE eggnog ({', '.join(h + ' TEXT' for h in eheader)})")
    eins = f"INSERT INTO eggnog VALUES ({','.join('?' * len(eheader))})"
    m = 0
    for row in rr:
        if not row:
            continue
        cur.execute(eins, [row[i] if i < len(row) else "" for i in range(len(eheader))])
        m += 1
    cur.execute(f"CREATE INDEX ix_egg_q ON eggnog({eheader[0]})")
    print(f"eggnog: {m} rows (key col = {eheader[0]})")

    con.commit()
    con.close()
    print(f"Done: {OUT} ({OUT.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
