import os
from pathlib import Path

import pysam

FASTA_PATH = Path(os.environ.get(
    "ASSEMBLY_FASTA", "/data/jbrowse/genome/final_assembly.fa.gz"))


def fasta_present() -> bool:
    return FASTA_PATH.exists() and FASTA_PATH.with_suffix(".gz.fai").exists()


def _open() -> pysam.FastaFile:
    if not fasta_present():
        raise FileNotFoundError(f"bgzipped+faidx'd FASTA not found at {FASTA_PATH}")
    return pysam.FastaFile(str(FASTA_PATH))


def _summary(fa: pysam.FastaFile, top_n: int) -> dict:
    pairs = sorted(zip(fa.references, fa.lengths), key=lambda x: -x[1])
    return {
        "count": len(pairs),
        "total_length": sum(fa.lengths),
        "top_contigs": [{"name": n, "length": l} for n, l in pairs[:top_n]],
        "source": str(FASTA_PATH),
    }


def _per_contig(fa: pysam.FastaFile, contig: str) -> dict:
    if contig not in fa.references:
        return {"error": f"contig '{contig}' not in assembly"}
    seq = fa.fetch(contig).upper()
    length = len(seq)
    gc = seq.count("G") + seq.count("C")
    n = seq.count("N")
    n_runs = 0
    in_run = False
    for base in seq:
        if base == "N":
            if not in_run:
                n_runs += 1
                in_run = True
        else:
            in_run = False
    return {
        "name": contig,
        "length": length,
        "gc_percent": round(100.0 * gc / max(length - n, 1), 3),
        "n_percent": round(100.0 * n / length, 3),
        "n_runs": n_runs,
    }


def run(contig: str | None = None, top_n: int = 10) -> dict:
    try:
        fa = _open()
    except FileNotFoundError as e:
        return {"unavailable": True, "reason": str(e)}
    try:
        if contig is None:
            return _summary(fa, top_n)
        return _per_contig(fa, contig)
    finally:
        fa.close()
