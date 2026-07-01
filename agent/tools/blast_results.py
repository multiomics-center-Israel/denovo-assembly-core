"""Ingest local BLAST tabular results and turn them into a genome track + JBrowse link.

Local user runs BLAST against the local DBs, then POSTs the outfmt 6/7 text here.
We parse hits, place them on genome coordinates, write a GFF3 the browser loads as
the persistent `blast_hits` track ("latest" overwrite), and return a deep link.

Subject placement:
  blastn / tblastn  -> subject IS a genome contig; use sstart/send directly.
  blastp / blastx   -> subject is a transcript id; resolve its mRNA span via gff.sqlite.
"""
import os
import time
import uuid
from pathlib import Path

import gffutils

STORE_DIR = Path(os.environ.get("BLAST_RESULTS_DIR", "/data/blast_results"))
GFF_DB_PATH = Path(os.environ.get("GFF_DB_PATH", "/data/gff.sqlite"))
ASSEMBLY = os.environ.get("ASSEMBLY_NAME", "spalangia_cameroni")

# outfmt 6/7 default 12 columns
COLS = ["qseqid", "sseqid", "pident", "length", "mismatch", "gapopen",
        "qstart", "qend", "sstart", "send", "evalue", "bitscore"]

_db = None


def _gff():
    global _db
    if _db is None and GFF_DB_PATH.exists():
        _db = gffutils.FeatureDB(str(GFF_DB_PATH))
    return _db


def _tx_span(transcript_id: str):
    """Return (contig, start, end, strand) for a transcript/mRNA id, or None."""
    db = _gff()
    if db is None:
        return None
    for fid in (transcript_id, f"{transcript_id}", transcript_id.split()[0]):
        try:
            f = db[fid]
            return (f.seqid, f.start, f.end, f.strand or "+")
        except Exception:
            continue
    return None


def _parse_rows(text: str):
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 12:
            parts = line.split()
        if len(parts) < 12:
            continue
        row = dict(zip(COLS, parts[:12]))
        try:
            row["pident"] = float(row["pident"])
            row["length"] = int(row["length"])
            row["sstart"] = int(row["sstart"])
            row["send"] = int(row["send"])
            row["evalue"] = float(row["evalue"])
            row["bitscore"] = float(row["bitscore"])
        except ValueError:
            continue
        yield row


def _subject_type(program: str | None, subject_type: str | None) -> str:
    if subject_type in ("genome", "protein"):
        return subject_type
    p = (program or "").lower()
    return "protein" if p in ("blastp", "blastx") else "genome"


def parse_and_store(text: str, program: str | None = None,
                    subject_type: str | None = None,
                    jbrowse_url: str | None = None,
                    max_features: int = 2000) -> dict:
    stype = _subject_type(program, subject_type)
    features = []   # (contig, start, end, strand, attrs, score, pident)
    skipped = 0
    for row in _parse_rows(text):
        if stype == "genome":
            contig = row["sseqid"]
            s, e = sorted((row["sstart"], row["send"]))
            strand = "+" if row["sstart"] <= row["send"] else "-"
            name = row["qseqid"]
        else:
            span = _tx_span(row["sseqid"])
            if span is None:
                skipped += 1
                continue
            contig, s, e, strand = span
            name = f"{row['qseqid']}->{row['sseqid']}"
        features.append((contig, s, e, strand, name, row["bitscore"], row["pident"], row["evalue"]))
        if len(features) >= max_features:
            break

    if not features:
        return {"n_hits": 0, "skipped": skipped,
                "note": "no placeable hits (protein hits need gff.sqlite)"}

    # top hit by bitscore for the deep link
    features.sort(key=lambda f: -f[5])
    top = features[0]

    STORE_DIR.mkdir(parents=True, exist_ok=True)
    token = uuid.uuid4().hex[:12]
    gff_lines = ["##gff-version 3"]
    # sort by contig,start for tidy display
    for i, (contig, s, e, strand, name, bit, pid, ev) in enumerate(
            sorted(features, key=lambda f: (f[0], f[1]))):
        attrs = (f"ID=hit{i};Name={name};pident={pid};bitscore={bit};evalue={ev}")
        gff_lines.append(
            f"{contig}\tBLAST\tmatch\t{s}\t{e}\t{bit}\t{strand}\t.\t{attrs}")
    gff_text = "\n".join(gff_lines) + "\n"

    (STORE_DIR / f"{token}.gff3").write_text(gff_text)
    (STORE_DIR / "latest.gff3").write_text(gff_text)
    (STORE_DIR / "latest.meta").write_text(
        f"token={token}\ntime={int(time.time())}\nn_hits={len(features)}\n"
        f"program={program}\nsubject_type={stype}\n")

    base = jbrowse_url or os.environ.get("JBROWSE_URL", "http://localhost:8080")
    pad = 500
    loc = f"{top[0]}:{max(1, top[1] - pad)}-{top[2] + pad}"
    link = (f"{base}/?assembly={ASSEMBLY}&loc={loc}"
            f"&tracks=blast_hits,spalangia_genes")

    return {
        "token": token,
        "n_hits": len(features),
        "skipped": skipped,
        "subject_type": stype,
        "top_hit": {"contig": top[0], "start": top[1], "end": top[2],
                    "name": top[4], "pident": top[6], "bitscore": top[5]},
        "jbrowse_url": link,
        "gff_url": f"/blast-results/latest.gff3",
    }


def latest() -> dict:
    meta = STORE_DIR / "latest.meta"
    if not meta.exists():
        return {"present": False}
    info = dict(
        line.split("=", 1) for line in meta.read_text().splitlines() if "=" in line)
    info["present"] = True
    return info
