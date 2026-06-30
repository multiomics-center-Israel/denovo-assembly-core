#!/usr/bin/env python3
"""CDS-locked UTR graft: attach PASA-recovered UTRs (from BRAKER models) onto the
canonical funannotate annotation WITHOUT altering any CDS.

A UTR is transferred to a canonical mRNA only when a PASA model has a byte-identical
CDS structure (same seqid/strand/all CDS segments). The donor's full exon span then
defines the transcript bounds; UTR features are DERIVED as exon-minus-CDS so exon/CDS/UTR
are mutually consistent. Canonical CDS lines (incl. phase) and all mRNA/gene attributes
are preserved verbatim. Genes with no identical-CDS UTR donor are emitted unchanged.

Seqid note: canonical seqids are stripped (ptg000001l); PASA seqids carry _np#### —
normalized for matching, canonical seqid kept on output.
"""
import re, sys
from collections import defaultdict

CANON = "/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly/annotation/funannotate_merged_out/annotate_results/Spalangia_cameroni.gff3"
PASA  = "/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly/analysis/utr/pasa_updated.gff3"
OUT   = "/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly/annotation/funannotate_merged_out/annotate_results/Spalangia_cameroni.utr.gff3"

def norm(s): return re.sub(r'_np\d+$', '', s)
def attr_id(a):
    m = re.search(r'ID=([^;]+)', a); return m.group(1) if m else None
def attr_parent(a):
    m = re.search(r'Parent=([^;]+)', a); return m.group(1).split(',')[0] if m else None

# ---- parse PASA donors: CDS signature -> best (exons, cds) ----
def parse_pasa(path):
    mrna = {}  # id -> dict
    for ln in open(path):
        if ln.startswith('#') or '\t' not in ln: continue
        c = ln.rstrip('\n').split('\t')
        if len(c) < 9: continue
        seqid, _, ft, s, e, _, strand, _, attr = c[:9]
        s, e = int(s), int(e)
        if ft == 'mRNA':
            mid = attr_id(attr)
            mrna[mid] = dict(seqid=norm(seqid), strand=strand, cds=[], exon=[])
        elif ft in ('CDS', 'exon'):
            pid = attr_parent(attr)
            if pid in mrna:
                mrna[pid]['cds' if ft == 'CDS' else 'exon'].append((s, e))
    sig_map = {}
    for v in mrna.values():
        if not v['cds'] or not v['exon']: continue
        v['cds'].sort(); v['exon'].sort()
        cmin, cmax = v['cds'][0][0], v['cds'][-1][1]
        emin, emax = v['exon'][0][0], v['exon'][-1][1]
        utr_len = (cmin - emin) + (emax - cmax)
        if utr_len <= 0: continue                      # donor has no UTR -> useless
        sig = (v['seqid'], v['strand'], tuple(v['cds']))
        # keep the donor with the most UTR for a given CDS signature
        if sig not in sig_map or utr_len > sig_map[sig][1]:
            sig_map[sig] = (v['exon'], utr_len)
    return sig_map

# ---- derive UTR segments from full exon list + CDS, strand-aware ----
def derive_utrs(exons, cds, strand):
    cmin = min(s for s, e in cds); cmax = max(e for s, e in cds)
    five, three = [], []
    for (es, ee) in exons:
        if es < cmin:
            seg = (es, min(ee, cmin - 1))
            if seg[1] >= seg[0]:
                (five if strand == '+' else three).append(seg)
        if ee > cmax:
            seg = (max(es, cmax + 1), ee)
            if seg[1] >= seg[0]:
                (three if strand == '+' else five).append(seg)
    return sorted(five), sorted(three)

# ---- parse canonical, grafting as we reconstruct ----
pasa_sig = parse_pasa(PASA)
print(f"PASA UTR-bearing CDS signatures: {len(pasa_sig)}", file=sys.stderr)

# group canonical lines per gene, preserving order
genes_order = []
gene_block = {}   # gene_id -> dict(gline=cols, mrnas=[(cols, attr)], exon/cds per mrna)
cur_gene = None
mrna_of = {}      # mrna_id -> gene_id
data = defaultdict(lambda: dict(gline=None, mrnas=[], exon=defaultdict(list), cds=defaultdict(list)))

