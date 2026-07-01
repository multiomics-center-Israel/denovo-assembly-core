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

from tools import (blast_results, contig_stats, functional_lookup, gff_query,
                   retriever)

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
          "Build a JBrowse 2 deep link for a contig coordinate range.",
          {"contig": {"type": "string"}, "start": {"type": "integer"},
           "end": {"type": "integer"}},
          ["contig", "start", "end"]),
    _tool("retrieve",
          "Retrieve narrative project context (genome report, RESULTS.md, methods, "
          "BUSCO) for background questions. Returns top chunks with citations.",
          {"query": {"type": "string"}, "k": {"type": "integer", "default": 5}},
          ["query"]),
    _tool("latest_blast_results",
          "Metadata about the most recent local BLAST result uploaded for "
          "visualization (hit count, program, token). No arguments.",
          {}, []),
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
    if name == "coords_to_jbrowse_url":
        base = os.environ.get("JBROWSE_URL", "http://localhost:8080")
        asm = os.environ.get("ASSEMBLY_NAME", "spalangia_cameroni")
        url = (f"{base}/?assembly={asm}"
               f"&loc={args['contig']}:{args['start']}-{args['end']}")
        return {"url": url}
    return {"error": f"unknown tool {name}"}


class ChatRequest(BaseModel):
    q: str
    max_turns: int = 6


class BlastResultsRequest(BaseModel):
    results: str                       # raw BLAST outfmt 6/7 text
    program: str | None = None         # blastn|tblastn|blastp|blastx
    subject_type: str | None = None    # genome|protein (overrides program inference)


@app.get("/health")
def health():
    return {
        "ok": True,
        "model": MODEL,
        "gff_db_present": gff_query.db_present(),
        "functional_db_present": functional_lookup.db_present(),
        "assembly_fasta_present": contig_stats.fasta_present(),
        "rag_index_present": retriever.index_present(),
    }


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
                model=MODEL, max_tokens=4096, messages=messages,
                tools=TOOLS, tool_choice="auto",
            )
            msg = resp.choices[0].message
            if msg.content:
                yield f"data: {json.dumps({'type': 'text', 'text': msg.content})}\n\n"

            assistant = {"role": "assistant", "content": msg.content or ""}
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
