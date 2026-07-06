"""Run BLAST server-side against the bundled local DBs — deterministic, no LLM.

`run(query, program, evalue)` shells out to the NCBI BLAST+ binary against the
genome or protein DB (chosen from the program), then hands the tabular output to
`blast_results.parse_and_store` so hits land on the JBrowse `blast_hits` track.
This is the same result shape the host `run_blast.sh` produced, but computed
inside the agent instead of on the host.

Program -> subject DB:
  blastn / tblastn  -> genome DB   (subject is a contig)
  blastp / blastx   -> protein DB  (subject is a transcript id)
"""
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

from . import blast_results

BLAST_DB_DIR = Path(os.environ.get("BLAST_DB_DIR", "/data/blast/db"))
GENOME_DB = os.environ.get("BLAST_GENOME_DB", "spalangia_genome")
PROTEIN_DB = os.environ.get("BLAST_PROTEIN_DB", "spalangia_proteins")
DEFAULT_EVALUE = os.environ.get("BLAST_EVALUE", "1e-5")
TIMEOUT = int(os.environ.get("BLAST_TIMEOUT", "180"))
MAX_QUERY_BYTES = int(os.environ.get("BLAST_MAX_QUERY_BYTES", str(2_000_000)))
MAX_TARGET_SEQS = os.environ.get("BLAST_MAX_TARGET_SEQS", "500")

PROGRAMS = {
    "blastn": GENOME_DB,
    "tblastn": GENOME_DB,
    "blastp": PROTEIN_DB,
    "blastx": PROTEIN_DB,
}


def _db_path(program: str) -> Path:
    return BLAST_DB_DIR / PROGRAMS[program]


def _binary_present(program: str) -> bool:
    return shutil.which(program) is not None


def _db_present(program: str) -> bool:
    base = _db_path(program)
    return any(base.parent.glob(base.name + ".*"))


def available() -> dict:
    """Report which BLAST binaries + DBs this container can actually run."""
    return {
        "db_dir": str(BLAST_DB_DIR),
        "binaries": {p: _binary_present(p) for p in PROGRAMS},
        "genome_db_present": _db_present("blastn"),
        "protein_db_present": _db_present("blastp"),
    }


def _normalize_query(query: str) -> str:
    q = (query or "").strip()
    if not q:
        raise ValueError("empty query")
    if not q.startswith(">"):
        q = ">query\n" + q
    return q + "\n"


def run(query: str, program: str, evalue=None, extra=None) -> dict:
    """Run one BLAST search and store hits as the blast_hits track.

    Returns the parse_and_store result dict (token, n_hits, jbrowse_url, ...),
    or {"error": ...} on any validation/runtime failure. Never raises.
    """
    program = (program or "").lower().strip()
    if program not in PROGRAMS:
        return {"error": f"unknown program {program!r}; use one of {sorted(PROGRAMS)}"}
    if not _binary_present(program):
        return {"error": f"{program} is not installed in this container"}
    if not _db_present(program):
        return {"error": f"no BLAST db for {program} at {_db_path(program)}.*"}
    try:
        fasta = _normalize_query(query)
    except ValueError as e:
        return {"error": str(e)}
    if len(fasta.encode()) > MAX_QUERY_BYTES:
        return {"error": f"query too large (> {MAX_QUERY_BYTES} bytes)"}
    ev = str(evalue) if evalue is not None else DEFAULT_EVALUE

    tf = tempfile.NamedTemporaryFile("w", suffix=".fa", delete=False)
    try:
        tf.write(fasta)
        tf.close()
        cmd = [program, "-query", tf.name, "-db", str(_db_path(program)),
               "-evalue", ev, "-outfmt", "6",
               "-max_target_seqs", str(MAX_TARGET_SEQS)]
        if extra:
            cmd += [str(a) for a in extra]
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True,
                                  timeout=TIMEOUT)
        except subprocess.TimeoutExpired:
            return {"error": f"BLAST timed out after {TIMEOUT}s"}
        except FileNotFoundError:
            return {"error": f"{program} binary not found on PATH"}
        if proc.returncode != 0:
            return {"error": f"{program} failed (exit {proc.returncode})",
                    "stderr": (proc.stderr or "").strip()[:1000]}
        result = blast_results.parse_and_store(
            proc.stdout, program=program,
            jbrowse_url=os.environ.get("JBROWSE_URL"))
        result["program"] = program
        result["evalue"] = ev
        return result
    finally:
        try:
            os.unlink(tf.name)
        except OSError:
            pass
