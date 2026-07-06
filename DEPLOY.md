# Web deploy — Railway + Supabase + OpenRouter

Hybrid design: **BLAST runs locally**; JBrowse 2 + the agent run in the cloud.

```
Local machine            Supabase Storage           Railway
-------------            ----------------           -------
BLAST DBs (genome,       genome + track files  <--  jbrowse  (nginx, basic auth)
proteins) ── run_blast   (range-request HTTP)       agent    (FastAPI, OpenRouter)
   │                     agent data (gff/func/rag)    │
   └── POST hits ───────────────────────────────────►┘  (/blast-results → JBrowse link)
```

Nothing host-specific is baked into the cloud: container paths default to
`/data` (env-overridable); all external URLs come from env at config-build time.

## 0. One-time: build the data bundle (local)

```bash
conda activate kallisto_env
bash scripts/prep_web_bundle.sh          # -> build/{genome,tracks,blast/db,agent}
```

Produces (all canonical `_np1212`):
- `build/genome/final_assembly.fa.gz` (+ .fai .gzi)  → Supabase (JBrowse refseq)
- `build/tracks/*`  genes, stringtie, repeats, ncRNA, 3× coverage, 2× Nvit  → Supabase
- `build/blast/db/spalangia_{genome,proteins}.*`  → **stays local** (local BLAST).
  The agent image now bundles blast+ and exposes `POST /blast` (server-side, no
  LLM), but the cloud service does not ship these DBs, so `/blast` reports the DB
  absent there — cloud BLAST stays on the host via `run_blast.sh` → `/blast-results`.
  To enable server-side BLAST in the cloud, mount the DBs and set `BLAST_DB_DIR`.
- `build/agent/{gff.sqlite,functional.sqlite,rag/chunks.jsonl}`  → Supabase (agent pulls on boot)

## 1. Upload data to Supabase

```bash
export SUPABASE_URL=https://YOURPROJECT.supabase.co
export SUPABASE_SERVICE_KEY=...          # service_role key
bash supabase/upload.sh
# prints:  TRACK_BASE=...   DATA_BASE=...   (same public bucket base)
```

## 2. Generate the JBrowse config (public URLs only)

```bash
TRACK_BASE="<from step 1>" \
AGENT_BASE="https://<your-agent-domain>" \
CONFIG_OUT=jbrowse/config.json \
  python scripts/build_jbrowse_config_web.py
```

`AGENT_BASE` is the Railway agent domain (set it after step 4, then rebuild the
jbrowse service — or set a planned domain up front).

## 3. Set the shared password

```bash
SITE_USER=spalangia SITE_PASSWORD='your-pass' bash jbrowse/gen_htpasswd.sh
```

Use the **same** `SITE_USER`/`SITE_PASSWORD` for the agent env (step 4) so the
local BLAST client and `/chat` authenticate consistently.

## 4. Deploy on Railway (two services, one repo)

Create a Railway project, then add two services from this repo:

| Service | Root directory | Exposed port | Volume |
|---|---|---|---|
| jbrowse | `jbrowse/` | 8080 | — |
| agent   | `agent/`   | 8000 | mount at `/data` (caches pulled data) |

Each dir has a `Dockerfile` + `railway.json`. Set the agent's target port to
8000 and jbrowse's to 8080 in service settings.

**Agent env vars** (from `.env.example`):
`OPENROUTER_API_KEY`, `OPENROUTER_MODEL`, `DATA_BASE` (= step-1 base),
`JBROWSE_URL`, `SITE_URL`, `CORS_ORIGINS` (= jbrowse domain),
`SITE_USER`, `SITE_PASSWORD`, `ASSEMBLY_NAME=spalangia_cameroni`.

```bash
railway up            # from each service dir, or connect the GitHub repo
```

After the agent gets its domain, redo step 2 with the real `AGENT_BASE` and
redeploy jbrowse so the live `blast_hits` track resolves.

## 5. Use it

- Browser: `https://<jbrowse-domain>/` → basic-auth → genome + tracks.
- Agent docs: `https://<agent-domain>/docs`, health: `/health`.
- Local BLAST → cloud visualization:

```bash
export AGENT_URL=https://<agent-domain> SITE_PASSWORD='your-pass'
bash local-blast/run_blast.sh query.fa blastn      # or tblastn/blastp/blastx
# -> prints a JBrowse deep link; hits appear as the blast_hits track
```

## Local smoke test (optional, before cloud)

```bash
docker compose -f docker-compose.web.yml up --build agent
curl -s localhost:8000/health | jq
```

## Notes / caveats

- **Storage size**: genome+tracks ≈ 0.2 GB, agent data ≈ 0.4 GB. Exceeds the
  Supabase free 1 GB only modestly; a paid tier is safer with headroom.
- **Cold-start fetch**: the agent downloads ~0.4 GB on first boot (cached on the
  volume). Set `FETCH_ASSEMBLY=0` to skip the 160 MB FASTA (loses `contig_stats`
  GC%/N%, keeps gene/functional tools).
- **GtfTabixAdapter**: the StringTie track uses it; confirm it renders on first
  load. If a JBrowse build lacks it, convert the GTF to sorted GFF3 + tabix.
- **blast_hits track** is a single "latest upload" overwrite (fine for a small
  shared group). The GET endpoint that serves it is intentionally unauthenticated
  so the browser can fetch it; the POST that writes it requires the password.
- **OpenRouter model**: `anthropic/claude-sonnet-4` is the default; change
  `OPENROUTER_MODEL` to any OpenRouter id.
