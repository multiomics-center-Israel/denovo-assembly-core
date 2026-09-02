# Plan — JBrowse 2 + BLAST + AI Agent Web App for *Spalangia cameroni* Genome

## Context

The *S. cameroni* assembly is now feature-complete through Phase 7.1 (RepeatModeler/RepeatMasker; 658.88 Mb hybrid assembly, BUSCO 90.1%, QV 45.6, 43.01% repeat-masked) and Phase 7.4 BRAKER3 gene predictions are pending. The user wants a self-hosted **web app** that wraps the assembly so collaborators (and the user) can:

1. Browse the genome interactively (tracks: contigs, repeats, future BRAKER3 genes, RNA-Seq coverage, BUSCOs, decontam evidence).
2. Run BLAST searches against the assembly + auxiliary databases without using the CLI.
3. Ask natural-language questions about the genome ("which contigs harbor LTR Gypsy clusters >50 kb?", "show me genes near BUSCO marker X", "is contig N likely contamination?") via an LLM agent that reads project artifacts.

**Deployment target (decided 2026-05-28):** The web app runs on the **user's laptop**, not on `bi-delllinux`. The lab host has limited internet — Claude API calls would be flaky from there. The lab host's role is reduced to: (a) preparing and packaging indexed track files, (b) staging a portable tarball the laptop pulls via `rsync` over SSH. The laptop runs the Docker stack and reaches Claude over its own internet connection.

**Launch gating (decided 2026-05-28):** Browser build is deferred until **Phase 7.4 BRAKER3** has produced gene predictions. The intervening time on the lab host is spent on (a) Phase 7.3 RNA-Seq alignment → 7.4 BRAKER3 → 7.5 functional annotation, and (b) authoring the prep/packaging scripts so they're ready to execute the moment 7.4 lands.

---

## 1. Literature Review

### 1.1 Genome browser platforms — landscape

The dominant browser choices for a custom non-model insect database are **JBrowse 2**, **Apollo** (built on JBrowse), the **UCSC Genome Browser** (hosted or local mirror), and **IGV / igv.js**. JBrowse 2 has emerged as the de facto modular standard for genome-database sites since Diesh et al. (2023): it is plugin-extensible, runs as a static-site SPA backed by indexed flat files (FASTA + BAI/CSI/TBI), and supports synteny, structural variation, and whole-genome dotplots not present in JBrowse 1 or GBrowse. The 2024 Current Protocols protocol (Diesh, 2024) is now the canonical recipe for standing up an instance.

**Viewpoint A — JBrowse 2 wins on portability and ecosystem.** It needs only a static file server (no database, no Java runtime) and reuses indexed bioinformatics formats (CRAM/BAM, VCF.gz/TBI, GFF3.gz/TBI). The plugin ecosystem includes track-hubs, comparative views, and the *MsaView* for protein alignments. For a small lab with no full-time webmaster, this minimizes maintenance burden (Diesh et al., 2023; Diesh, 2024).

**Viewpoint B — Apollo if community annotation is a goal.** Web Apollo (Lee et al., 2013) and later Apollo 3 / *Apollo: Democratizing genome annotation* (Dunn et al., 2019) extend JBrowse with collaborative real-time annotation editing ("Google Docs for genomes"). Used by HGD, i5K, and most insect genome consortia. Cost: a Postgres backend, a Java application server (Grails), authentication, and dramatically more sysadmin overhead. Apollo is overkill if the team is one user + occasional collaborators reading only.

**Viewpoint C — UCSC Assembly Hubs as a "no-server" alternative.** A UCSC Genome Browser *Assembly Hub* lets users host BAI/BB/BW files on a public-readable URL and load them as a custom assembly into the UCSC site — no local web app. Strength: zero infrastructure. Weakness: requires a publicly reachable HTTPS endpoint with byte-range requests, and the user loses local control + customization. Not viable for a LAN-only deployment.

