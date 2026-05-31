import os
from pathlib import Path

import gffutils

DB_PATH = Path(os.environ.get("GFF_DB_PATH", "/data/gff.sqlite"))


def db_present() -> bool:
    return DB_PATH.exists()


def _open():
    return gffutils.FeatureDB(str(DB_PATH))


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
