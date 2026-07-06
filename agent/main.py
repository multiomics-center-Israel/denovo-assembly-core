import json
import os
import secrets
from pathlib import Path

from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import PlainTextResponse, StreamingResponse
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from openai import OpenAI
from pydantic import BaseModel

SITE_USER = os.environ.get("SITE_USER", "spalangia")
SITE_PASSWORD = os.environ.get("SITE_PASSWORD", "")  # unset -> auth disabled
_basic = HTTPBasic(auto_error=False)


def require_auth(creds: HTTPBasicCredentials | None = Depends(_basic)):
    """Shared-password gate. No-op when SITE_PASSWORD is unset."""
    if not SITE_PASSWORD:
        return
    ok = creds is not None and \
        secrets.compare_digest(creds.username, SITE_USER) and \
        secrets.compare_digest(creds.password, SITE_PASSWORD)
    if not ok:
        raise HTTPException(
            status.HTTP_401_UNAUTHORIZED, "unauthorized",
            headers={"WWW-Authenticate": "Basic"})

from tools import (blast_results, blast_run, contig_stats, functional_lookup,
                   gff_query, retriever, sql_query)

MODEL = os.environ.get("OPENROUTER_MODEL", "anthropic/claude-sonnet-4")
SYSTEM_PROMPT_PATH = Path("/app/system_prompt.md")

client = OpenAI(
    base_url=os.environ.get("OPENROUTER_BASE_URL", "https://openrouter.ai/api/v1"),
    api_key=os.environ.get("OPENROUTER_API_KEY", ""),
    default_headers={
        "HTTP-Referer": os.environ.get("SITE_URL", "http://localhost:8080"),
        "X-Title": "Spalangia genome agent",
    },
)

app = FastAPI(title="Spalangia genome agent")
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.environ.get("CORS_ORIGINS", "*").split(","),
    allow_methods=["*"],
    allow_headers=["*"],
)


def _tool(name, description, properties, required):
    return {
        "type": "function",
        "function": {
            "name": name,
            "description": description,
            "parameters": {
                "type": "object",
                "properties": properties,
                "required": required,
            },
        },
    }


TOOLS = [
    _tool("gff_query",
          "Query gene models (gffutils SQLite): gene/mRNA/exon/CDS/tRNA by type, "
          "optionally restricted to a contig + coordinate range.",
          {"feature_type": {"type": "string", "description": "gene, mRNA, exon, CDS, tRNA"},
           "contig": {"type": "string"},
           "start": {"type": "integer"},
           "end": {"type": "integer"},
           "limit": {"type": "integer", "default": 50}},
          ["feature_type"]),
    _tool("functional_lookup",
          "Functional annotation (funannotate + eggNOG): product, PFAM, InterPro, "
          "GO, COG, EC, KEGG. Look up by transcript_id or gene_id (exact), or "
          "search a product/name substring.",
          {"gene_id": {"type": "string"},
           "transcript_id": {"type": "string"},
           "search": {"type": "string"},
           "limit": {"type": "integer", "default": 25}},
          []),
    _tool("contig_stats",
          "Assembly stats. No contig -> count, total length, longest contigs. "
          "With a contig -> length, GC%, N%, gap count.",
          {"contig": {"type": "string"}, "top_n": {"type": "integer", "default": 10}},
          []),
    _tool("coords_to_jbrowse_url",
          "Build a JBrowse 2 deep link for a contig coordinate range. Optional "
          "`flank` bp widens the view on both sides.",
          {"contig": {"type": "string"}, "start": {"type": "integer"},
           "end": {"type": "integer"},
           "flank": {"type": "integer", "description": "bp added each side (default 0)"}},
          ["contig", "start", "end"]),
    _tool("goto_gene",
          "Jump to a gene or transcript in the genome browser: resolve it by id "
          "(gene/mRNA/tRNA) or Name substring to its coordinates and return a "
          "JBrowse deep link, with `flank` bp of context on each side (default "
          "1000 = 1 kb). Use this whenever the user asks to see / go to / locate a "
          "named gene. If the name isn't found, the result has flag 'not_found' — "
          "try functional_lookup(search=...) to find the id first.",
          {"query": {"type": "string", "description": "gene/transcript id or Name substring"},
           "flank": {"type": "integer", "description": "bp of flanking context each side (default 1000)"},
           "tracks": {"type": "string", "description": "comma-separated trackIds to open (default spalangia_genes)"}},
          ["query"]),
    _tool("retrieve",
          "Retrieve narrative project context (genome report, RESULTS.md, methods, "
          "BUSCO) for background questions. Returns top chunks with citations.",
          {"query": {"type": "string"}, "k": {"type": "integer", "default": 5}},
          ["query"]),
    _tool("latest_blast_results",
          "Metadata about the most recent local BLAST result uploaded for "
          "visualization (hit count, program, token). No arguments.",
          {}, []),
    _tool("sql_query",
          "Run a READ-ONLY SQL query (SELECT / WITH / PRAGMA table_info) against a "
          "SQLite database when the fixed tools can't express the question "
          "(aggregations, joins, GROUP BY, custom filters, counts). Databases: "
          "'functional' (tables: annotations, eggnog) and 'gff' (gffutils schema). "
          "Call with schema=true (or no sql) first to see tables + columns. Results "
          "are capped at 200 rows. If the query errors or the data can't answer it, "
          "the result includes a 'flag' field — when you see it, tell the user you "
          "cannot be sure of the answer.",
          {"sql": {"type": "string", "description": "one read-only SQL statement"},
           "db": {"type": "string", "enum": ["functional", "gff"],
                  "description": "which database (default functional)"},
           "schema": {"type": "boolean",
                      "description": "true = return tables+columns instead of running sql"}},
          []),
]


