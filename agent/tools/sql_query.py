"""Read-only SQL access to the agent's SQLite databases.

Exposes ad-hoc SELECT/WITH/PRAGMA-table_info queries against:
  - functional : funannotate + eggNOG tables (annotations, eggnog)
  - gff        : the gffutils feature DB (features, relations, ...)

Read-only is enforced two ways: the connection is opened mode=ro, and the
statement is checked to be a single SELECT/WITH/PRAGMA table_info. Anything the
query cannot answer (bad SQL, wrong db, empty result) comes back with a `flag`
so the model can hedge its answer.
"""
import os
import re
import sqlite3
from pathlib import Path

DBS = {
    "functional": Path(os.environ.get("FUNC_DB_PATH", "/data/functional.sqlite")),
    "gff": Path(os.environ.get("GFF_DB_PATH", "/data/gff.sqlite")),
}
MAX_ROWS = 200
_DDL = re.compile(
    r"\b(INSERT|UPDATE|DELETE|DROP|ALTER|CREATE|REPLACE|ATTACH|DETACH|VACUUM|REINDEX|TRIGGER)\b",
    re.I,
)


def dbs_present() -> dict:
    return {k: v.exists() for k, v in DBS.items()}


def _connect(db: str) -> sqlite3.Connection:
    con = sqlite3.connect(f"file:{DBS[db]}?mode=ro", uri=True)
    con.execute("PRAGMA query_only = ON")
    return con


def get_schema(db: str | None = None) -> dict:
    """List tables + column names for one db (or all)."""
    out = {}
    for d in ([db] if db in DBS else list(DBS)):
        if not DBS[d].exists():
            out[d] = {"unavailable": True}
            continue
        con = _connect(d)
        try:
            cur = con.cursor()
            tables = [
                r[0]
                for r in cur.execute(
                    "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
                )
            ]
            out[d] = {
                t: [c[1] for c in cur.execute(f"PRAGMA table_info('{t}')").fetchall()]
                for t in tables
            }
        finally:
            con.close()
    return {"schema": out}


def run(sql: str | None = None, db: str = "functional", schema: bool = False) -> dict:
    if schema or not sql:
        return get_schema(db if db in DBS else None)
    if db not in DBS:
        return {"error": f"unknown db '{db}'; choose 'functional' or 'gff'",
                "flag": "cannot_answer_with_sql"}
    if not DBS[db].exists():
        return {"unavailable": True, "reason": f"{db} DB not found at {DBS[db]}",
                "flag": "cannot_answer_with_sql"}

    stmt = sql.strip().rstrip(";").strip()
    if ";" in stmt:
        return {"error": "one statement only; remove the ';'",
                "flag": "cannot_answer_with_sql"}
    head = stmt.lstrip("( \n\t").lower()
    if not (head.startswith("select") or head.startswith("with")
            or head.startswith("pragma table_info")):
        return {"error": "only read-only SELECT / WITH / PRAGMA table_info is allowed",
                "flag": "cannot_answer_with_sql"}
    if _DDL.search(stmt):
        return {"error": "write / DDL keywords are not allowed (read-only)",
                "flag": "cannot_answer_with_sql"}

    con = _connect(db)
    try:
        cur = con.cursor()
        cur.execute(stmt)
        cols = [d[0] for d in cur.description] if cur.description else []
        rows = cur.fetchmany(MAX_ROWS + 1)
        truncated = len(rows) > MAX_ROWS
        data = [dict(zip(cols, r)) for r in rows[:MAX_ROWS]]
        return {
            "columns": cols,
            "rows": data,
            "row_count": len(data),
            "truncated": truncated,
            "db": db,
            "sql": stmt,
        }
    except sqlite3.Error as e:
        return {"error": f"SQL error: {e}", "flag": "cannot_answer_with_sql"}
    finally:
        con.close()
