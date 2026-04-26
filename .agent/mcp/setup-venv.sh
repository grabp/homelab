#!/usr/bin/env bash
# Setup local venv for MCP server runtime
# MCP requires a stable Python path, but hatch uses centralized venvs with hash-based paths
# This script creates a local venv that .mcp.json can reference reliably
# Also configures opencode.json with the MCP server settings

set -e

cd "$(dirname "$0")"
MCP_DIR="$(pwd)"
REPO_ROOT="$(cd "$MCP_DIR/../.." && pwd)"

echo "Creating local venv for MCP server..."
python3 -m venv venv

echo "Installing package in development mode..."
venv/bin/pip install -q --upgrade pip
venv/bin/pip install -q -e ".[dev]"

echo "Running tests to verify installation..."
venv/bin/pytest -q

echo ""
echo "Configuring MCP integration..."

# Get machine IPs from vars.nix if available
PEBBLE_IP="192.168.10.50"
VPS_IP="204.168.181.110"
VARS_NIX="$REPO_ROOT/vars.nix"
if [ -f "$VARS_NIX" ]; then
    PEBBLE_IP=$(grep -o 'pebbleIp = "[^"]*"' "$VARS_NIX" 2>/dev/null | sed 's/.*"\([^"]*\)".*/\1/' || echo "$PEBBLE_IP")
    VPS_IP=$(grep -o 'vpsIp = "[^"]*"' "$VARS_NIX" 2>/dev/null | sed 's/.*"\([^"]*\)".*/\1/' || echo "$VPS_IP")
fi

# Generate .mcp.json for Claude Code
cd "$REPO_ROOT"
if [ ! -f ".mcp.json" ]; then
    sed "s|REPO_ROOT|$REPO_ROOT|g" .mcp.json.example > .mcp.json
    echo "✓ Created .mcp.json (Claude Code)"
else
    echo "✓ .mcp.json already exists (Claude Code)"
fi

# Generate/update opencode.json for OpenCode
OPENCONFIG_JSON="$REPO_ROOT/opencode.json"
if [ -f "$OPENCONFIG_JSON" ]; then
    if grep -q '"mcp"' "$OPENCONFIG_JSON" 2>/dev/null; then
        echo "✓ opencode.json already has MCP config (OpenCode)"
    else
        echo "  Adding MCP config to opencode.json..."
        venv/bin/python3 << PYEOF
import json

with open('$OPENCONFIG_JSON', 'r') as f:
    config = json.load(f)

config['mcp'] = {
    'homelab': {
        'type': 'local',
        'command': ['$MCP_DIR/run-mcp.sh'],
        'enabled': True,
        'environment': {
            'PEBBLE_IP': '$PEBBLE_IP',
            'VPS_IP': '$VPS_IP'
        }
    }
}

with open('$OPENCONFIG_JSON', 'w') as f:
    json.dump(config, f, indent=2)
    f.write('\n')

print('✓ Updated opencode.json (OpenCode)')
PYEOF
    fi
else
    cat > "$OPENCONFIG_JSON" << EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "mcp": {
    "homelab": {
      "type": "local",
      "command": ["$MCP_DIR/run-mcp.sh"],
      "enabled": true,
      "environment": {
        "PEBBLE_IP": "$PEBBLE_IP",
        "VPS_IP": "$VPS_IP"
      }
    }
  }
}
EOF
    echo "✓ Created opencode.json (OpenCode)"
fi

echo ""
echo "✓ Setup complete!"
echo ""
echo "MCP server ready:"
echo "  - Claude Code: .mcp.json configured"
echo "  - OpenCode: opencode.json configured"
echo ""
echo "Restart your editor/IDE to connect."
echo ""
echo "For development, use hatch commands:"
echo "  - hatch run pytest       # Run tests"
echo "  - hatch run pytest --cov # Run tests with coverage"
