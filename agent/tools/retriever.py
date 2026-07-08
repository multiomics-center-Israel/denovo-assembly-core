import json
import os
from pathlib import Path

from rank_bm25 import BM25Okapi

INDEX_DIR = Path(os.environ.get("RAG_INDEX_DIR", "/data/rag"))
CHUNKS_FILE = INDEX_DIR / "chunks.jsonl"

_bm25 = None
_chunks: list[dict] = []


def index_present() -> bool:
    return CHUNKS_FILE.exists()


def _load():
    global _bm25, _chunks
    if _bm25 is not None:
        return
    if not index_present():
        raise FileNotFoundError(f"RAG index not built at {CHUNKS_FILE}")
    with CHUNKS_FILE.open() as fh:
        _chunks = [json.loads(line) for line in fh]
    tokenized = [c["text"].lower().split() for c in _chunks]
    _bm25 = BM25Okapi(tokenized)


def document(source: str) -> str | None:
    """Full text of one source doc, its chunks re-joined in file order."""
    _load()
    parts = [c["text"] for c in _chunks if c.get("source") == source]
    return "\n\n".join(parts) if parts else None


def run(query: str, k: int = 5) -> dict:
    _load()
    scores = _bm25.get_scores(query.lower().split())
    ranked = sorted(zip(scores, _chunks), key=lambda x: -x[0])[:k]
    hits = []
    for score, c in ranked:
        if score <= 0:
            continue
        hits.append({
            "score": float(score),
            "source": c["source"],
            "text": c["text"],
        })
    return {"query": query, "hits": hits}
