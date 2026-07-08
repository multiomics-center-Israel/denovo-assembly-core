"""Stdio MCP server exposing the Spalangia agent tools.

Spawned by the local `claude` CLI (LLM_BACKEND=cli) so the model can call the
same gff/functional/contig/blast tools the OpenRouter loop uses — over MCP,
against the bundled SQLite/FASTA data. Run: `python mcp_server.py` (stdio).
"""
import json

import anyio
import mcp.types as types
from mcp.server import Server
from mcp.server.stdio import stdio_server

from agent_tools import TOOLS, dispatch_tool

server = Server("spalangia")


@server.list_tools()
async def list_tools() -> list[types.Tool]:
    return [
        types.Tool(
            name=t["function"]["name"],
            description=t["function"]["description"],
            inputSchema=t["function"]["parameters"],
        )
        for t in TOOLS
    ]


@server.call_tool()
async def call_tool(name: str, arguments: dict | None) -> list[types.TextContent]:
    # Tools are synchronous and quick; run inline and return JSON text.
    result = dispatch_tool(name, arguments or {})
    return [types.TextContent(type="text", text=json.dumps(result))]


async def _main() -> None:
    async with stdio_server() as (read_stream, write_stream):
        await server.run(read_stream, write_stream,
                         server.create_initialization_options())


if __name__ == "__main__":
    anyio.run(_main)