for ln in open(CANON):
    if ln.startswith('#') or '\t' not in ln:
        continue
    c = ln.rstrip('\n').split('\t')
    if len(c) < 9: continue
    ft = c[2]; attr = c[8]
    if ft == 'gene':
        gid = attr_id(attr); cur_gene = gid
        if gid not in data: genes_order.append(gid)
        data[gid]['gline'] = c
    elif ft == 'mRNA':
        mid = attr_id(attr); pid = attr_parent(attr)
        mrna_of[mid] = pid
        data[pid]['mrnas'].append(c)
    elif ft in ('exon', 'CDS'):
        pid = attr_parent(attr)
        g = mrna_of.get(pid)
        if g is None: continue
        data[g][ 'cds' if ft == 'CDS' else 'exon'][pid].append(c)

def fld(cols, seqid=None, start=None, end=None, ftype=None, attr=None):
    o = list(cols)
    if seqid is not None: o[0] = seqid
    if ftype is not None: o[2] = ftype
    if start is not None: o[3] = str(start)
    if end   is not None: o[4] = str(end)
    if attr  is not None: o[8] = attr
    return "\t".join(o)

n_graft = 0; n_genes_graft = 0
u5_total = u3_total = 0
out = open(OUT, "w")
out.write("##gff-version 3\n")

for gid in genes_order:
    blk = data[gid]
    gcols = blk['gline']
    if gcols is None: continue
    seqid = gcols[0]; strand = gcols[6]
    gene_min = int(gcols[3]); gene_max = int(gcols[4])
    gene_lines = []
    gene_grafted = False

    for mcols in blk['mrnas']:
        mid = attr_id(mcols[8])
        cds_cols = sorted(blk['cds'][mid], key=lambda x: int(x[3]))
        exon_cols = sorted(blk['exon'][mid], key=lambda x: int(x[3]))
        cds = [(int(x[3]), int(x[4])) for x in cds_cols]
        sig = (norm(seqid), strand, tuple(sorted(cds)))
        donor = pasa_sig.get(sig)

        # validate donor exons fully cover canonical CDS
        ok = False
        if donor:
            dex = donor[0]
            ok = all(any(de_s <= s and e <= de_e for de_s, de_e in dex) for s, e in cds)

        m_start = int(mcols[3]); m_end = int(mcols[4])
        children = []
        if donor and ok:
            dex = donor[0]
            five, three = derive_utrs(dex, cds, strand)
            if five or three:
                n_graft += 1; gene_grafted = True
                u5_total += sum(e - s + 1 for s, e in five)
                u3_total += sum(e - s + 1 for s, e in three)
                m_start = min(de[0] for de in dex); m_end = max(de[1] for de in dex)
                # full-transcript exons from donor
                for i, (s, e) in enumerate(sorted(dex), 1):
                    a = f"ID={mid}.exon{i};Parent={mid}"
                    children.append((s, 1, fld(exon_cols[0] if exon_cols else mcols,
                                                seqid=seqid, start=s, end=e, ftype='exon', attr=a)))
                # CDS verbatim (preserve phase)
                for x in cds_cols:
                    children.append((int(x[3]), 2, fld(x, seqid=seqid)))
                for i, (s, e) in enumerate(five, 1):
                    a = f"ID={mid}.utr5p{i};Parent={mid}"
                    children.append((s, 0, fld(mcols, seqid=seqid, start=s, end=e,
                                                ftype='five_prime_UTR', attr=a)))
                for i, (s, e) in enumerate(three, 1):
                    a = f"ID={mid}.utr3p{i};Parent={mid}"
                    children.append((s, 3, fld(mcols, seqid=seqid, start=s, end=e,
                                                ftype='three_prime_UTR', attr=a)))
        if not children:
            # unchanged: emit original exon + CDS lines
            for x in exon_cols: children.append((int(x[3]), 1, fld(x, seqid=seqid)))
            for x in cds_cols:  children.append((int(x[3]), 2, fld(x, seqid=seqid)))

        gene_min = min(gene_min, m_start); gene_max = max(gene_max, m_end)
        gene_lines.append(fld(mcols, seqid=seqid, start=m_start, end=m_end))
        children.sort(key=lambda t: (t[0], t[1]))
        gene_lines.extend(cl for _, _, cl in children)

    if gene_grafted: n_genes_graft += 1
    out.write(fld(gcols, seqid=seqid, start=gene_min, end=gene_max) + "\n")
    for gl in gene_lines:
        out.write(gl + "\n")

out.close()
print(f"mRNAs grafted with UTRs : {n_graft}")
print(f"genes grafted with UTRs : {n_genes_graft}")
print(f"total 5' UTR bp added   : {u5_total:,}")
print(f"total 3' UTR bp added   : {u3_total:,}")
print(f"wrote {OUT}")
