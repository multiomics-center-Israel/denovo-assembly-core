import json
import os
from pathlib import Path

import anthropic
from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from tools import blast_client, contig_stats, gff_query, retriever

MODEL = os.environ.get("ANTHROPIC_MODEL", "claude-sonnet-4-6")
SYSTEM_PROMPT_PATH = Path("/app/system_prompt.md")

app = FastAPI(title="Spalangia genome agent")

client = anthropic.Anthropic()

TOOLS = [
    {
        "name": "gff_query",
        "description": (
            "Query the GFF SQLite database (gffutils) holding all annotation features "
            "(repeats, BUSCO, BRAKER3 genes, functional annotation). Accepts a feature "
            "type, contig name, and optional coordinate range. Returns a list of feature "
            "rows with attributes."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "feature_type": {"type": "string", "description": "e.g. 'gene', 'mRNA', 'repeat_region'"},
                "contig": {"type": "string"},
                "start": {"type": "integer"},
                "end": {"type": "integer"},
                "limit": {"type": "integer", "default": 50},
            },
            "required": ["feature_type"],
        },
    },
    {
        "name": "blast",
        "description": "Run a BLAST search against the indexed Spalangia databases.",
        "input_schema": {
            "type": "object",
            "properties": {
                "sequence": {"type": "string"},
                "program": {"type": "string", "enum": ["blastn", "blastp", "tblastn", "blastx"]},
                "db": {"type": "string"},
            },
            "required": ["sequence", "program", "db"],
        },
    },
    {
        "name": "coords_to_jbrowse_url",
        "description": "Build a JBrowse 2 deep link for a contig coordinate range.",
        "input_schema": {
            "type": "object",
            "properties": {
                "contig": {"type": "string"},
                "start": {"type": "integer"},
                "end": {"type": "integer"},
            },
            "required": ["contig", "start", "end"],
        },
    },
    {
        "name": "contig_stats",
        "description": (
            "Stats from the assembly FASTA. With no contig argument, returns the "
            "total contig count, total length, and the top N longest contigs. "
            "With a contig name, returns length, GC%, N%, and gap (N-run) count."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "contig": {"type": "string"},
                "top_n": {"type": "integer", "default": 10},
            },
        },
    },
    {
        "name": "retrieve",
        "description": (
            "Retrieve project context (RESULTS.md, decontam summaries, RepeatMasker .tbl, "
            "pipeline reports) for natural-language background questions. Returns top "
            "chunks with citations."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {"type": "string"},
                "k": {"type": "integer", "default": 5},
            },
            "required": ["query"],
        },
    },
]


def dispatch_tool(name: str, args: dict) -> dict:
    if name == "gff_query":
        return gff_query.run(**args)
    if name == "blast":
        return blast_client.run(**args)
    if name == "contig_stats":
        return contig_stats.run(**args)
    if name == "coords_to_jbrowse_url":
        base = os.environ.get("JBROWSE_URL", "http://localhost:8080")
        url = (
            f"{base}/?assembly=spalangia_cameroni"
            f"&loc={args['contig']}:{args['start']}-{args['end']}"
        )
        return {"url": url}
    if name == "retrieve":
        return retriever.run(**args)
    return {"error": f"unknown tool {name}"}


class ChatRequest(BaseModel):
    q: str
    max_turns: int = 6


@app.get("/health")
def health():
    return {
        "ok": True,
        "model": MODEL,
        "assembly_fasta_present": contig_stats.fasta_present(),
        "gff_db_present": gff_query.db_present(),
        "rag_index_present": retriever.index_present(),
    }


@app.post("/chat")
def chat(req: ChatRequest):
    if not SYSTEM_PROMPT_PATH.exists():
        raise HTTPException(500, "system_prompt.md missing")
    system = [
        {
            "type": "text",
            "text": SYSTEM_PROMPT_PATH.read_text(),
            "cache_control": {"type": "ephemeral"},
        }
    ]

    messages = [{"role": "user", "content": req.q}]

    def stream():
        for turn in range(req.max_turns):
            resp = client.messages.create(
                model=MODEL,
                max_tokens=4096,
                system=system,
                tools=TOOLS,
                messages=messages,
            )
            messages.append({"role": "assistant", "content": resp.content})

            tool_uses = [b for b in resp.content if b.type == "tool_use"]
            for block in resp.content:
                if block.type == "text":
                    yield f"data: {json.dumps({'type': 'text', 'text': block.text})}\n\n"

            if resp.stop_reason != "tool_use" or not tool_uses:
                break

            tool_results = []
            for tu in tool_uses:
                yield f"data: {json.dumps({'type': 'tool_use', 'name': tu.name, 'input': tu.input})}\n\n"
                try:
                    result = dispatch_tool(tu.name, tu.input)
                except Exception as e:
                    result = {"error": str(e)}
                tool_results.append(
                    {"type": "tool_result", "tool_use_id": tu.id, "content": json.dumps(result)}
                )
                yield f"data: {json.dumps({'type': 'tool_result', 'name': tu.name, 'result': result})}\n\n"
            messages.append({"role": "user", "content": tool_results})

        yield f"data: {json.dumps({'type': 'done'})}\n\n"

    return StreamingResponse(stream(), media_type="text/event-stream")
