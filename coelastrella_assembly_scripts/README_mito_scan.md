# Step 30 — Mito recovery scan of dropped contigs

**Question (from supervisor):** Did we discard a real mitochondrial contig during
assembly cleanup (BlobTools / purge_dups / Tiara)?

## What the script does
1. Collects every contig dropped at each stage into one labelled multifasta
   (`dropped_all.fa`), tagging each with the stage that removed it.
   - BlobTools-removed = in `Coelastrella_pilon.fasta` (64) but not in `Coelastrella_decontaminated.fasta` (62)
   - purge_dups-removed = `hap.fa` minus the contigs in `rescue_contigs.txt`
   - Tiara-removed = in polypolish (29) but not in `Coelastrella_FINAL.fa` (28)
2. Annotates each contig (length, GC, ONT cov, Illumina cov, BlobTools taxonomy)
   by joining to the existing `summary_full.tsv`.
3. **`diamond blastx` vs nr** — the decisive screen. nr contains all mitochondrial
   proteins with taxonomy; a real mito contig will hit cox1/nad/cob/atp genes.
4. **`blastn` vs the 8 Coelastrella nuclear genomes** — a strong hit means the
   contig is nuclear/haplotig and was correctly dropped.
5. **`blastn` vs green-algal mitochondrial references** (downloaded via Entrez) —
   targeted nucleotide confirmation.
6. Writes **`dropped_contigs_verdict.tsv`** with a verdict per contig.

## Databases used (all already on the cluster)
- `NR.dmnd` — `/gpfs0/system/conda/DataBases/Blast/NR/DIAMOND/NR.dmnd`
- 8 Coelastrella genomes — `.../Centrifuge/db_nt_2026/extra_genomes/coelastrella/coelastrella_all_genomes.fna`
- mito references — downloaded fresh (Step 5; needs internet on the node)

## How to run
```bash
cd /gpfs0/bioinfo/projects/Multiomics_Center/Inna_Khozin_Goldberg/00.Coelastrella_genomic_sequencing
qsub 99.scripts_neatseq/30_mito_recovery_scan.sh     # or wherever you keep scripts
```
Before submitting, check **one** variable: `ENV_DIAMOND` (line ~70). Set it to the
name of your diamond conda env. If Step 5's Entrez download can't run on compute
nodes, run that block on the login node, or drop a mito FASTA at
`12.mito_recovery_scan/mito_refs.fa` and rerun — Step 3 (diamond vs nr) already
answers the mito question on its own.

## How to read `dropped_contigs_verdict.tsv`
- `>>> CANDIDATE MITOCHONDRION` — hits mito genes/refs and is NOT just nuclear →
  inspect and consider rescuing.
- `MITO-LIKE but matches nuclear genome` — likely a NUMT (nuclear copy of mito DNA),
  not a real organelle contig.
- `nuclear / haplotig (correctly dropped)` — strong match to a Coelastrella nuclear
  genome; expected to be dropped.
- `likely contaminant (taxon)` — best nr hit is bacterial/fungal/non-algal.
- `unknown / low-complexity` — no informative hit.

## What to expect (important)
Per `01.assembly_workflow` §23 and script `26b`, the only mito-flagged piece so far
(`ptg000037l`, 2.4 kb) turned out to be a **plastid** fragment. So the most likely
result is that **no full mitochondrion was assembled** from the ONT data. If the
scan finds no candidate, the right next step is **dedicated organelle assembly**
(GetOrganelle / MitoHiFi with a green-algal mito seed, or map ONT+Illumina reads to
a reference mito and assemble the fished reads) — far more sensitive than sifting
discarded contigs.
