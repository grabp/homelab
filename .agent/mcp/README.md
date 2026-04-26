# Homelab MCP Server

Model Context Protocol (MCP) server providing tools for Claude Code to interact with the homelab NixOS repository.

## What is MCP?

MCP (Model Context Protocol) is a standard protocol that allows AI assistants like Claude to connect to external tools and data sources. MCP servers expose **tools** (functions Claude can call) and **resources** (data Claude can read).

This homelab MCP server gives Claude Code direct access to repository metadata without having to parse files repeatedly:

- **Get machine IPs** from `vars.nix` without reading the file
- **List services** without globbing `homelab/*/`
- **Resolve paths** to service modules programmatically

## Architecture

```
Claude Code (client)
    ↓
.mcp.json (config)
    ↓
homelab_mcp/server.py (MCP server, stdio transport)
    ↓
homelab_mcp/repo.py (repository utilities)
    ↓
Git repository (machines/nixos/vars.nix, homelab/*/default.nix)
```

### How it works

1. **Startup**: Claude Code reads `.mcp.json` and spawns the Python server as a subprocess
2. **Communication**: Server and client communicate via stdin/stdout using JSON-RPC
3. **Tool calls**: Claude requests available tools, then calls them with arguments
4. **Responses**: Server executes tool logic and returns results as text

The server runs in the same process space for the entire Claude Code session.

## Available Tools

### `get_machine_ip`

Get the IP address for a machine from `machines/nixos/vars.nix`.

**Input:**
```json
{
  "machine": "pebble" | "vps"
}
```

**Output:**
```
192.168.10.50
```

**Use case:** When Claude needs to reference IPs in deploy commands, SSH targets, or documentation.

### `list_services`

List all homelab services (directories under `homelab/` with `default.nix`).

**Input:** (none)

**Output:**
```json
[
  "backup",
  "caddy",
  "grafana",
  "home-assistant",
  "kanidm",
  "loki",
  ...
]
```

**Use case:** When Claude needs to enumerate services for documentation, verification, or batch operations.

### `get_service_path`

Get the full absolute path to a homelab service module directory.

**Input:**
```json
{
  "service": "caddy"
}
```

**Output:**
```
/Users/patrykgrabowski/Projects/lab/homelab/caddy
```

**Use case:** When Claude needs to construct file paths for reading READMEs, configs, or modules.

## Setup

### Initial setup (one-time)

The MCP server requires a local virtual environment that `.mcp.json` can reference. Run this once after cloning:

```bash
cd .agent/mcp
./setup-venv.sh
```

This creates `venv/` and installs the package. The MCP server will use this venv at runtime.

**Why a local venv?** Hatch creates environments in a centralized location (`~/Library/Application Support/hatch/env/...`) with hash-based paths that change. MCP configuration requires a stable path, so we maintain a local venv specifically for runtime.

### Development workflow

For development tasks, use Hatch (faster, better dependency management):

```bash
cd .agent/mcp

# Install/update dev environment
hatch env create

# Run tests
hatch run pytest -v

# Run tests with coverage
hatch run pytest --cov=homelab_mcp --cov-report=term-missing

# Clean build artifacts
hatch clean
```

Or use the provided Justfile:

```bash
just install   # Install with hatch
just test      # Run tests (verbose)
just test-q    # Run tests (quiet)
just test-cov  # Run with coverage
just run       # Run server (for manual testing)
just clean     # Clean artifacts and venv
just env       # Show environment info
```

**Summary:**
- **Runtime** (MCP server): Uses `venv/` (created by `setup-venv.sh`)
- **Development** (testing, debugging): Uses Hatch (managed by `hatch env create`)

### Project structure

```
.agent/mcp/
├── pyproject.toml          # Hatch project config
├── homelab_mcp/
│   ├── __init__.py         # Package metadata
│   ├── server.py           # MCP server (tool definitions, handlers)
│   └── repo.py             # Repository utilities (parsing, file I/O)
├── tests/
│   └── test_tools.py       # Test suite
└── README.md               # This file
```

