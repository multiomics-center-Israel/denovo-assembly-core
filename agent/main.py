import html
import json
import os
import re
import secrets
import subprocess
from pathlib import Path

from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import (HTMLResponse, PlainTextResponse,
                               StreamingResponse)
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

from agent_tools import TOOLS, dispatch_tool
from tools import (blast_results, blast_run, contig_stats, functional_lookup,
                   gene_search, gff_query, retriever, sql_query)

MODEL = os.environ.get("OPENROUTER_MODEL", "anthropic/claude-sonnet-4")
LLM_BACKEND = os.environ.get("LLM_BACKEND", "openrouter").lower()
SYSTEM_PROMPT_PATH = Path(os.environ.get(
    "SYSTEM_PROMPT_PATH", Path(__file__).with_name("system_prompt.md")))

# --- local Claude CLI backend (LLM_BACKEND=cli) config -----------------------
# The CLI backend drives the local `claude` binary with the agent's tools exposed
# over MCP (mcp_server.py). It runs where `claude` is installed + authenticated
# (the host); the MCP server runs in the agent container via `docker exec` so it
# reuses the bundled SQLite/FASTA data. Every knob is env-overridable.
CLAUDE_BIN = os.environ.get("CLAUDE_BIN", "claude")
CLAUDE_CLI_MODEL = os.environ.get("CLAUDE_CLI_MODEL", "sonnet")
AGENT_CONTAINER = os.environ.get("AGENT_CONTAINER", "spalangia-agent-local")
MCP_TOOL_PREFIX = "mcp__spalangia__"
try:
    MCP_SERVER_CMD = json.loads(os.environ["MCP_SERVER_CMD"])
except (KeyError, json.JSONDecodeError):
    MCP_SERVER_CMD = ["docker", "exec", "-i", AGENT_CONTAINER,
                      "python", "/app/mcp_server.py"]

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


# --- deterministic (no-LLM) helpers for the browser UI buttons ---------------

# contig:start-end (or contig:start..end), commas allowed in the numbers.
_COORD_RANGE = re.compile(r"^\s*([^\s:]+):([\d,]+)\s*(?:\.\.|-|–)\s*([\d,]+)\s*$")
# contig:pos — a single point.
_COORD_POINT = re.compile(r"^\s*([^\s:]+):([\d,]+)\s*$")


def _to_int(s: str) -> int:
    return int(s.replace(",", ""))


def resolve_goto(query: str, flank: int | None = None,
                 tracks: str = "spalangia_genes") -> dict:
    """Resolve a free-text location box to a JBrowse view, no LLM involved.

    Accepts `contig:start-end`, `contig:pos`, or a gene id / symbol / Name
    substring (delegated to gff_query.locate). `flank` bp widen the view; when
    unset it defaults to 0 for an explicit range and 1000 otherwise.
    """
    query = (query or "").strip()
    if not query:
        return {"found": False, "flag": "empty", "reason": "empty query"}

    m = _COORD_RANGE.match(query)
    if m:
        contig, start, end = m.group(1), _to_int(m.group(2)), _to_int(m.group(3))
        if start > end:
            start, end = end, start
        pad = 0 if flank is None else max(0, flank)
        vs, ve = max(1, start - pad), end + pad
        return {"found": True, "input_kind": "coordinates",
                "view": {"contig": contig, "start": vs, "end": ve},
                "url": gff_query._jbrowse_url(contig, vs, ve, tracks)}

    m = _COORD_POINT.match(query)
    if m:
        contig, pos = m.group(1), _to_int(m.group(2))
        pad = 1000 if flank is None else max(0, flank)
        vs, ve = max(1, pos - pad), pos + pad
        return {"found": True, "input_kind": "coordinates",
                "view": {"contig": contig, "start": vs, "end": ve},
                "url": gff_query._jbrowse_url(contig, vs, ve, tracks)}

    res = gff_query.locate(query=query, flank=1000 if flank is None else max(0, flank),
                           tracks=tracks)
    res.setdefault("input_kind", "gene")
    return res


@app.get("/goto")
def goto(q: str, flank: int | None = None, tracks: str = "spalangia_genes"):
    """Deterministic 'jump to' resolver for coordinates, gene id, or gene symbol.
    Read-only, no auth, no LLM — powers the browser's Go-to button."""
    return resolve_goto(q, flank=flank, tracks=tracks)


@app.get("/docs/search")
def docs_search(q: str, k: int = 6):
    """Lexical (BM25) full-text search over the project/pipeline documentation.
    Read-only, no auth, no LLM — powers the browser's Docs-search button."""
    q = (q or "").strip()
    if not q:
        return {"query": q, "hits": []}
    if not retriever.index_present():
        raise HTTPException(503, "docs index not built")
    try:
        k = max(1, min(20, int(k)))
    except (TypeError, ValueError):
        k = 6
    return retriever.run(q, k=k)


