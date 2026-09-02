# Spalangia cameroni Genome Browser

Self-hosted JBrowse 2 + BLAST + Claude-API agent for the *S. cameroni* assembly.

## Quick start (laptop)

```bash
git clone <this-repo> spalangia-browser
cd spalangia-browser

# 1. Get the data bundle (built on the lab host, see scripts/)
rsync -avz user@bi-delllinux:/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly/webapp/build/webapp_data.tar.zst .
tar --zstd -xf webapp_data.tar.zst   # extracts to ./data/

# 2. Configure Claude API key
cp .env.example .env
$EDITOR .env   # paste your ANTHROPIC_API_KEY

# 3. Launch
docker compose up -d

# 4. Open
open http://localhost:8080        # JBrowse
open http://localhost:4567        # SequenceServer (BLAST)
open http://localhost:8000/docs   # Agent FastAPI docs
```

## Data layout (after extracting bundle)

```
data/
  jbrowse/         # static JBrowse 2 site + config.json + tracks/
  blast/db/        # makeblastdb outputs
  agent/
    gff.sqlite     # gffutils DB indexing all annotation GFFs
    rag/           # BM25 + (optional) embedding index
```

## What it does

- **JBrowse 2** — interactive browser, tracks for contigs, repeats (RepeatMasker), BUSCO loci, BRAKER3 genes, decontam evidence, RNA-Seq coverage, *N. vitripennis* protein homology (tblastn).
- **SequenceServer** — BLAST against the genome and BRAKER3-predicted proteins. Hits deep-link into JBrowse.
- **Agent** — Claude-API orchestrator with tools: `gff_query`, `blast`, `coords_to_jbrowse_url`, `retrieve` (RAG over project reports).

Localhost-only. No auth. No public exposure.

## Building the bundle (lab host side)

On `bi-delllinux`:

```bash
cd /mnt/data/Projects/Elad_Chiel/wasp_genome_assembly/webapp
bash scripts/prep_tracks.sh         # bgzip + tabix all GFFs/BAMs
bash scripts/build_jbrowse_config.sh
bash scripts/build_blast_dbs.sh
python scripts/build_rag_index.py
bash scripts/package_bundle.sh      # → build/webapp_data.tar.zst
```

Re-run after each annotation update (e.g., once Phase 7.4 BRAKER3 finishes).

### Nvit protein homology track (tblastn)

Builds the `nvit_tblastn` JBrowse track from a tblastn (Nvit proteins vs.
assembly) outfmt-7 result. Requires `bgzip`/`tabix` on PATH
(`conda activate kallisto_env`):

```bash
bash scripts/prep_tblastn_track.sh [tblastn_result.txt]   # → data/jbrowse/tracks/nvit_tblastn.gff.gz
```

Converts via `scripts/tblastn_to_gff3.py`, then sort + bgzip + tabix.
`config.json` already references the track; just re-run after the tblastn
search finishes to refresh it.
