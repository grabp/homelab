"""Repository utilities for homelab MCP server."""

import subprocess
from pathlib import Path
from typing import Optional


def get_repo_root() -> Path:
    """Get the root of the git repository."""
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
        check=True,
    )
    return Path(result.stdout.strip())


def get_machine_ip(machine: str) -> Optional[str]:
    """Get the IP address for a machine from vars.nix."""
    repo_root = get_repo_root()
    vars_file = repo_root / "machines" / "nixos" / "vars.nix"

    if not vars_file.exists():
        return None

    content = vars_file.read_text()

    # Map machine names to var names in vars.nix
    var_map = {
        "pebble": "serverIP",
        "vps": "vpsIP",
    }

    if machine not in var_map:
        return None

    var_name = var_map[machine]

    # Simple parser: look for 'varName = "value";'
    for line in content.splitlines():
        line = line.strip()
        if line.startswith(var_name):
            # Extract IP from: varName = "IP"; # optional comment
            parts = line.split("=")
            if len(parts) == 2:
                value = parts[1].strip()
                # Remove inline comment if present
                if "#" in value:
                    value = value.split("#")[0].strip()
                # Strip quotes and semicolon
                ip = value.strip('";').strip()
                return ip

    return None


def get_services() -> list[str]:
    """Get list of homelab services (directories under homelab/)."""
    repo_root = get_repo_root()
    homelab_dir = repo_root / "homelab"

    if not homelab_dir.exists():
        return []

    services = []
    for item in homelab_dir.iterdir():
        if item.is_dir() and (item / "default.nix").exists():
            services.append(item.name)

    return sorted(services)
