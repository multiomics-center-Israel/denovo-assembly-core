#!/usr/bin/env python3
"""Add-only, evidence-gated rescue of Tiberius gene models into the EVM+PASA
canonical set. Three subcommands driven by merge_tiberius_rescue.sh:

  beds      -> write EVM + Tiberius gene-locus BEDs (strand-aware)
  candprot  -> given candidate Tiberius gene-ids, write their protein fasta
  finalize  -> apply the balanced gate (BUSCO | homology | expression),
               protect duplication, emit merged proteome + merged gff3 + decisions

Tiberius gene_id convention: gtf attr gene_id "gN"; aa header >g?|gN.tK|coords
(the gene id is the MIDDLE pipe token minus .tK); BUSCO full_table Sequence col
is g?|gN.tK|coords likewise. So gene = header.split('|')[1].split('.')[0].
"""
import argparse, os, re, sys, collections

def tib_gene_from_token(tok):
    # tok like 'g5|g19730.t1|ptg..:..' or 'g19730.t1' or 'gN'
    parts = tok.split('|')
    mid = parts[1] if len(parts) >= 2 else parts[0]
    return mid.split('.')[0]

def busco_status(path):
    """best status per busco id; returns dict id->status and id->seq(geneid for tib)."""
    rank = {'Complete':3,'Duplicated':3,'Fragmented':2,'Missing':1}
    st, seq = {}, {}
    with open(path) as f:
        for l in f:
            if l.startswith('#'): continue
            c = l.rstrip('\n').split('\t')
            if len(c) < 2: continue
            bid, s = c[0], c[1]
            if bid not in st or rank.get(s,0) > rank.get(st[bid],0):
                st[bid] = s
                if s != 'Missing' and len(c) > 2:
                    seq[bid] = c[2]
    return st, seq

# ---------------- beds ----------------
def cmd_beds(a):
    # EVM canonical gff3 gene features
    with open(a.evm_gff) as f, open(a.evm_bed,'w') as o:
        for l in f:
            if l.startswith('#'): continue
            c = l.rstrip('\n').split('\t')
            if len(c) < 9 or c[2] != 'gene': continue
            m = re.search(r'ID=([^;]+)', c[8])
            gid = m.group(1) if m else '.'
            o.write(f"{c[0]}\t{int(c[3])-1}\t{c[4]}\t{gid}\t.\t{c[6]}\n")
    # Tiberius gtf gene features
    n = 0
    with open(a.tib_gtf) as f, open(a.tib_bed,'w') as o:
        for l in f:
            if l.startswith('#'): continue
            c = l.rstrip('\n').split('\t')
            if len(c) < 9 or c[2] != 'gene': continue
            m = re.search(r'gene_id "([^"]+)"', c[8])
            gid = m.group(1) if m else '.'
            o.write(f"{c[0]}\t{int(c[3])-1}\t{c[4]}\t{gid}\t.\t{c[6]}\n")
            n += 1
    print(f"beds: tiberius genes={n}")

# ---------------- candprot ----------------
def cmd_candprot(a):
    keep = set(l.strip() for l in open(a.cand_ids) if l.strip())
    out = open(a.out_faa,'w')
    write = False
    kept = set()
    with open(a.tib_aa) as f:
        for l in f:
            if l.startswith('>'):
                g = tib_gene_from_token(l[1:].strip())
                write = g in keep
                if write:
                    kept.add(g)
                    out.write(f">{g}\n")   # simplify header to bare gene id
            elif write:
                out.write(l)
    out.close()
    print(f"candprot: candidates={len(keep)} proteins_written_for={len(kept)}")

# ---------------- finalize ----------------
def parse_diamond(path, pid, qcov, evalue):
    """fmt6: qseqid sseqid pident length mm gap qs qe ss se evalue bitscore qcovhsp.
    qseqid is the bare gene id we wrote in candprot."""
    hit = {}
    if not path or not os.path.exists(path): return hit
    with open(path) as f:
        for l in f:
            c = l.rstrip('\n').split('\t')
            if len(c) < 12: continue
            q = c[0]; p = float(c[2]); e = float(c[10]); qc = float(c[12]) if len(c) > 12 else 0.0
            if p >= pid and e <= evalue and qc >= qcov:
                if q not in hit or float(c[11]) > hit[q]:
                    hit[q] = float(c[11])
    return set(hit)

