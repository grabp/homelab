---
kind: architecture
tags: [navigation, structure]
---

# STRUCTURE.md — Repository Layout

## Configuration

**Machine configurations:** Each host's NixOS config lives in `machines/nixos/<hostname>/`. The entry point is `default.nix`, which imports `disko.nix` (disk layout), `hardware.nix` (hardware-specific settings), and enables the desired services.

**Service modules:** Each service module and its documentation live in `homelab/<service>/`. The module defines a `my.services.<service>.enable` option. The machine config enables only the services it needs.

**Shared modules:** Reusable modules that don't fit a specific service live in `modules/`. Examples: `modules/networking/` for the `my.networking.staticIPv4` helper, `modules/podman/` for base Podman configuration.

## Secrets

**Secret files:** `secrets/*.yaml` encrypted with sops-nix. Each file is encrypted to specific age keys (derived from SSH host keys + admin workstation key).

- `secrets/secrets.yaml` — homelab secrets (pebble + boulder age keys can decrypt)
- `secrets/vps.yaml` — VPS secrets (vps age key can decrypt)

**Key management:** `.sops.yaml` defines which hosts can decrypt which files. After adding a new host: run `ssh-keyscan <IP> | ssh-to-age` to get its age key, add it to `.sops.yaml` under `&<hostname>`, add `*<hostname>` to the relevant `creation_rules`, then run `just rekey`.

## Documentation

**Architecture documentation:** `docs/architecture/` contains topology, auth, ports & DNS reference, and architecture decision records (ADRs).

**Operations runbooks:** `docs/operations/` contains procedures for deploy, secrets management, backup/restore, and monitoring.

**Pattern library:** `docs/patterns/` contains verified code patterns. Each pattern is a standalone markdown file. See `docs/patterns/index.md` for the full list.

**Roadmap and stages:** `docs/roadmap/` contains the implementation roadmap. `docs/roadmap/stages.md` is the stage summary table. Individual stage narratives live in `docs/roadmap/stage-NN-<name>.md`.

**Archive:** `docs/archive/` contains superseded research documents retained for historical context.

**Per-service docs:** Service-specific documentation lives with the service module at `homelab/<service>/README.md`, not in `docs/`. This keeps configuration and documentation co-located.

**Per-machine docs:** Machine-specific information (hardware, network, deploy procedure, one-time setup steps) lives at `machines/nixos/<hostname>/README.md`.

## Agent tooling

**Claude Code skills:** `.agent/skills/<name>/SKILL.md` defines custom skills for common homelab tasks. The `.claude/skills` directory symlinks to `.agent/skills` so Claude Code discovers project skills automatically.

**MCP server:** `.agent/mcp/` contains the homelab MCP (Model Context Protocol) server. The server provides tools for repository introspection: get machine IPs from `vars.nix`, list services, resolve service paths. `.mcp.json` at the repo root registers the server with Claude Code. See `.agent/mcp/README.md` for architecture and development.

## Generating the current tree

Run `tree -L 3 -I 'result|result-*|.git' .` at the repo root to see the actual directory structure. The tree is not committed to the repo because it drifts with every change.
