"""Advanced gene-annotation search — deterministic, pure parameterized SQL.

Powers the browser's "Gene search" query-builder button (no LLM). Conditions come
from a whitelisted set of fields and operators; column names are never taken from
user input (only bound values are), so the generated SQL is injection-safe.
"""
import os
import re
import sqlite3
from pathlib import Path

DB_PATH = Path(os.environ.get("FUNC_DB_PATH", "/data/functional.sqlite"))

# UI field key -> annotations column. None = the special "any field" fan-out.
FIELDS = {
    "any": None,
    "product": "Product",
    "name": "Name",
    "gene_id": "GeneID",
    "transcript_id": "TranscriptID",
    "contig": "Contig",
    "go": "GO_Terms",
    "pfam": "PFAM",
    "interpro": "InterPro",
    "ec": "EC_number",
    "cog": "COG",
    "eggnog": "EggNog",
    "notes": "Notes",
}
# Boolean-ish annotation flags: presence test, value ignored.
FLAG_FIELDS = {"secreted": "Secreted", "membrane": "Membrane",
               "protease": "Protease", "cazyme": "CAZyme"}
ANY_COLS = ["GeneID", "TranscriptID", "Name", "Product", "PFAM", "InterPro",
            "GO_Terms", "EC_number", "COG", "Notes"]
OPS = {"contains", "equals", "regex"}
SELECT_COLS = ("GeneID, TranscriptID, Contig, Start, Stop, Strand, Name, Product, "
               "EC_number, PFAM, InterPro, GO_Terms, COG, Secreted, Membrane, "
               "Protease, CAZyme")


def db_present() -> bool:
    return DB_PATH.exists()


def _regexp(pattern, value) -> int:
    if value is None:
        return 0
    try:
        return 1 if re.search(pattern, str(value), re.IGNORECASE) else 0
    except re.error:
        return 0


def _op_frag(col: str, op: str, value: str):
    if op == "equals":
        return f"{col} = ? COLLATE NOCASE", [value]
    if op == "regex":
        return f"{col} REGEXP ?", [value]
    return f"{col} LIKE ? COLLATE NOCASE", [f"%{value}%"]  # contains (default)


def _cond_frag(field: str, op: str, value: str):
    """Return (sql_fragment, params) for one whitelisted condition, or None."""
    if field in FLAG_FIELDS:
        col = FLAG_FIELDS[field]
        return f"({col} IS NOT NULL AND {col} != '')", []
    if field not in FIELDS:
        return None
    if op not in OPS:
        op = "contains"
    if value == "":
        return None
    col = FIELDS[field]
    if col is None:  # "any" -> OR across the searchable text columns
        parts, params = [], []
        for c in ANY_COLS:
            frag, ps = _op_frag(c, op, value)
            parts.append(frag)
            params.extend(ps)
        return "(" + " OR ".join(parts) + ")", params
    frag, ps = _op_frag(col, op, value)
    return frag, ps


def _link(row: dict):
    contig = row.get("Contig")
    if not contig:
        return None
    ref = contig if contig.endswith("_np1212") else contig + "_np1212"
    try:
        s, e = int(row["Start"]), int(row["Stop"])
    except (TypeError, ValueError, KeyError):
        return None
    if s > e:
        s, e = e, s
    vs, ve = max(1, s - 1000), e + 1000
    base = os.environ.get("JBROWSE_URL", "http://localhost:8080").rstrip("/")
    asm = os.environ.get("ASSEMBLY_NAME", "spalangia_cameroni")
    return f"{base}/?assembly={asm}&loc={ref}:{vs}-{ve}&tracks=spalangia_genes"


def run(conditions: list, logic: str = "AND", limit: int = 50) -> dict:
    if not db_present():
        return {"unavailable": True, "reason": f"functional DB not found at {DB_PATH}"}
    if not isinstance(conditions, list):
        return {"error": "conditions must be a list", "count": 0, "rows": []}

    frags, params = [], []
    for c in conditions:
        if not isinstance(c, dict):
            continue
        built = _cond_frag(c.get("field", "any"),
                           c.get("op", "contains"),
                           (c.get("value") or "").strip())
        if built is None:
            continue
        frags.append(built[0])
        params.extend(built[1])

    if not frags:
        return {"error": "no valid conditions", "count": 0, "rows": []}

    joiner = " OR " if str(logic).upper() == "OR" else " AND "
    try:
        limit = max(1, min(500, int(limit)))
    except (TypeError, ValueError):
        limit = 50
    sql = f"SELECT {SELECT_COLS} FROM annotations WHERE {joiner.join(frags)} LIMIT ?"

    conn = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    conn.create_function("REGEXP", 2, _regexp)
    try:
        cur = conn.execute(sql, params + [limit])
        cols = [d[0] for d in cur.description]
        rows = [dict(zip(cols, r)) for r in cur.fetchall()]
    except sqlite3.Error as e:
        conn.close()
        return {"error": str(e), "sql": sql, "count": 0, "rows": []}
    conn.close()

    for r in rows:
        r["jbrowse"] = _link(r)
    return {"count": len(rows), "rows": rows,
            "logic": "OR" if joiner.strip() == "OR" else "AND",
            "sql": sql, "params": params + [limit]}
