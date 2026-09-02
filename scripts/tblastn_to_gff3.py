#!/usr/bin/env python3
"""Convert a tblastn outfmt-7 tabular result to GFF3 for a JBrowse 2 track.

Each HSP becomes one `protein_match` feature on the subject (genome)
coordinates. Expected query fields (the order produced by prep_tracks /
tblastn_protein_vs_genome.py):

  qseqid sseqid pident length mismatch gapopen qstart qend sstart send
  evalue bitscore ppos qcovs sseq

Usage: tblastn_to_gff3.py <tblastn_tab>   # writes GFF3 to stdout
"""
import os
import sys

# Per-HSP thresholds, AND-combined. Defaults are the close-homolog set;
# override via env to produce e.g. a strict-ortholog track.
MIN_QCOVS = float(os.environ.get("MIN_QCOVS", 60.0))
MIN_PIDENT = float(os.environ.get("MIN_PIDENT", 35.0))
MAX_EVALUE = float(os.environ.get("MAX_EVALUE", 0.01))
MIN_LENGTH_AA = int(os.environ.get("MIN_LENGTH_AA", 80))


def main(path):
    sys.stdout.write("##gff-version 3\n")
    n = 0
    with open(path) as fh:
        for line in fh:
            if line.startswith("#") or not line.strip():
                continue
            f = line.rstrip("\n").split("\t")
            if (float(f[2]) <= MIN_PIDENT or int(f[3]) <= MIN_LENGTH_AA or
                    float(f[10]) >= MAX_EVALUE or float(f[13]) <= MIN_QCOVS):
                continue
            qseqid, sseqid = f[0], f[1]
            pident, qstart, qend = f[2], f[6], f[7]
            sstart, send, evalue, bitscore, qcovs = int(f[8]), int(f[9]), f[10], f[11], f[13]
            # tblastn reports send < sstart on the minus strand; GFF needs
            # start <= end with strand carrying the orientation.
            strand = "+" if sstart <= send else "-"
            start, end = (sstart, send) if sstart <= send else (send, sstart)
            n += 1
            attrs = (f"ID=hsp{n};Name={qseqid};Target={qseqid} {qstart} {qend};"
                     f"pident={pident};evalue={evalue};qcovs={qcovs}")
            sys.stdout.write(
                f"{sseqid}\ttblastn\tprotein_match\t{start}\t{end}\t"
                f"{bitscore}\t{strand}\t.\t{attrs}\n")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: tblastn_to_gff3.py <tblastn_tab>")
    main(sys.argv[1])
