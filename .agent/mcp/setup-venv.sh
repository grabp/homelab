#!/usr/bin/env bash
# Setup local venv for MCP server runtime
# MCP requires a stable Python path, but hatch uses centralized venvs with hash-based paths
# This script creates a local venv that .mcp.json can reference reliably

set -e

cd "$(dirname "$0")"

echo "Creating local venv for MCP server..."
python3 -m venv venv

echo "Installing package in development mode..."
venv/bin/pip install -q --upgrade pip
venv/bin/pip install -q -e ".[dev]"

echo "Running tests to verify installation..."
venv/bin/pytest -q

echo ""
echo "✓ Setup complete!"
echo ""
echo "The venv is now ready for MCP server use."
echo "For development, use hatch commands instead:"
echo "  - hatch run pytest       # Run tests"
echo "  - hatch run pytest --cov # Run tests with coverage"
echo ""
