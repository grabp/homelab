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


def get_service_info(service_name: str) -> Optional[dict]:
    """Get detailed information about a homelab service.

    Returns a dict with:
    - ports: list of TCP ports from networking.firewall.allowedTCPPorts
    - secrets: list of sops secret paths (e.g., "caddy/env")
    - patterns: list of pattern IDs referenced in comments (e.g., ["11", "16"])
    """
    repo_root = get_repo_root()
    service_path = repo_root / "homelab" / service_name / "default.nix"

    if not service_path.exists():
        return None

    content = service_path.read_text()

    # Extract ports from networking.firewall.allowedTCPPorts = [ ... ];
    ports = []
    in_ports_block = False
    for line in content.splitlines():
        stripped = line.strip()
        if "allowedTCPPorts" in stripped:
            in_ports_block = True
            # Check if ports are on same line: allowedTCPPorts = [ 80 443 ];
            if "[" in stripped and "]" in stripped:
                bracket_content = stripped.split("[")[1].split("]")[0]
                ports.extend([p.strip() for p in bracket_content.split() if p.strip().isdigit()])
                in_ports_block = False
        elif in_ports_block:
            if "]" in stripped:
                # Get content before the closing bracket
                bracket_content = stripped.split("]")[0]
                ports.extend([p.strip() for p in bracket_content.split() if p.strip().isdigit()])
                in_ports_block = False
            else:
                # Just port numbers on this line
                ports.extend([p.strip() for p in stripped.split() if p.strip().isdigit()])

    # Extract secrets from sops.secrets."service/..." declarations
    secrets = set()
    import re
    secret_pattern = re.compile(r'sops\.secrets\."([^"]+)"')
    for match in secret_pattern.finditer(content):
        secrets.add(match.group(1))

    # Extract pattern IDs from comments (Pattern NN or pattern NN)
    patterns = []
    pattern_id_regex = re.compile(r'[Pp]attern\s+(\d+)')
    for match in pattern_id_regex.finditer(content):
        pattern_id = match.group(1)
        if pattern_id not in patterns:
            patterns.append(pattern_id)

    return {
        "ports": [int(p) for p in ports],
        "secrets": sorted(list(secrets)),
        "patterns": sorted(patterns),
    }
