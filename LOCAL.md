# Fully-local stack (no Supabase, no Railway)

Everything reads the locally-built bundle in `./build`. Runs alongside the older
local stack (which owns ports 8080/8000) — this one uses **8090 / 8001**.

## Run

```bash
# 1. (optional) enable the AI agent chat: put your key in .env
echo 'OPENROUTER_API_KEY=sk-or-...' >> .env

# 2. bring it up
docker compose -f docker-compose.local.yml up -d --build

# 3. open the browser
#    genome browser : http://localhost:8090
#    agent health   : http://localhost:8001/health
#    agent API docs : http://localhost:8001/docs
```

## What runs

| Service | Port | Notes |
|---|---|---|
| jbrowse | 8090 | JBrowse 2 app + all tracks, no auth (local) |
| agent   | 8001 | FastAPI: /chat, tools, /blast-results |
| BLAST   | host | `local-blast/run_blast.sh` (needs blast+ on PATH, e.g. `conda activate kallisto_env`) |

Tracks served: genes, StringTie, repeats, ncRNA, 3× coverage, 2× Nvit, blast_hits.
Agent tools (all verified working locally): gff_query, functional_lookup,
contig_stats, coords_to_jbrowse_url, retrieve, latest_blast_results.

## Local BLAST → browser

```bash
conda activate kallisto_env          # provides blastn/tblastn/blastp/blastx
export AGENT_URL=http://localhost:8001
bash local-blast/run_blast.sh query.fa blastn
# hits appear as the blast_hits track; the script prints a JBrowse deep link
```

## Stop

```bash
docker compose -f docker-compose.local.yml down
```

## Notes

- The agent `/chat` needs `OPENROUTER_API_KEY`; all other tools/endpoints work
  without it.
- Genome (160M) and gff.sqlite (185M) exceed Supabase free-tier's 50 MB/file
  cap — this local stack serves them directly, so no size limit applies.