@app.get("/docs/view", response_class=HTMLResponse)
def docs_view(source: str):
    """Full text of one documentation source, rendered as a standalone HTML page
    (opened in a new tab from a docs-search result). Read-only, no auth, no LLM."""
    if not retriever.index_present():
        raise HTTPException(503, "docs index not built")
    text = retriever.document(source)
    if text is None:
        raise HTTPException(404, f"no documentation source named {source!r}")
    esc_src, esc_body = html.escape(source), html.escape(text)
    page = (
        "<!doctype html><html lang=en><head><meta charset=utf-8>"
        "<meta name=viewport content='width=device-width,initial-scale=1'>"
        f"<title>{esc_src}</title><style>"
        "body{margin:0;font:15px/1.6 system-ui,Segoe UI,Roboto,sans-serif;color:#1a1a1a;background:#fafafa}"
        "header{background:#6a4bb0;color:#fff;padding:14px 22px;font-weight:600}"
        "main{max-width:820px;margin:0 auto;padding:24px 22px}"
        "pre{white-space:pre-wrap;word-break:break-word;font:inherit;margin:0}"
        "</style></head><body>"
        f"<header>📖 {esc_src}</header><main><pre>{esc_body}</pre></main></body></html>"
    )
    return HTMLResponse(page)


@app.get("/genes/search")
def genes_search(q: str, limit: int = 50):
    """Advanced gene-annotation search (query builder). `q` is either a JSON
    object {logic, conditions:[{field,op,value}]} or free text (searched across
    all annotation fields). Read-only, no auth, no LLM — pure parameterized SQL."""
    if not gene_search.db_present():
        raise HTTPException(503, "functional annotation DB not built")
    q = (q or "").strip()
    if not q:
        return {"count": 0, "rows": []}
    logic, conditions = "AND", None
    try:
        parsed = json.loads(q)
        if isinstance(parsed, dict):
            conditions = parsed.get("conditions")
            logic = parsed.get("logic", "AND")
    except (json.JSONDecodeError, TypeError):
        conditions = None
    if not conditions:
        conditions = [{"field": "any", "op": "contains", "value": q}]
    return gene_search.run(conditions, logic=logic, limit=limit)


def _sse(obj: dict) -> str:
    return f"data: {json.dumps(obj)}\n\n"


def stream_via_cli(question: str, system_prompt: str):
    """Drive the local `claude` CLI, agent tools exposed over MCP, and translate
    its stream-json events into the same SSE shape the OpenRouter loop emits."""
    mcp_cfg = {"mcpServers": {"spalangia": {
        "command": MCP_SERVER_CMD[0], "args": MCP_SERVER_CMD[1:]}}}
    cmd = [
        CLAUDE_BIN, "-p", question,
        "--system-prompt", system_prompt,
        "--mcp-config", json.dumps(mcp_cfg),
        "--strict-mcp-config",
        "--permission-mode", "bypassPermissions",
        "--tools", "",                       # no built-in tools; MCP tools only
        "--model", CLAUDE_CLI_MODEL,
        "--output-format", "stream-json", "--verbose",
    ]
    try:
        proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, bufsize=1)
    except FileNotFoundError:
        yield _sse({"type": "text", "text": f"⚠ `{CLAUDE_BIN}` not found on PATH"})
        yield _sse({"type": "done"})
        return

    tool_names: dict[str, str] = {}                # tool_use_id -> short name
    try:
        for line in proc.stdout:
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except json.JSONDecodeError:
                continue
            etype = ev.get("type")
            if etype == "assistant":
                for block in ev.get("message", {}).get("content", []):
                    bt = block.get("type")
                    if bt == "thinking" and block.get("thinking"):
                        yield _sse({"type": "thinking", "text": block["thinking"]})
                    elif bt == "text" and block.get("text"):
                        yield _sse({"type": "text", "text": block["text"]})
                    elif bt == "tool_use":
                        short = (block.get("name") or "").replace(MCP_TOOL_PREFIX, "")
                        tool_names[block.get("id")] = short
                        yield _sse({"type": "tool_use", "name": short,
                                    "input": block.get("input") or {}})
            elif etype == "user":
                for block in ev.get("message", {}).get("content", []):
                    if block.get("type") != "tool_result":
                        continue
                    name = tool_names.get(block.get("tool_use_id"), "tool")
                    content = block.get("content")
                    if isinstance(content, list):
                        content = "".join(c.get("text", "") for c in content
                                          if isinstance(c, dict))
                    try:
                        result = json.loads(content)
                    except (json.JSONDecodeError, TypeError):
                        result = {"text": content}
                    yield _sse({"type": "tool_result", "name": name, "result": result})
    finally:
        proc.wait()
        if proc.returncode not in (0, None):
            err = (proc.stderr.read() or "").strip()[:500] if proc.stderr else ""
            yield _sse({"type": "text", "text": f"⚠ claude CLI exited {proc.returncode}. {err}"})
    yield _sse({"type": "done"})


@app.post("/chat", dependencies=[Depends(require_auth)])
def chat(req: ChatRequest):
    if not SYSTEM_PROMPT_PATH.exists():
        raise HTTPException(500, "system_prompt.md missing")

    if LLM_BACKEND == "cli":
        return StreamingResponse(
            stream_via_cli(req.q, SYSTEM_PROMPT_PATH.read_text()),
            media_type="text/event-stream")

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