### Adding a new tool

1. **Add the tool definition** to `server.py` in `list_tools()`:

```python
Tool(
    name="my_new_tool",
    description="What the tool does",
    inputSchema={
        "type": "object",
        "properties": {
            "param": {
                "type": "string",
                "description": "Parameter description",
            },
        },
        "required": ["param"],
    },
)
```

2. **Add the handler** to `server.py` in `call_tool()`:

```python
elif name == "my_new_tool":
    param = arguments.get("param")
    if not param:
        return [TextContent(type="text", text="Error: param required")]

    result = do_something(param)
    return [TextContent(type="text", text=result)]
```

3. **Add helper logic** to `repo.py` if needed:

```python
def do_something(param: str) -> str:
    """Do something with the parameter."""
    # Implementation
    return result
```

4. **Write tests** in `tests/test_tools.py`:

```python
def test_my_new_tool():
    """Test my new tool."""
    result = do_something("test")
    assert result == "expected"
```

5. **Run tests** to verify:

```bash
hatch run pytest -v
```

### Testing the server manually

Run the server in standalone mode:

```bash
cd .agent/mcp
hatch run python -m homelab_mcp.server
```

The server will wait for JSON-RPC messages on stdin. This is useful for debugging protocol-level issues.

For integration testing, use `claude mcp list` to verify the server connects:

```bash
claude mcp list
# Should show: homelab: ... - ✓ Connected
```

## Configuration

The server is configured in `.mcp.json` at the repository root:

```json
{
  "mcpServers": {
    "homelab": {
      "command": "/Users/.../lab/.agent/mcp/venv/bin/python",
      "args": ["-m", "homelab_mcp.server"],
      "cwd": "/Users/.../lab/.agent/mcp",
      "env": {
        "PEBBLE_IP": "192.168.10.50",
        "VPS_IP": "204.168.181.110"
      }
    }
  }
}
```

**Important:** The `command` path points to the venv Python created by Hatch. This ensures dependencies are available at runtime.

### Environment variables

- `PEBBLE_IP`, `VPS_IP`: IP addresses from `vars.nix` (currently unused, reserved for future tools)

## Why MCP instead of direct file reads?

MCP provides:

1. **Caching**: Claude Code caches tool responses within a session
2. **Abstraction**: Tools hide parsing logic (e.g., Nix syntax) from Claude
3. **Performance**: Tool calls are faster than file reads + prompt processing
4. **Reliability**: Parsing happens once in Python instead of ad-hoc in prompts
5. **Discoverability**: Claude sees available tools and their schemas upfront

## Troubleshooting

### Server shows "✗ Failed to connect"

```bash
# Check the server can start
cd .agent/mcp
hatch run python -m homelab_mcp.server

# Verify dependencies are installed
hatch env show

# Check .mcp.json points to the correct Python binary
cat ../../.mcp.json
```

### Tests fail with "No module named 'homelab_mcp'"

```bash
# Reinstall in development mode
cd .agent/mcp
hatch env create --force
```

### Git repo not found during tests

Tests must run from within the repository (they use `git rev-parse --show-toplevel`). Ensure you're running from `.agent/mcp/` or a subdirectory of the repo.

## Future enhancements

Potential tools to add:

- `get_service_ports`: Extract port assignments from a service module
- `get_secret_keys`: List secrets declared in `sops-nix` for a service
- `validate_nix_option`: Check if a NixOS option exists before use
- `get_service_readme`: Read and parse a service's README.md
- `list_stages`: Enumerate roadmap stages and their status

See `PLAN.md` for planned improvements.

## References

- [MCP specification](https://modelcontextprotocol.io/)
- [MCP Python SDK](https://github.com/modelcontextprotocol/python-sdk)
- [Claude Code MCP integration](https://docs.anthropic.com/claude-code/mcp)
