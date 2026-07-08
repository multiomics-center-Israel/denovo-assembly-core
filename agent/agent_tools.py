"""Shared tool registry — the agent's callable tools and their dispatch.

Imported by both the OpenRouter chat loop (main.py) and the MCP server
(mcp_server.py) so the exact same tools back both LLM backends.
"""
import os

from tools import (blast_results, contig_stats, functional_lookup, gff_query,
                   retriever, sql_query)


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
