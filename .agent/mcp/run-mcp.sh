#!/usr/bin/env bash
# run-mcp.sh — Portable MCP launcher for homelab
# This script finds the repo root and runs the MCP server from the correct location
set -e

# Get the directory where this script lives
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Repo root is two levels up from .agent/mcp/
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MCP_DIR="$REPO_ROOT/.agent/mcp"

cd "$MCP_DIR"

# Use venv if it exists, otherwise fall back to system Python
if [ -f "$MCP_DIR/venv/bin/python" ]; then
    PYTHON="$MCP_DIR/venv/bin/python"
else
    PYTHON="python3"
fi

# Verify Python can import the module
if ! "$PYTHON" -c "import homelab_mcp" 2>/dev/null; then
    echo "Error: Cannot import homelab_mcp module" >&2
    echo "Run: cd '$MCP_DIR' && pip install -e ." >&2
    exit 1
fi

exec "$PYTHON" -m homelab_mcp.server
