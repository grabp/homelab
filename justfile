# justfile — NixOS homelab task runner
# Install just: nix-shell -p just

# ── Machine IPs (sourced from vars.nix) ───────
vps_ip := `grep -oP '(?<=vpsIP = ")[^"]+' machines/nixos/vars.nix`

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

# Pre-generate pebble SSH host key (for reprovisioning from scratch).
# Workflow:
#   1. just gen-pebble-hostkey     — generates key, prints age key
#   2. Edit .sops.yaml             — add `- &pebble age1...`, add `- *pebble` to pebble.yaml rule
#   3. just edit-secrets-pebble    — create secrets/pebble.yaml
#   4. nix build .#nixosConfigurations.pebble.config.system.build.toplevel
#   5. just provision-pebble <IP>  — install NixOS with pre-generated host key
gen-pebble-hostkey:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p /tmp/pebble-hostkey/etc/ssh
    if [ ! -f /tmp/pebble-hostkey/etc/ssh/ssh_host_ed25519_key ]; then
      ssh-keygen -t ed25519 -N "" -f /tmp/pebble-hostkey/etc/ssh/ssh_host_ed25519_key -C "pebble-hostkey"
      echo "SSH host key generated."
    else
      echo "SSH host key already exists at /tmp/pebble-hostkey/etc/ssh/ssh_host_ed25519_key"
    fi
    echo ""
    echo "Pebble SSH host public key:"
    cat /tmp/pebble-hostkey/etc/ssh/ssh_host_ed25519_key.pub
    echo ""
    echo "Pebble age key (add to .sops.yaml under keys):"
    nix shell nixpkgs#ssh-to-age -c ssh-to-age < /tmp/pebble-hostkey/etc/ssh/ssh_host_ed25519_key.pub
    echo ""
    echo "Next steps:"
    echo "  1. Add '- &pebble age1...' to .sops.yaml keys section"
    echo "  2. Add '- *pebble' to the pebble.yaml creation rule"
    echo "  3. just edit-secrets-pebble"
    echo "  4. nix build .#nixosConfigurations.pebble.config.system.build.toplevel"
    echo "  5. just provision-pebble <IP>"

# Initial pebble provisioning via nixos-anywhere (run once on fresh machine).
# Prereqs: run `just gen-pebble-hostkey` first, update .sops.yaml,
#          create secrets/pebble.yaml, verify build, then run this.
# If kexec causes a power-off (HP bare metal), boot a NixOS ISO first and re-run.
# If disko fails with "bogus FAT filesystem", re-run — it's a partition rescan race.
# Usage: just provision-pebble 192.168.10.50
provision-pebble ip:
    nix run github:nix-community/nixos-anywhere -- \
      --flake .#pebble \
      --extra-files /tmp/pebble-hostkey \
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

ssh-pebble:
    ssh admin@192.168.10.50

ssh-vps:
    ssh admin@{{vps_ip}}

ssh-boulder:
    ssh admin@192.168.10.51

# Pre-generate boulder SSH host key to solve the sops chicken-and-egg problem.
# The boulder age key (derived from SSH host key) must be in .sops.yaml before
# secrets/boulder.yaml can be created for boulder.
#
# Workflow:
#   1. just gen-boulder-hostkey    — generates key, prints age key
#   2. Edit .sops.yaml             — add `- &boulder age1...` and the boulder.yaml creation rule
#   3. just edit-secrets-boulder   — create secrets/boulder.yaml with netbird/setup_key
#   4. nix build .#nixosConfigurations.boulder.config.system.build.toplevel
#   5. just provision-boulder <IP> — install NixOS with pre-generated host key
gen-boulder-hostkey:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p /tmp/boulder-hostkey/etc/ssh
    if [ ! -f /tmp/boulder-hostkey/etc/ssh/ssh_host_ed25519_key ]; then
      ssh-keygen -t ed25519 -N "" -f /tmp/boulder-hostkey/etc/ssh/ssh_host_ed25519_key -C "boulder-hostkey"
      echo "SSH host key generated."
    else
      echo "SSH host key already exists at /tmp/boulder-hostkey/etc/ssh/ssh_host_ed25519_key"
    fi
    echo ""
    echo "Boulder SSH host public key:"
    cat /tmp/boulder-hostkey/etc/ssh/ssh_host_ed25519_key.pub
    echo ""
    echo "Boulder age key (add to .sops.yaml under keys):"
    nix shell nixpkgs#ssh-to-age -c ssh-to-age < /tmp/boulder-hostkey/etc/ssh/ssh_host_ed25519_key.pub
    echo ""
    echo "Next steps:"
    echo "  1. Add '- &boulder age1...' to .sops.yaml keys section"
    echo "  2. Add boulder.yaml creation rule in .sops.yaml (see vps.yaml rule as template)"
    echo "  3. just edit-secrets-boulder  # create secrets/boulder.yaml with netbird/setup_key"
    echo "  4. nix build .#nixosConfigurations.boulder.config.system.build.toplevel"
    echo "  5. just provision-boulder <IP>"

# Initial boulder provisioning via nixos-anywhere (run once on fresh machine)
# Prereqs: run `just gen-boulder-hostkey` first, add age key to .sops.yaml,
#          run `just rekey`, verify build, then run this.
# Usage: just provision-boulder 192.168.10.51
provision-boulder ip:
    nix run github:nix-community/nixos-anywhere -- \
      --flake .#boulder \
      --extra-files /tmp/boulder-hostkey \
      root@{{ ip }}

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
edit-secrets-pebble:
    sops secrets/pebble.yaml

edit-secrets-vps:
    sops secrets/vps.yaml

edit-secrets-boulder:
    sops secrets/boulder.yaml

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
# Manual disko run — use when bootstrapping from a NixOS ISO directly on the target.
# nixos-anywhere (provision-*) handles this automatically; only use this for manual installs.
#
# Workflow on target machine:
#   1. Boot NixOS minimal ISO
#   2. git clone the repo (or scp disko.nix)
#   3. Verify disk device: lsblk -d -o NAME,SIZE,MODEL,TRAN
#   4. Update machines/nixos/<host>/disko.nix device path if needed
#   5. Run: just disko-format <host>
disko-format host:
    sudo nix run github:nix-community/disko/latest -- \
      --mode destroy,format,mount \
      ./machines/nixos/{{ host }}/disko.nix

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

# ── Agent Setup ────────────────────────────────

# Create .claude/skills symlink so Claude Code discovers project skills
link-skills:
    ln -sfn ../.agent/skills .claude/skills

# ── MCP Server ─────────────────────────────────

# Setup MCP server venv, install dependencies, and create configs for Claude Code and OpenCode
mcp-setup:
    .agent/mcp/setup-venv.sh

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
