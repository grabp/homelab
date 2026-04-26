# justfile — NixOS homelab task runner
# Install just: nix-shell -p just

# ── Local Operations ──────────────────────────
switch:
    sudo nixos-rebuild switch --flake .

test:
    nixos-rebuild test --flake . --use-remote-sudo

build:
    nixos-rebuild build --flake .

debug:
    nixos-rebuild switch --flake . --use-remote-sudo --show-trace --verbose

# ── Remote Deployment ─────────────────────────
deploy host="pebble":
    nix run github:serokell/deploy-rs -- -s .#{{ host }}

deploy-all:
    nix run github:serokell/deploy-rs -- -s .

deploy-vps:
    nix run github:serokell/deploy-rs -- -s .#vps

# Initial VPS provisioning via nixos-anywhere (run once per VPS)
# Prereqs: run `just gen-vps-hostkey` first, add the age key to .sops.yaml,
#          create secrets/vps.yaml with `just edit-secrets-vps`, then run this.
# --extra-files uploads the pre-generated SSH host key so sops can decrypt vps.yaml at boot.

# Usage: just provision-vps 1.2.3.4
provision-vps ip:
    nix run github:nix-community/nixos-anywhere -- \
      --flake .#vps \
      --extra-files /tmp/vps-hostkey \
      root@{{ ip }}

# Pre-generate VPS SSH host key to solve the sops chicken-and-egg problem.
# The VPS age key (derived from SSH host key) must be in .sops.yaml before
# secrets/vps.yaml can be encrypted for the VPS.
#
# Workflow:
#   1. just gen-vps-hostkey        — generates key, prints age key
#   2. Edit .sops.yaml             — add `- &vps age1...` and uncomment `- *vps`
#   3. just edit-secrets-vps       — create secrets/vps.yaml with netbird secrets
#   4. just build                  — verify flake builds before provisioning

# 5. just provision-vps <VPS_IP> — install NixOS with pre-generated host key
gen-vps-hostkey:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p /tmp/vps-hostkey/etc/ssh
    if [ ! -f /tmp/vps-hostkey/etc/ssh/ssh_host_ed25519_key ]; then
      ssh-keygen -t ed25519 -N "" -f /tmp/vps-hostkey/etc/ssh/ssh_host_ed25519_key -C "vps-hostkey"
      echo "SSH host key generated."
    else
      echo "SSH host key already exists at /tmp/vps-hostkey/etc/ssh/ssh_host_ed25519_key"
    fi
    echo ""
    echo "VPS SSH host public key:"
    cat /tmp/vps-hostkey/etc/ssh/ssh_host_ed25519_key.pub
    echo ""
    echo "VPS age key (add to .sops.yaml under keys):"
    nix shell nixpkgs#ssh-to-age -c ssh-to-age < /tmp/vps-hostkey/etc/ssh/ssh_host_ed25519_key.pub
    echo ""
    echo "Next steps:"
    echo "  1. Add '- &vps age1...' to .sops.yaml keys section"
    echo "  2. Uncomment '- *vps' in the vps.yaml creation rule"
    echo "  3. just edit-secrets-vps  # add netbird/turn_password and netbird/encryption_key"
    echo "  4. just build"
    echo "  5. just provision-vps <VPS_IP>"

ssh-vps:
    ssh admin@204.168.181.110

# ── Flake Management ──────────────────────────
update:
    nix flake update

update-input input:
    nix flake update {{ input }}

check:
    nix flake check

show:
    nix flake show

# ── Secrets ───────────────────────────────────
edit-secrets:
    sops secrets/secrets.yaml

edit-secrets-vps:
    sops secrets/vps.yaml

rekey:
    find secrets -name '*.yaml' -exec sops updatekeys {} \;

# ── NetBird ────────────────────────────────────

# Show NetBird connection status and ICE candidate type on homelab
netbird-status:
    ssh admin@192.168.10.50 "sudo netbird-wt0 status -d"

# ── Maintenance ───────────────────────────────
gc:
    sudo nix-collect-garbage --delete-old

clean:
    sudo nix profile wipe-history --profile /nix/var/nix/profiles/system --older-than 7d

history:
    nix profile history --profile /nix/var/nix/profiles/system

fmt:
    nix fmt

# Install pre-commit hooks without entering the devShell
install-hooks:
    nix run nixpkgs#pre-commit -- install

repl:
    nix repl -f flake:nixpkgs

# ── Installation helpers ───────────────────────
# Run on target machine during installation
# 1. Boot NixOS ISO
# 2. Identify disk: lsblk -d -o NAME,SIZE,MODEL
# 3. Update disko.nix device path

# 4. Run: just disko-install /dev/sdX
disko-install disk:
    sudo nix run github:nix-community/disko/latest -- \
      --mode destroy,format,mount \
      ./machines/nixos/pebble/disko.nix \
      --arg diskoFile ./machines/nixos/pebble/disko.nix

# Generate hostId for networking.hostId in pebble/default.nix
gen-hostid:
    head -c4 /dev/urandom | od -A none -t x4 | tr -d ' \n' && echo

# ── Documentation ──────────────────────────────

# Serve docs locally at http://localhost:8000
docs-serve:
    mkdocs serve

# Build static site to site/ directory
docs-build:
    nix build .#docs-site && echo "BUILD OK"

# ── MCP Server ─────────────────────────────────

# Setup MCP server venv, install dependencies, and create .mcp.json (run once per machine)
mcp-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    REPO_ROOT="$(pwd)"
    cd .agent/mcp
    if [ ! -d "venv" ]; then
        python3 -m venv venv
        echo "✓ Created venv"
    else
        echo "✓ venv already exists"
    fi
    source venv/bin/activate
    pip install -q -e ".[dev]"
    echo "✓ Installed homelab_mcp package"

    # Generate .mcp.json from example
    cd "$REPO_ROOT"
    if [ ! -f ".mcp.json" ]; then
        sed "s|REPO_ROOT|$REPO_ROOT|g" .mcp.json.example > .mcp.json
        echo "✓ Created .mcp.json"
        echo ""
        echo "MCP server ready. Restart Claude Code to connect."
    else
        echo ""
        echo "Note: .mcp.json already exists. Delete it to regenerate."
    fi

    echo ""
    echo "To test: just mcp-serve"

# Run MCP server manually (for testing)
mcp-serve:
    .agent/mcp/run-mcp.sh

# Run MCP server tests
mcp-test:
    #!/usr/bin/env bash
    set -euo pipefail
    cd .agent/mcp
    source venv/bin/activate
    pytest -q

# Check MCP server configuration
mcp-check:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "MCP config: .mcp.json (gitignored, machine-specific)"
    echo "Example: .mcp.json.example"
    echo "Server script: .agent/mcp/run-mcp.sh"
    echo ""
    if [ -f ".mcp.json" ]; then
        echo "✓ .mcp.json exists"
        SCRIPT_PATH=$(grep -o '"[^"]*run-mcp.sh"' .mcp.json | tr -d '"' | head -1)
        echo "  Configured script path: $SCRIPT_PATH"
    else
        echo "✗ .mcp.json missing - run: just mcp-setup"
    fi
    if [ -f ".agent/mcp/venv/bin/python" ]; then
        echo "✓ venv exists"
    else
        echo "✗ venv missing - run: just mcp-setup"
    fi
    if "$SHELL" -c "source .agent/mcp/venv/bin/activate && python -c 'import homelab_mcp' 2>/dev/null"; then
        echo "✓ homelab_mcp module importable"
    else
        echo "✗ homelab_mcp not installed - run: just mcp-setup"
    fi
