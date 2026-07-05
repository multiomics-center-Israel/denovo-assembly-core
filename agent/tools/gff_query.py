import os
from pathlib import Path

import gffutils

DB_PATH = Path(os.environ.get("GFF_DB_PATH", "/data/gff.sqlite"))


def db_present() -> bool:
    return DB_PATH.exists()


def _open():
    return gffutils.FeatureDB(str(DB_PATH))


def _jbrowse_url(contig, start, end, tracks):
    base = os.environ.get("JBROWSE_URL", "http://localhost:8080").rstrip("/")
    asm = os.environ.get("ASSEMBLY_NAME", "spalangia_cameroni")
    url = f"{base}/?assembly={asm}&loc={contig}:{start}-{end}"
    if tracks:
        url += f"&tracks={tracks}"
    return url


def locate(query: str, flank: int = 1000,
           tracks: str = "spalangia_genes") -> dict:
    """Resolve a gene/transcript to its genomic location and a JBrowse deep link.

    `query` is a feature id (gene/mRNA/tRNA) or a Name substring. `flank` bp are
    added on each side of the feature so it sits in context. Coordinates come from
    the GFF DB (canonical `_np1212` contigs).
    """
    if not db_present():
        return {"unavailable": True, "reason": f"GFF SQLite DB not found at {DB_PATH}"}
    db = _open()
    feat = None
    try:
        feat = db[query]                       # exact id (fast path)
    except Exception:
        feat = None

    matches = []
    if feat is None:
        q = query.lower()
        for ft in ("gene", "mRNA", "tRNA"):
            for f in db.features_of_type(ft):
                name = (f.attributes.get("Name", [""]) or [""])[0]
                if q == f.id.lower() or q in f.id.lower() or q in name.lower():
                    matches.append(f)
                    if len(matches) >= 5:
                        break
            if matches:
                break
        if not matches:
            return {"found": False, "flag": "not_found",
                    "reason": f"no gene/transcript matching '{query}' in the GFF DB",
                    "hint": "try functional_lookup(search=...) to find an id first"}
        feat = matches[0]

    try:
        flank = max(0, int(flank))
    except (TypeError, ValueError):
        flank = 1000
    contig, start, end = feat.seqid, feat.start, feat.end
    view_start, view_end = max(1, start - flank), end + flank
    out = {
        "found": True,
        "gene": {"id": feat.id, "type": feat.featuretype, "contig": contig,
                 "start": start, "end": end, "strand": feat.strand,
                 "name": (feat.attributes.get("Name", [None]) or [None])[0]},
        "flank": flank,
        "view": {"contig": contig, "start": view_start, "end": view_end},
        "url": _jbrowse_url(contig, view_start, view_end, tracks),
        "source": str(DB_PATH),
    }
    if len(matches) > 1:
        out["other_matches"] = [{"id": m.id, "type": m.featuretype} for m in matches[1:]]
        out["note"] = "multiple matches; showing the first"
    return out


def run(feature_type: str, contig: str | None = None,
        start: int | None = None, end: int | None = None,
        limit: int = 50) -> dict:
    if not db_present():
        return {
            "unavailable": True,
            "reason": f"GFF SQLite DB not found at {DB_PATH} (Phase 7.4 BRAKER3 pending)",
        }
    db = _open()
    region = None
    if contig is not None and start is not None and end is not None:
        region = (contig, start, end)

    if region is not None:
        it = db.region(region=region, featuretype=feature_type)
    else:
        it = db.features_of_type(feature_type)

    rows = []
    for i, feat in enumerate(it):
        if i >= limit:
            break
        rows.append({
            "id": feat.id,
            "seqid": feat.seqid,
            "start": feat.start,
            "end": feat.end,
            "strand": feat.strand,
            "type": feat.featuretype,
            "attributes": {k: list(v) for k, v in feat.attributes.items()},
        })
    return {"count": len(rows), "rows": rows, "source": str(DB_PATH)}
