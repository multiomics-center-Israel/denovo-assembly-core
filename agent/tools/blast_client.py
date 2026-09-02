import os

import httpx

BLAST_URL = os.environ.get("BLAST_URL", "http://blast:4567")


def run(sequence: str, program: str, db: str, evalue: float = 1e-5) -> dict:
    payload = {
        "method": program,
        "sequence": sequence,
        "databases[]": db,
    }
    with httpx.Client(base_url=BLAST_URL, timeout=120.0) as c:
        r = c.post("/", data=payload)
        if r.status_code != 200:
            return {"error": f"SequenceServer returned {r.status_code}", "body": r.text[:500]}
        loc = r.headers.get("location") or "/"
        result = c.get(loc + ".json")
        if result.status_code != 200:
            return {"error": f"result fetch {result.status_code}", "url": loc}
        return result.json()
