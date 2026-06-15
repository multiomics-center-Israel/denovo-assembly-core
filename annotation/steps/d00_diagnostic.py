#!/usr/bin/env python3
"""D00 BUSCO lever diagnostic: classify the canonical-set completeness gap by
comparing per-BUSCO status against the raw BRAKER3 set. See D00_busco_diagnostic.sh."""
import argparse, collections, datetime

def load(path):
    """busco id -> best status (Complete/Duplicated > Fragmented > Missing)."""
    rank = {"Complete": 3, "Duplicated": 3, "Fragmented": 2, "Missing": 1}
    best = {}
    with open(path) as fh:
        for line in fh:
            if line.startswith("#") or not line.strip():
                continue
            f = line.rstrip("\n").split("\t")
            bid, status = f[0], f[1]
            r = rank.get(status, 0)
            if bid not in best or r > best[bid][0]:
                best[bid] = (r, status)
    return {k: v[1] for k, v in best.items()}

def simplify(s):
    return "Complete" if s in ("Complete", "Duplicated") else s

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--braker", required=True)
    ap.add_argument("--canonical", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    braker = {k: simplify(v) for k, v in load(a.braker).items()}
    canon = {k: simplify(v) for k, v in load(a.canonical).items()}
    # guard: the two tables must share a BUSCO id namespace (same lineage). If the
    # overlap is small, they are different lineages (e.g. odb9 EOG vs odb10 at7399).
    overlap = len(set(braker) & set(canon))
    union = len(set(braker) | set(canon))
    if union == 0 or overlap < 0.5 * union:
        raise SystemExit(
            f"ERROR: BUSCO tables are not the same lineage (overlap {overlap}/{union}). "
            f"Both must be hymenoptera_odb10. braker sample={next(iter(braker),'?')} "
            f"canonical sample={next(iter(canon),'?')}")
    ids = sorted(set(braker) | set(canon))
    total = len(ids)

    def pct(n): return f"{100.0*n/total:.1f}%" if total else "n/a"
    cc = collections.Counter(canon.get(i, "Missing") for i in ids)
    bc = collections.Counter(braker.get(i, "Missing") for i in ids)

    recoverable, hard_tail, regression, frag_repair = [], [], [], []
    for i in ids:
        c, b = canon.get(i, "Missing"), braker.get(i, "Missing")
        if c == "Missing" and b == "Complete":
            recoverable.append(i)
        elif c == "Missing" and b in ("Missing", "Fragmented"):
            hard_tail.append(i)
        elif c == "Fragmented" and b == "Complete":
            frag_repair.append(i)
        elif c == "Complete" and b == "Missing":
            regression.append(i)

    cheap = len(recoverable) + len(frag_repair)
    if cheap >= len(hard_tail) and cheap > 0:
        verdict = (f"MODEL lever dominates — {cheap} BUSCOs are Complete in raw BRAKER3 but "
                   f"Missing/Fragmented in canonical (recoverable by switching/merging models, "
                   f"no new data). Hard tail (Missing in both) = {len(hard_tail)}.")
    elif len(hard_tail) > 0:
        verdict = (f"DATA/MASKING lever dominates — {len(hard_tail)} BUSCOs Missing in BOTH sets; "
                   f"only {cheap} recoverable from BRAKER. Gains need more evidence (RNA/protein) "
                   f"or reduced masking; some may be true Spalangia divergence (publish as-is).")
    else:
        verdict = "Canonical already captures BRAKER's completeness; gap is data-bound."

    L = []
    L.append("# D00 — BUSCO lever diagnostic (raw BRAKER3 vs canonical)")
    L.append(f"_generated {datetime.datetime.now():%Y-%m-%d %H:%M:%S}_  •  lineage total = {total}\n")
    L.append("## Set-level completeness")
    L.append("| set | Complete | Fragmented | Missing |")
    L.append("|---|---|---|---|")
    L.append(f"| raw BRAKER3 | {bc['Complete']} ({pct(bc['Complete'])}) | {bc['Fragmented']} | {bc['Missing']} |")
    L.append(f"| canonical (funannotate_final) | {cc['Complete']} ({pct(cc['Complete'])}) | {cc['Fragmented']} | {cc['Missing']} |\n")
    L.append("## Lever breakdown (per-BUSCO cross-tab)")
    L.append(f"- **recoverable** (canonical Missing, BRAKER Complete): **{len(recoverable)}** — cheap model-merge win")
    L.append(f"- **frag_repair** (canonical Fragmented, BRAKER Complete): **{len(frag_repair)}** — model repair")
    L.append(f"- **hard_tail** (Missing in BOTH): **{len(hard_tail)}** — needs data/less masking, or true divergence")
    L.append(f"- **regression** (canonical Complete, BRAKER Missing): {len(regression)} — funannotate already added these\n")
    L.append(f"VERDICT: {verdict}\n")
    if recoverable:
        L.append("<details><summary>recoverable BUSCO ids</summary>\n\n" + ", ".join(recoverable[:200]) + "\n</details>")
    with open(a.out, "w") as fh:
        fh.write("\n".join(L) + "\n")
    print(verdict)

if __name__ == "__main__":
    main()
