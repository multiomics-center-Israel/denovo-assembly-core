#!/usr/bin/env python3
"""Summarise venom-gland gene recovery.
Inputs:
  --ref     venom_reference.faa (query proteins)
  --genome_paf  miniprot PAF of venom ref vs genome (optional)
  --evm_blast   diamond blastp venom ref vs EVM proteins, fmt6 with qcovhsp scovhsp (optional)
  --tib_blast   diamond blastp venom ref vs Tiberius proteins, fmt6 (optional)
  --out     summary tsv
diamond fmt6 expected cols: qseqid sseqid pident length ... evalue bitscore qcovhsp scovhsp
We pass: 6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore qcovhsp scovhsp
"""
import argparse, collections, os

ap = argparse.ArgumentParser()
ap.add_argument("--ref", required=True)
ap.add_argument("--genome_paf")
ap.add_argument("--evm_blast")
ap.add_argument("--tib_blast")
ap.add_argument("--pid", type=float, default=30.0)
ap.add_argument("--cov", type=float, default=50.0)
ap.add_argument("--out", required=True)
a = ap.parse_args()

def ref_ids(path):
    ids = []
    with open(path) as fh:
        for line in fh:
            if line.startswith(">"):
                ids.append(line[1:].split()[0])
    return ids

refs = ref_ids(a.ref)
total = len(refs)

def best_blast(path):
    """Return dict qseqid -> (pident, qcov) best by bitscore, passing thresholds."""
    found = {}
    if not path or not os.path.exists(path):
        return found
    best = {}
    with open(path) as fh:
        for line in fh:
            c = line.rstrip("\n").split("\t")
            if len(c) < 12:
                continue
            q = c[0]; pid = float(c[2]); bits = float(c[11])
            qcov = float(c[12]) if len(c) > 12 else 0.0
            if q not in best or bits > best[q][0]:
                best[q] = (bits, pid, qcov)
    for q, (bits, pid, qcov) in best.items():
        if pid >= a.pid and qcov >= a.cov:
            found[q] = (pid, qcov)
    return found

def paf_hits(path):
    """miniprot PAF: count ref proteins with an alignment passing identity & coverage."""
    found = set()
    if not path or not os.path.exists(path):
        return found
    with open(path) as fh:
        for line in fh:
            c = line.split("\t")
            if len(c) < 12:
                continue
            q = c[0]; qlen = int(c[1]); qs = int(c[2]); qe = int(c[3])
            nmatch = int(c[9]); alen = int(c[10])
            qcov = 100.0 * (qe - qs) / qlen if qlen else 0
            pid = 100.0 * nmatch / alen if alen else 0
            if qcov >= a.cov and pid >= a.pid:
                found.add(q)
    return found

evm = best_blast(a.evm_blast)
tib = best_blast(a.tib_blast)
gen = paf_hits(a.genome_paf)

with open(a.out, "w") as o:
    o.write("metric\tcount\tpct_of_reference\n")
    def row(name, n):
        o.write(f"{name}\t{n}\t{100.0*n/total:.1f}\n")
    o.write(f"# venom reference proteins\t{total}\t100.0\n")
    row("present in genome (miniprot, pid>=%g cov>=%g)" % (a.pid, a.cov), len(gen))
    row("present in EVM+PASA canonical annotation (diamond)", len(evm))
    if a.tib_blast:
        row("present in Tiberius annotation (diamond)", len(tib))
    # union of annotation evidence
    union = set(evm) | set(tib)
    row("present in EVM OR Tiberius annotation", len(union))

# per-protein detail for EVM
det = os.path.splitext(a.out)[0] + "_per_protein.tsv"
with open(det, "w") as o:
    o.write("venom_ref\tin_genome_miniprot\tEVM_pident\tEVM_qcov\tTiberius_pident\tTiberius_qcov\n")
    for r in refs:
        e = evm.get(r); t = tib.get(r)
        o.write(f"{r}\t{'Y' if r in gen else ''}\t"
                f"{e[0] if e else ''}\t{e[1] if e else ''}\t"
                f"{t[0] if t else ''}\t{t[1] if t else ''}\n")
print(f"venom: {total} refs | genome {len(gen)} | EVM {len(evm)} | union {len(set(evm)|set(tib))}")