def dispatch_tool(name: str, args: dict) -> dict:
    if name == "gff_query":
        return gff_query.run(**args)
    if name == "functional_lookup":
        return functional_lookup.run(**args)
    if name == "contig_stats":
        return contig_stats.run(**args)
    if name == "retrieve":
        return retriever.run(**args)
    if name == "latest_blast_results":
        return blast_results.latest()
    if name == "sql_query":
        return sql_query.run(**args)
    if name == "goto_gene":
        return gff_query.locate(**args)
    if name == "coords_to_jbrowse_url":
        base = os.environ.get("JBROWSE_URL", "http://localhost:8080").rstrip("/")
        asm = os.environ.get("ASSEMBLY_NAME", "spalangia_cameroni")
        flank = max(0, int(args.get("flank") or 0))
        start = max(1, int(args["start"]) - flank)
        end = int(args["end"]) + flank
        url = f"{base}/?assembly={asm}&loc={args['contig']}:{start}-{end}"
        return {"url": url, "view": {"contig": args["contig"], "start": start, "end": end}}
    return {"error": f"unknown tool {name}"}


class ChatRequest(BaseModel):
    q: str
    max_turns: int = 6


class BlastResultsRequest(BaseModel):
    results: str                       # raw BLAST outfmt 6/7 text
    program: str | None = None         # blastn|tblastn|blastp|blastx
    subject_type: str | None = None    # genome|protein (overrides program inference)


class BlastRunRequest(BaseModel):
    query: str                         # raw sequence or FASTA (>header optional)
    program: str                       # blastn|tblastn|blastp|blastx
    evalue: float | None = None        # default 1e-5


@app.get("/health")
def health():
    return {
        "ok": True,
        "model": MODEL,
        "gff_db_present": gff_query.db_present(),
        "functional_db_present": functional_lookup.db_present(),
        "assembly_fasta_present": contig_stats.fasta_present(),
        "rag_index_present": retriever.index_present(),
        "sql_dbs_present": sql_query.dbs_present(),
        "blast": blast_run.available(),
    }


@app.post("/blast", dependencies=[Depends(require_auth)])
def blast_run_endpoint(req: BlastRunRequest):
    """Run BLAST server-side (blastn/tblastn/blastp/blastx) against the local DBs
    and store hits as the `blast_hits` track. Deterministic — no LLM involved."""
    return blast_run.run(req.query, program=req.program, evalue=req.evalue)


@app.post("/blast-results", dependencies=[Depends(require_auth)])
def blast_results_ingest(req: BlastResultsRequest):
    """Ingest local BLAST output, store as the `blast_hits` track, return a JBrowse link."""
    return blast_results.parse_and_store(
        req.results, program=req.program, subject_type=req.subject_type,
        jbrowse_url=os.environ.get("JBROWSE_URL"))


@app.get("/blast-results/latest.gff3", response_class=PlainTextResponse)
def blast_results_gff():
    path = blast_results.STORE_DIR / "latest.gff3"
    if not path.exists():
        raise HTTPException(404, "no BLAST results uploaded yet")
    return PlainTextResponse(path.read_text(), media_type="text/plain")


@app.post("/chat", dependencies=[Depends(require_auth)])
def chat(req: ChatRequest):
    if not SYSTEM_PROMPT_PATH.exists():
        raise HTTPException(500, "system_prompt.md missing")
    messages = [
        {"role": "system", "content": SYSTEM_PROMPT_PATH.read_text()},
        {"role": "user", "content": req.q},
    ]

    def stream():
        for _turn in range(req.max_turns):
            resp = client.chat.completions.create(
                model=MODEL, max_tokens=8000, messages=messages,
                tools=TOOLS, tool_choice="auto",
                extra_body={"reasoning": {"effort": "medium"}},
            )
            msg = resp.choices[0].message

            # Expose the model's reasoning (OpenRouter returns it on the message).
            extra = getattr(msg, "model_extra", None) or {}
            reasoning = getattr(msg, "reasoning", None) or extra.get("reasoning")
            if reasoning:
                yield f"data: {json.dumps({'type': 'thinking', 'text': reasoning})}\n\n"

            if msg.content:
                yield f"data: {json.dumps({'type': 'text', 'text': msg.content})}\n\n"

            assistant = {"role": "assistant", "content": msg.content or ""}
            # Preserve reasoning across tool-call turns (Anthropic needs the thinking
            # block to precede tool_use; OpenRouter round-trips it via reasoning_details).
            rd = extra.get("reasoning_details")
            if rd:
                assistant["reasoning_details"] = rd
            if msg.tool_calls:
                assistant["tool_calls"] = [
                    {"id": tc.id, "type": "function",
                     "function": {"name": tc.function.name,
                                  "arguments": tc.function.arguments}}
                    for tc in msg.tool_calls
                ]
            messages.append(assistant)

            if not msg.tool_calls:
                break

            for tc in msg.tool_calls:
                try:
                    args = json.loads(tc.function.arguments or "{}")
                except json.JSONDecodeError:
                    args = {}
                yield f"data: {json.dumps({'type': 'tool_use', 'name': tc.function.name, 'input': args})}\n\n"
                try:
                    result = dispatch_tool(tc.function.name, args)
                except Exception as e:  # noqa: BLE001
                    result = {"error": str(e)}
                yield f"data: {json.dumps({'type': 'tool_result', 'name': tc.function.name, 'result': result})}\n\n"
                messages.append({"role": "tool", "tool_call_id": tc.id,
                                 "content": json.dumps(result)})

        yield f"data: {json.dumps({'type': 'done'})}\n\n"

    return StreamingResponse(stream(), media_type="text/event-stream")