**Viewpoint D — IGV / igv.js as embeddable visualizer.** IGV (Robinson et al., 2011) and the JavaScript port igv.js are excellent for *visualization-only*, embeddable widgets — but lack a multi-track configuration UI, sessions, search, and the synteny views JBrowse 2 has. Suitable as a component inside another app, not as the user-facing portal.

The Hymenoptera Genome Database (Walsh et al., 2022; Elsik et al., 2016) — the canonical precedent for parasitoid-wasp genomes including *Nasonia vitripennis* — combines **JBrowse 2** (browsing), **Apollo** (curation), **SequenceServer** (BLAST), and **HymenopteraMine** (InterMine data warehouse). This is the reference architecture for any new hymenopteran genome portal.

### 1.2 BLAST UIs

For a custom BLAST front-end, **SequenceServer** (Priyam et al., 2019) is the standard. It is a Ruby/Sinatra app over BLAST+, used by ~50 community databases. Strengths: zero-config indexing of `makeblastdb` outputs, hit-result table with built-in links to genome browsers via configurable URL templates (so a BLAST hit can deep-link into JBrowse 2 at the matched coordinates), and FASTA download per hit. Alternatives are **NCBI BLAST web service** (no custom DB), **Galaxy** (heavyweight workflow platform), and roll-your-own FastAPI wrappers (loses curl-tested UI). SequenceServer is the lowest-friction choice and is what HGD itself uses.

### 1.3 LLM agents for genome data

This is the rapidly-evolving frontier. Three architectural patterns appear in the 2024-2026 literature:

**Pattern 1 — Tool-using agent over bioinformatics CLIs.** *BioInformatics Agent* (BIA; Xin et al., 2024) wraps an LLM around shell tools (BLAST, samtools, bedtools) with a planner that decomposes user questions into tool calls. Strength: handles open-ended workflows. Weakness: brittle, expensive in tokens, no provenance guarantees, and shell-injection risk if not sandboxed.

**Pattern 2 — Retrieval-augmented generation (RAG) over indexed annotations.** *GeneRAG* (Wang et al., 2024) embeds gene and annotation text into a vector DB and retrieves relevant chunks at query time. Reported +39 % gene QA accuracy over base GPT-4. *Boosting GPT for genomics* (Liu et al., 2025) used RAG over 190 M variant annotations. Strength: grounded answers with citations; cheap inference. Weakness: tied to text-style annotations — does not natively answer quantitative range queries ("contigs >1 Mb with >50% repeats").

**Pattern 3 — Structured-data NL→query agents.** *gffutilsAI* (preprint, 2025) compiles natural-language questions into `gffutils` Python queries against a GFF SQLite database, returning structured results. *GeneWhisperer* (preprint, 2025) does the same for manual gene annotation. Strength: exact, reproducible answers on structured data. Weakness: question coverage is bounded by what the underlying library can express.

