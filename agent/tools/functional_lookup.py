import os
import sqlite3
from pathlib import Path

DB_PATH = Path(os.environ.get("FUNC_DB_PATH", "/data/functional.sqlite"))


def db_present() -> bool:
    return DB_PATH.exists()


def _rows(cur, sql, params):
    cur.execute(sql, params)
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, r)) for r in cur.fetchall()]


def run(gene_id: str | None = None, transcript_id: str | None = None,
        search: str | None = None, limit: int = 25) -> dict:
    """Look up functional annotation (funannotate + eggNOG).

    Provide one of: transcript_id (exact), gene_id (exact),
    or search (substring match on Product/Name).
    """
    if not db_present():
        return {"unavailable": True, "reason": f"functional DB not found at {DB_PATH}"}
    con = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    cur = con.cursor()
    try:
        if transcript_id:
            ann = _rows(cur, "SELECT * FROM annotations WHERE TranscriptID=? LIMIT ?",
                        (transcript_id, limit))
            egg = _rows(cur, "SELECT * FROM eggnog WHERE query=? LIMIT ?",
                        (transcript_id, limit))
        elif gene_id:
            ann = _rows(cur, "SELECT * FROM annotations WHERE GeneID=? LIMIT ?",
                        (gene_id, limit))
            egg = []
            for a in ann:
                egg += _rows(cur, "SELECT * FROM eggnog WHERE query=? LIMIT 1",
                             (a.get("TranscriptID", ""),))
        elif search:
            like = f"%{search}%"
            ann = _rows(cur,
                        "SELECT * FROM annotations WHERE Product LIKE ? OR Name LIKE ? LIMIT ?",
                        (like, like, limit))
            egg = []
        else:
            return {"error": "provide gene_id, transcript_id, or search"}
        return {"annotations": ann, "eggnog": egg, "source": str(DB_PATH)}
    finally:
        con.close()
