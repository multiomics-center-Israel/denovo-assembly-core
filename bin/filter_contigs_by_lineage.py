#!/usr/bin/env python3
"""Walk Kraken2 nodes.dmp to split contigs into keep / contaminant lists.

Used by the Phase 4 contig-level decontamination step (both the Python
pipeline at denovo_assembly_core.pipeline.phase4_decontamination and the
NeatSeq-Flow workflow at config/neatseq_flow/genome_assembly_workflow.template.yaml).

A contig is dropped only if its taxid's lineage passes through one of
CONTAM_TAXIDS: bacteria, archaea, viruses, fungi, synthetic constructs.
Hominidae/Vertebrata are intentionally excluded because Kraken2 PlusPF
yields spurious vertebrate hits on insect contigs lacking close references.
"""

import argparse
import pathlib
import sys

CONTAM_TAXIDS = {2, 2157, 10239, 4751, 32630, 28384}


def load_parent_map(nodes_dmp: pathlib.Path) -> dict:
    parent = {}
    for line in nodes_dmp.read_text().splitlines():
        f = [x.strip() for x in line.split("|")]
        parent[int(f[0])] = int(f[1])
    return parent


def has_contam_ancestor(taxid: int, parent: dict) -> bool:
    seen = set()
    while taxid and taxid not in seen:
        if taxid in CONTAM_TAXIDS:
            return True
        seen.add(taxid)
        taxid = parent.get(taxid, 0)
    return False


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--kraken2-out", required=True, type=pathlib.Path,
                    help="Per-contig Kraken2 output (C/U TAB contig TAB taxid TAB ...)")
    ap.add_argument("--kraken2-db", required=True, type=pathlib.Path,
                    help="Kraken2 DB directory (must contain nodes.dmp or taxonomy/nodes.dmp)")
    ap.add_argument("--keep-out", required=True, type=pathlib.Path,
                    help="Output: list of contig IDs to keep (one per line)")
    ap.add_argument("--contam-out", required=True, type=pathlib.Path,
                    help="Output: contig_id<TAB>taxid for dropped contigs")
    args = ap.parse_args()

    nodes_dmp = None
    for cand in (args.kraken2_db / "nodes.dmp",
                 args.kraken2_db / "taxonomy" / "nodes.dmp"):
        if cand.exists():
            nodes_dmp = cand
            break
    if nodes_dmp is None:
        sys.exit(f"nodes.dmp not found under {args.kraken2_db}")

    parent = load_parent_map(nodes_dmp)

    kept, contaminated = [], []
    for line in args.kraken2_out.read_text().splitlines():
        if not line.strip():
            continue
        f = line.split("\t")
        status, cid, taxid = f[0], f[1], int(f[2])
        if status != "U" and taxid != 0 and has_contam_ancestor(taxid, parent):
            contaminated.append((cid, taxid))
        else:
            kept.append(cid)

    args.keep_out.parent.mkdir(parents=True, exist_ok=True)
    args.keep_out.write_text("\n".join(kept) + "\n")
    args.contam_out.write_text("\n".join(f"{c}\t{t}" for c, t in contaminated) + "\n")
    print(f"KEEP={len(kept)}  CONTAM={len(contaminated)}")


if __name__ == "__main__":
    main()