**Viewpoint E — Hybrid is the sane choice.** Real questions span all three: a user asking "show me LTR-rich contigs near BUSCO duplicates" needs structured query (#3) on the GFF + structured query on the BUSCO table, and natural-language summary (#1). A user asking "what is this gene family known for" needs RAG (#2) over literature. A single-pattern agent will frustrate. Build the agent as a tool-using orchestrator (#1) whose tools include a GFF/SQLite query helper (#3) and a RAG retriever (#2) over a small literature/README corpus.

**Counter-viewpoint F — Skip the agent for v1.** Several recent commentaries (e.g., the Rancho Biosciences review, 2025) emphasize that LLM hallucination on quantitative bio data remains a real risk and that grounded structured-query interfaces (HymenopteraMine, BioMart) outperform free-text LLMs on most reproducible-research tasks. A defensible v1 ships JBrowse 2 + SequenceServer and *defers* the agent until BRAKER3 gene predictions exist (otherwise the agent has nothing to answer about beyond contigs and repeats).

### 1.4 Synthesis for this project

- **Architecture template:** copy the HGD pattern (JBrowse 2 + SequenceServer) sized down for a single-host LAN deployment, with Apollo deferred unless community editing becomes a need.
- **Agent:** build the orchestrator scaffolding now and switch it on once Phase 7.4 BRAKER3 has produced a real gene set; agent tools are (a) a JBrowse-coordinate-aware GFF query helper, (b) a BLAST-result interpreter, (c) a RAG retriever over the project's `RESULTS.md`, decontam reports, and a small Hymenoptera literature corpus.
- **Deployment:** Docker Compose on the LAN, behind a simple nginx reverse-proxy with basic auth. No public exposure (consistent with `Open ports: none`).

### References (APA)

- Diesh, C. (2024). Setting up the JBrowse 2 genome browser. *Current Protocols*, *4*(9), e1120. https://doi.org/10.1002/cpz1.1120
- Diesh, C., Stevens, G. J., Xie, P., De Jesus Martinez, T., Hershberg, E. A., Leung, A., Guo, E., Dider, S., Zhang, J., Bridge, C., Hogue, G., Duncan, A., Morgan, M., Flores, T., Bimber, B. N., Haw, R., Cain, S., Buels, R. M., Stein, L. D., & Holmes, I. H. (2023). JBrowse 2: a modular genome browser with views of synteny and structural variation. *Genome Biology*, *24*, 74. https://doi.org/10.1186/s13059-023-02914-z
- Buels, R., Yao, E., Diesh, C. M., Hayes, R. D., Munoz-Torres, M., Helt, G., Goodstein, D. M., Elsik, C. G., Lewis, S. E., Stein, L., & Holmes, I. H. (2016). JBrowse: a dynamic web platform for genome visualization and analysis. *Genome Biology*, *17*, 66. https://doi.org/10.1186/s13059-016-0924-1
- Skinner, M. E., Uzilov, A. V., Stein, L. D., Mungall, C. J., & Holmes, I. H. (2009). JBrowse: a next-generation genome browser. *Genome Research*, *19*(9), 1630–1638. https://doi.org/10.1101/gr.094607.109
- Lee, E., Helt, G. A., Reese, J. T., Munoz-Torres, M. C., Childers, C. P., Buels, R. M., Stein, L., Holmes, I. H., Elsik, C. G., & Lewis, S. E. (2013). Web Apollo: a web-based genomic annotation editing platform. *Genome Biology*, *14*(8), R93. https://doi.org/10.1186/gb-2013-14-8-r93
- Dunn, N. A., Unni, D. R., Diesh, C., Munoz-Torres, M., Harris, N. L., Yao, E., Rasche, H., Holmes, I. H., Elsik, C. G., & Lewis, S. E. (2019). Apollo: democratizing genome annotation. *PLOS Computational Biology*, *15*(2), e1006790. https://doi.org/10.1371/journal.pcbi.1006790
- Priyam, A., Woodcroft, B. J., Rai, V., Moghul, I., Munagala, A., Ter, F., Chowdhary, H., Pieniak, I., Maynard, L. J., Gibbins, M. A., Moon, H., Davis-Richardson, A., Uludag, M., Saremi, N. F., Bürki, S., Wu, J., Pevzner, S., Wright, K., Crosier, B., … Wurm, Y. (2019). Sequenceserver: a modern graphical user interface for custom BLAST databases. *Molecular Biology and Evolution*, *36*(12), 2922–2924. https://doi.org/10.1093/molbev/msz185
- Walsh, A. T., Triant, D. A., Le Tourneau, J. J., Shamimuzzaman, M., & Elsik, C. G. (2022). Hymenoptera Genome Database: new genomes and annotation datasets for improved GO enrichment and orthologue analyses. *Nucleic Acids Research*, *50*(D1), D1032–D1039. https://doi.org/10.1093/nar/gkab1018
- Elsik, C. G., Tayal, A., Diesh, C. M., Unni, D. R., Emery, M. L., Nguyen, H. N., & Hagen, D. E. (2016). Hymenoptera Genome Database: integrating genome annotations in HymenopteraMine. *Nucleic Acids Research*, *44*(D1), D793–D800. https://doi.org/10.1093/nar/gkv1208
- Robinson, J. T., Thorvaldsdóttir, H., Winckler, W., Guttman, M., Lander, E. S., Getz, G., & Mesirov, J. P. (2011). Integrative genomics viewer. *Nature Biotechnology*, *29*(1), 24–26. https://doi.org/10.1038/nbt.1754
- Wang, M., Yu, F., Xu, M., Zhang, L., Yang, J., Wang, B., Liu, Y., Sun, F., Zhang, Q., Liu, Y., Yao, H., Xu, X., Liu, X., Zhang, X., & Liu, J. (2024). GeneRAG: Enhancing large language models with gene-related task by retrieval-augmented generation [Preprint]. *bioRxiv*. https://doi.org/10.1101/2024.06.24.600176
- Xin, Q., Kong, Y., Zhang, X., Ji, Y., Wang, X., & Chen, W. (2024). BioInformatics Agent (BIA): Unleashing the power of large language models to reshape bioinformatics workflow [Preprint]. *bioRxiv*. https://doi.org/10.1101/2024.05.22.595240
- Liu, B., Zhang, K., Huang, J., Yu, X., Wang, J., & Yang, J. (2025). Boosting GPT models for genomics analysis: generating trusted genetic variant annotations and interpretations through RAG and fine-tuning. *Briefings in Bioinformatics*. https://www.ncbi.nlm.nih.gov/pmc/articles/PMC11842050/
- Rancho Biosciences. (2025, May 24). *How large language models are reshaping bioinformatics*. https://ranchobiosciences.com/blog/large-language-models-and-bioinformatics

(Preprints flagged for the GeneWhisperer and gffutilsAI tools — listed in the search results — are omitted from APA pending verified author lists.)

---

## 2. Recommended Architecture

### 2.1 Two-host split

- **Lab host (`bi-delllinux`)** — *staging only*. Builds bgzip/tabix-indexed tracks from existing files, produces a `webapp_data.tar.zst` bundle (~3-5 GB), exposes it via the user's existing SSH access.
- **User's laptop** — *runtime*. Pulls the bundle, runs Docker Compose, talks to Claude API over the laptop's internet. All user-facing endpoints bind to `localhost`; no auth needed because nothing listens on the LAN.

### 2.2 Laptop services (Docker Compose, `localhost`-only)

| Service | Image / build | Purpose | Mounts |
|---|---|---|---|
| `jbrowse` | nginx + static JBrowse 2 build | Static SPA serving JBrowse 2 + assembly data | `./data/jbrowse:ro` |
| `blast` | `wurmlab/sequenceserver:latest` | SequenceServer UI over BLAST+ | `./data/blast/db:ro` |
| `agent` | Python 3.13 + FastAPI (build local) | Claude-API orchestrator + GFF SQLite + RAG retriever | `./data/agent:ro`, `./cache` |

Ports bound to `127.0.0.1` only — `jbrowse:8080`, `blast:4567`, `agent:8000`. No nginx, no auth, no TLS. User opens `http://localhost:8080` in their laptop browser.

**Data preparation (runs on `bi-delllinux` after Phase 7.4 completes; reuses existing conda envs):**

All output goes to `webapp/build/data/` on the lab host, then `tar --zstd -cf webapp_data.tar.zst data/` for transport.

1. **FASTA prep:** `bgzip -k final_assembly.fa` + `samtools faidx final_assembly.fa.gz` → `data/jbrowse/genome/`.
2. **Repeats track:** sort + bgzip + tabix `annotation/repeats/final_assembly.fa.out.gff` → `data/jbrowse/tracks/repeats.gff.gz`.
3. **BUSCO track:** convert `qc/busco_results/run_hymenoptera_odb10/full_table.tsv` → BED12 → bgzip + tabix.
4. **Decontam evidence track:** convert hybrid-rescue per-contig table → BED → bgzip + tabix.
5. **Coverage tracks:** `samtools sort` + `samtools index` `decontamination/mapped.bam` → `data/jbrowse/tracks/`. (Optionally downsampled BAM to keep bundle size manageable.)
6. **BRAKER3 track (required for launch):** sort + bgzip + tabix `annotation/braker/braker.gff3`.
7. **Functional annotation track (Phase 7.5):** bgzip + tabix the functional-annotation GFF.
8. **JBrowse config:** `jbrowse add-assembly`, `jbrowse add-track` calls scripted into `scripts/build_jbrowse_config.sh`. Output `data/jbrowse/config.json` is included in the bundle.

**BLAST DB prep (on lab host, bundled):**

- Reuse `annotation/repeats/spalangia_db.{nhr,nin,nsq}` (already built).
- `makeblastdb -in final_assembly.fa -dbtype nucl -out data/blast/db/spalangia_genome`.
- Protein DB from BRAKER3 predicted proteins: `makeblastdb -in annotation/braker/braker.aa -dbtype prot -out data/blast/db/spalangia_proteins`.

**Transport:** `rsync -avz bi-delllinux:webapp/build/webapp_data.tar.zst ./` on the laptop, then `tar --zstd -xf webapp_data.tar.zst`.

**Agent (FastAPI + Anthropic SDK):**

- Endpoints: `POST /chat` (streaming), `POST /search` (BLAST proxy).
- Tools registered via Anthropic tool-use:
  - `gff_query(filters)` — runs against a SQLite of all GFFs (gffutils-style).
  - `blast(seq, db, program)` — proxies SequenceServer's REST endpoint.
  - `coords_to_jbrowse_url(contig, start, end)` — returns a deep link.
  - `retrieve(query)` — RAG over `RESULTS.md`, decontam reports, repeats `.tbl`, and a small Hymenoptera lit corpus.
- LLM call uses Claude API with **prompt caching** on the static system prompt + corpus chunks (project conventions; see [[claude-api]] guidance).
- Citations are required in every answer — agent must return tool-result identifiers, not free-text claims.

**Auth:** none — `localhost`-only binding means nothing on the LAN can reach the services. The Claude API key lives in `webapp/.env` on the laptop, never on the lab host or in the bundle.

---

## 3. Critical Files / Paths to Create

**On `bi-delllinux` (build & bundle, authored *before* Phase 7.4 lands so the run-it-the-moment-BRAKER3-finishes button exists):**
- `webapp/scripts/prep_tracks.sh` — bgzip + sort + tabix for repeats, BUSCO, decontam, BRAKER3, functional GFFs
- `webapp/scripts/build_jbrowse_config.sh` — runs `jbrowse add-assembly` / `add-track`
- `webapp/scripts/build_blast_dbs.sh` — `makeblastdb` for nucleotide genome + BRAKER protein set
- `webapp/scripts/build_rag_index.py` — offline index over `RESULTS.md`, decontam reports, `annotation/repeats/final_assembly.fa.tbl`, hybrid-rescue summaries
- `webapp/scripts/package_bundle.sh` — `tar --zstd -cf webapp_data.tar.zst data/`

**Portable webapp tree (single git repo, cloned on the laptop):**
- `webapp/docker-compose.yml`
- `webapp/.env.example` — `ANTHROPIC_API_KEY=` placeholder
- `webapp/agent/Dockerfile`
- `webapp/agent/main.py` — FastAPI app, streaming `/chat`
- `webapp/agent/tools/gff_query.py` — gffutils SQLite query helper
- `webapp/agent/tools/blast_client.py` — proxies SequenceServer REST
- `webapp/agent/tools/retriever.py` — BM25 over the RAG index
- `webapp/agent/system_prompt.md` — cached system prompt with assembly-specific context
- `webapp/README.md` — laptop-side setup, ~10 lines

**Reuses existing artifacts (read-only inputs):** `final_assembly.fa`, `annotation/repeats/final_assembly.fa.out.gff`, `annotation/repeats/final_assembly.fa.tbl`, `annotation/repeats/spalangia_db.*`, `annotation/braker/braker.gff3` (pending 7.4), `annotation/braker/braker.aa` (pending 7.4), `decontamination/mapped.bam`, `qc/busco_results/run_hymenoptera_odb10/full_table.tsv`, `RESULTS.md`, `pipeline_report.html`.

## 4. Phasing (revised — gated on Phase 7.4)

**Pre-7.4 (do now, no blocker):**
- **P0a (½ day):** Scaffold `webapp/` directory tree on `bi-delllinux`; write `docker-compose.yml`, `agent/Dockerfile`, FastAPI skeleton with stubbed tools. No data prep yet.
- **P0b (1 day):** Write all `webapp/scripts/*.sh` track-prep scripts and dry-run them against the *currently-available* tracks (repeats, BUSCO, decontam, coverage). Confirm the bundle builds cleanly minus BRAKER3 placeholders.
- **P0c (½ day):** RAG index build over present artifacts; verify `retriever.py` returns sane chunks.

**Post-7.4 (executes after BRAKER3 + functional annotation land):**
- **P1 (½ day):** Re-run `prep_tracks.sh` + `build_blast_dbs.sh` to include BRAKER3 GFF + protein DB; run `package_bundle.sh` → `webapp_data.tar.zst`.
- **P2 (½ day, on laptop):** `git clone webapp/ && rsync webapp_data.tar.zst && tar -xf && cp .env.example .env && set ANTHROPIC_API_KEY && docker compose up`.
- **P3 (½ day, on laptop):** Wire up agent's Anthropic tool-use loop, prompt caching, and end-to-end smoke test.

## 5. Verification

On the laptop, after `docker compose up`:
- `curl -I http://localhost:8080` → 200 from the JBrowse 2 static server.
- Browser: navigate to a known contig (e.g. the longest contig from `final_assembly.fa.fai`) and confirm repeats + BUSCO + BRAKER3 + coverage tracks render.
- BLAST UI at `http://localhost:4567`: paste a 200 bp probe known to hit a BUSCO locus; confirm hit table appears and the "view in browser" link jumps to the right contig in JBrowse.
- Agent: `curl -X POST localhost:8000/chat -d '{"q":"Which contigs have >50% repeat coverage and harbor at least one BUSCO duplicate?"}'` — confirm the response cites tool results (contig IDs from `gff_query` + `full_table.tsv`) and does not hallucinate.
- Acceptance: the user can browse the genome, run a BLAST search whose results deep-link back into the browser, and get one structured agent answer with verifiable citations to file paths inside the bundle.

## 6. Out of scope (explicit)

- Apollo collaborative editing.
- Public-internet exposure / TLS / LAN access (deliberately localhost-only on the laptop).
- HymenopteraMine-style data warehouse.
- Synteny views vs *Nasonia vitripennis* (deferred — would need a second indexed assembly + a `comparative` plugin config).

## 7. Side note — Kaiju OOM (not part of this plan)

While planning was in progress, the Kaiju refseq classifier OOMed a second time (RSS reached 93 GB; `MemAvailable` fell to 7.8 GB; process killed). The 98 GB FMI is too close to system RAM headroom under any concurrent load. After exiting plan mode, options to discuss separately: (a) split DB into smaller `kaiju-makedb -s viruses,bacteria` partitions, (b) use Kaiju's `--mem-mapped`/swap-friendly mode, (c) skip Kaiju for reads since the alignment-based decontam already passed, (d) reduce thread count to 8 (smaller per-thread state).
