"""MCP server implementation for homelab tools."""

import asyncio
import json
from pathlib import Path
from typing import Any

from mcp.server import Server
from mcp.types import Tool, TextContent, ImageContent, EmbeddedResource

from .repo import get_repo_root, get_machine_ip, get_services


# Create server instance
server = Server("homelab")


@server.list_tools()
async def list_tools() -> list[Tool]:
    """List available tools."""
    return [
        Tool(
            name="get_machine_ip",
            description="Get the IP address for a machine (pebble or vps) from vars.nix",
            inputSchema={
                "type": "object",
                "properties": {
                    "machine": {
                        "type": "string",
                        "enum": ["pebble", "vps"],
                        "description": "Machine name (pebble or vps)",
                    },
                },
                "required": ["machine"],
            },
        ),
        Tool(
            name="list_services",
            description="List all homelab services (directories under homelab/ with default.nix)",
            inputSchema={
                "type": "object",
                "properties": {},
            },
        ),
        Tool(
            name="get_service_path",
            description="Get the full path to a homelab service module directory",
            inputSchema={
                "type": "object",
                "properties": {
                    "service": {
                        "type": "string",
                        "description": "Service name (e.g., 'caddy', 'kanidm')",
                    },
                },
                "required": ["service"],
            },
        ),
    ]


@server.call_tool()
async def call_tool(name: str, arguments: Any) -> list[TextContent | ImageContent | EmbeddedResource]:
    """Handle tool calls."""

    if name == "get_machine_ip":
        machine = arguments.get("machine")
        if not machine:
            return [TextContent(type="text", text="Error: machine parameter required")]

        ip = get_machine_ip(machine)
        if ip:
            return [TextContent(type="text", text=ip)]
        else:
            return [TextContent(type="text", text=f"Error: Could not find IP for machine '{machine}'")]

    elif name == "list_services":
        services = get_services()
        if services:
            return [TextContent(type="text", text=json.dumps(services, indent=2))]
        else:
            return [TextContent(type="text", text="[]")]

    elif name == "get_service_path":
        service = arguments.get("service")
        if not service:
            return [TextContent(type="text", text="Error: service parameter required")]

        repo_root = get_repo_root()
        service_path = repo_root / "homelab" / service

        if service_path.exists() and (service_path / "default.nix").exists():
            return [TextContent(type="text", text=str(service_path))]
        else:
            return [TextContent(type="text", text=f"Error: Service '{service}' not found")]

    else:
        return [TextContent(type="text", text=f"Error: Unknown tool '{name}'")]


async def main():
    """Run the MCP server."""
    from mcp.server.stdio import stdio_server

    async with stdio_server() as (read_stream, write_stream):
        await server.run(
            read_stream,
            write_stream,
            server.create_initialization_options(),
        )


if __name__ == "__main__":
    asyncio.run(main())
