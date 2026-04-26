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


def get_stages() -> list[dict]:
    """Get list of stages from PROGRESS.md.

    Returns a list of stage objects with:
    - number: stage number (e.g., "1", "7a", "10b")
    - description: stage description
    - status: status string (e.g., "✅ COMPLETE", "NOT STARTED")
    - doc_link: path to documentation file
    """
    import re

    repo_root = get_repo_root()
    progress_file = repo_root / "PROGRESS.md"

    if not progress_file.exists():
        return []

    content = progress_file.read_text()
    stages = []

    # Parse the markdown table
    # Look for lines starting with | followed by stage number
    # Format: | Stage | Description | Status | Details |
    # Example: | 1 | Base System | ✅ COMPLETE | [docs/roadmap/stage-01-base-system.md](docs/roadmap/stage-01-base-system.md) |

    in_table = False
    for line in content.splitlines():
        line = line.strip()

        # Skip header and separator rows
        if line.startswith("| Stage |") or line.startswith("|----"):
            in_table = True
            continue

        # End of table when we hit empty line or new section
        if in_table and (not line or not line.startswith("|")):
            in_table = False
            continue

        if in_table and line.startswith("|"):
            # Split by | and clean up
            parts = [p.strip() for p in line.split("|")]
            # parts[0] is empty (before first |), parts[1] is stage, etc.
            if len(parts) >= 5 and parts[1]:
                stage_num = parts[1].strip()
                description = parts[2].strip()
                status = parts[3].strip()
                details = parts[4].strip()

                # Extract doc link from markdown format [text](link)
                doc_link = ""
                link_match = re.search(r'\[([^\]]+)\]\(([^\)]+)\)', details)
                if link_match:
                    doc_link = link_match.group(2)

                stages.append({
                    "number": stage_num,
                    "description": description,
                    "status": status,
                    "doc_link": doc_link,
                })

    return stages


def get_pattern(pattern_id: str) -> Optional[dict]:
    """Get a pattern by ID or tag.

    Args:
        pattern_id: Pattern number (e.g., "17") or tag (e.g., "podman")

    Returns:
        Dict with:
        - id: pattern number
        - name: pattern filename (e.g., "17-podman-volume-uid")
        - title: pattern title
        - tags: list of tags
        - file: relative path to pattern file
        - content: full file content including frontmatter
        - summary: summary from index table
    """
    import re

    repo_root = get_repo_root()
    index_file = repo_root / "docs" / "patterns" / "index.md"

    if not index_file.exists():
        return None

    index_content = index_file.read_text()

    # Parse the index table to find pattern
    # Format: | # | Pattern | Summary | Tags |
    # Example: | 17 | [17-podman-volume-uid](./17-podman-volume-uid.md) | Podman volume directories — own by container UID, not root | [podman, volumes, permissions, sqlite] |

    pattern_entry = None
    in_table = False

    for line in index_content.splitlines():
        line = line.strip()

        # Skip header and separator
        if line.startswith("| # |") or line.startswith("|---|"):
            in_table = True
            continue

        if in_table and (not line or not line.startswith("|")):
            in_table = False
            continue

        if in_table and line.startswith("|"):
            parts = [p.strip() for p in line.split("|")]
            if len(parts) >= 5:
                num = parts[1].strip()
                pattern_cell = parts[2].strip()
                summary = parts[3].strip()
                tags_cell = parts[4].strip()

                # Extract pattern name and file from markdown link [name](file)
                link_match = re.search(r'\[([^\]]+)\]\(([^\)]+)\)', pattern_cell)
                if link_match:
                    pattern_name = link_match.group(1)
                    pattern_file = link_match.group(2).lstrip('./')

                    # Extract tags from [tag1, tag2, tag3]
                    tags = []
                    tags_match = re.search(r'\[([^\]]+)\]', tags_cell)
                    if tags_match:
                        tags = [t.strip() for t in tags_match.group(1).split(',')]

                    # Check if this matches by ID or tag
                    matches = False
                    if num == pattern_id:
                        matches = True
                    elif pattern_id.lower() in [t.lower() for t in tags]:
                        matches = True

                    if matches:
                        pattern_entry = {
                            "id": num,
                            "name": pattern_name,
                            "summary": summary,
                            "tags": tags,
                            "file": f"docs/patterns/{pattern_file}",
                        }
                        break

    if not pattern_entry:
        return None

    # Read the pattern file content
    pattern_path = repo_root / pattern_entry["file"]
    if not pattern_path.exists():
        return None

    pattern_content = pattern_path.read_text()

    # Extract title from the pattern file (first # heading)
    title = ""
    for line in pattern_content.splitlines():
        if line.startswith("# "):
            title = line.lstrip("# ").strip()
            break

    pattern_entry["title"] = title
    pattern_entry["content"] = pattern_content

    return pattern_entry