def parse_expr(path, gene_col=3):
    """bedtools intersect -wa -u output of tib_bed vs pasa assemblies -> gene ids col4."""
    s = set()
    if not path or not os.path.exists(path): return s
    with open(path) as f:
        for l in f:
            c = l.rstrip('\n').split('\t')
            if len(c) > gene_col: s.add(c[gene_col])
    return s

def cmd_finalize(a):
    cands = set(l.strip() for l in open(a.cand_ids) if l.strip())
    # BUSCO sets
    evm_st, _ = busco_status(a.evm_busco)
    tib_st, tib_seq = busco_status(a.tib_busco)
    def complete(s): return s in ('Complete','Duplicated')
    def present(s): return s in ('Complete','Duplicated','Fragmented')
    evm_complete = {k for k,v in evm_st.items() if complete(v)}
    # buscos EVM does NOT have complete (missing or fragmented) but tiberius completes
    rescuable = {k for k in tib_st if complete(tib_st[k]) and k not in evm_complete}
    # map those buscos to tiberius gene ids
    busco_gene = {}                      # gene -> busco id (first rescuable)
    for bid in rescuable:
        seqtok = tib_seq.get(bid)
        if not seqtok: continue
        g = tib_gene_from_token(seqtok)
        busco_gene.setdefault(g, bid)
    busco_pass = set(busco_gene) & cands
    # homology + expression
    hom_pass = parse_diamond(a.diamond, a.pid, a.qcov, a.evalue) & cands
    expr_pass = parse_expr(a.expr) & cands
    # union, then protect duplication: drop a kept gene if its (any) busco is ALREADY
    # complete in EVM (would just add a duplicate BUSCO). Build gene->busco for ALL tib buscos.
    gene_allbusco = collections.defaultdict(set)
    for bid, s in tib_st.items():
        if s == 'Missing': continue
        seqtok = tib_seq.get(bid)
        if seqtok:
            gene_allbusco[tib_gene_from_token(seqtok)].add(bid)
    kept = set()
    dropped_dup = set()
    for g in (busco_pass | hom_pass | expr_pass):
        # if this gene carries ONLY buscos already complete in EVM, and it wasn't a
        # busco-rescue itself, skip to protect duplication
        gb = gene_allbusco.get(g, set())
        if g not in busco_pass and gb and gb <= evm_complete:
            dropped_dup.add(g); continue
        kept.add(g)
    # write decisions
    with open(a.decisions,'w') as o:
        o.write("tiberius_gene\tbusco_rescue\thomology\texpression\tbusco_id\n")
        for g in sorted(kept):
            o.write(f"{g}\t{'Y' if g in busco_pass else ''}\t{'Y' if g in hom_pass else ''}"
                    f"\t{'Y' if g in expr_pass else ''}\t{busco_gene.get(g,'')}\n")
    # Pick ONE representative isoform (longest protein) per kept gene. The candidate
    # set may be multi-isoform (braker emits g30.t1, g30.t2, ...); the graft recovers a
    # single model per locus (as Tiberius does). Emitting every isoform under the bare
    # gene id produced duplicate FASTA headers (BUSCO-fatal) and duplicate mRNA IDs in
    # the GFF. Single-isoform inputs (Tiberius) are unaffected — the only transcript wins.
    def aa_iter(path):
        h = None; buf = []
        for l in open(path):
            if l.startswith('>'):
                if h is not None: yield h, ''.join(buf)
                h = l[1:].strip(); buf = []
            else: buf.append(l.strip())
        if h is not None: yield h, ''.join(buf)
    def tib_tx_from_token(tok):                      # 'g5|g19730.t1|coords' or 'g30.t1'
        parts = tok.split('|'); return (parts[1] if len(parts) >= 2 else parts[0]).split()[0]
    rep_tx, rep_seq = {}, {}                         # gene -> chosen transcript id / protein
    for h, seq in aa_iter(a.tib_aa):
        g = tib_gene_from_token(h)
        if g not in kept: continue
        if g not in rep_seq or len(seq) > len(rep_seq[g]):
            rep_tx[g] = tib_tx_from_token(h); rep_seq[g] = seq
    # merged proteome = canonical proteins + one protein per kept gene
    with open(a.merged_faa,'w') as o:
        for l in open(a.evm_faa):
            o.write(l)
        for g in sorted(rep_tx):
            o.write(f">TIBR_{g}\n")
            s = rep_seq[g]
            for i in range(0, len(s), 60):
                o.write(s[i:i+60] + "\n")
    # merged gff3 = canonical gff3 + the representative transcript of each kept gene
    def gtf_tx(attr):
        m = re.search(r'transcript_id "([^"]+)"', attr); return m.group(1) if m else None
    with open(a.merged_gff,'w') as o:
        o.write("##gff-version 3\n")
        for l in open(a.evm_gff):
            if not l.startswith('#'): o.write(l)
        # emit kept tiberius features (representative transcript only)
        for l in open(a.tib_gtf):
            if l.startswith('#'): continue
            c = l.rstrip('\n').split('\t')
            if len(c) < 9: continue
            m = re.search(r'gene_id "([^"]+)"', c[8])
            g = m.group(1) if m else None
            if g not in kept: continue
            t = c[2]
            tid = f"TIBR_{g}"
            if t == 'gene':
                attr = f"ID={tid}"
            elif t == 'transcript':
                if gtf_tx(c[8]) != rep_tx.get(g): continue   # skip non-representative isoforms
                attr = f"ID={tid}.t1;Parent={tid}"
                t = 'mRNA'
            elif t in ('exon','CDS'):
                if gtf_tx(c[8]) != rep_tx.get(g): continue
                attr = f"ID={tid}.{t}.{c[3]};Parent={tid}.t1"
            else:
                continue
            o.write("\t".join(c[:2]+[t]+c[3:8]+[attr])+"\n")
    n_evm = sum(1 for l in open(a.evm_gff) if not l.startswith('#') and l.split('\t')[2:3]==['gene'])
    print(f"finalize: candidates={len(cands)} | busco={len(busco_pass)} hom={len(hom_pass)} "
          f"expr={len(expr_pass)} | kept={len(kept)} dropped_dup={len(dropped_dup)} "
          f"| merged_genes={n_evm+len(kept)} (evm {n_evm} + tib {len(kept)})")

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('beds'); b.add_argument('--evm_gff',required=True); b.add_argument('--tib_gtf',required=True)
    b.add_argument('--evm_bed',required=True); b.add_argument('--tib_bed',required=True); b.set_defaults(fn=cmd_beds)
    c = sub.add_parser('candprot'); c.add_argument('--cand_ids',required=True); c.add_argument('--tib_aa',required=True)
    c.add_argument('--out_faa',required=True); c.set_defaults(fn=cmd_candprot)
    z = sub.add_parser('finalize')
    z.add_argument('--cand_ids',required=True); z.add_argument('--evm_busco',required=True); z.add_argument('--tib_busco',required=True)
    z.add_argument('--diamond'); z.add_argument('--expr'); z.add_argument('--evm_faa',required=True); z.add_argument('--tib_aa',required=True)
    z.add_argument('--evm_gff',required=True); z.add_argument('--tib_gtf',required=True)
    z.add_argument('--merged_faa',required=True); z.add_argument('--merged_gff',required=True); z.add_argument('--decisions',required=True)
    z.add_argument('--pid',type=float,default=30.0); z.add_argument('--qcov',type=float,default=50.0); z.add_argument('--evalue',type=float,default=1e-10)
    z.set_defaults(fn=cmd_finalize)
    a = ap.parse_args(); a.fn(a)
