# AGENTS.md

## Project
NixOS homelab. One flake managing **two machines**: homelab server + VPS control plane. Target: nixos-25.11.

**Machines:**
- `pebble` — HP ProDesk (homelab server, deployed, behind CGNAT)
- `vps` — Hetzner CX22 (NetBird control plane, public IP, Stage 6a)
- `boulder` — HP EliteDesk (future, different purposes)

## Current State
Read PROGRESS.md first. It tracks what's done and what's next.

## Architecture Docs (read before implementing)
- docs/ARCHITECTURE.md — decisions on ZFS, isolation, networking, secrets
- docs/roadmap/ — staged implementation plan (follow this order)
- docs/NIX-PATTERNS.md — verified code patterns (use these, don't invent)
- docs/SERVICE-CONFIGS.md — per-service configs and gotchas
- docs/STRUCTURE.md — repo layout (follow exactly)

## Critical Rules
- Never invent NixOS options. If unsure whether an option exists, say so.
- Use code patterns from docs/NIX-PATTERNS.md as templates.
- One stage at a time per docs/roadmap/.
- Update PROGRESS.md after completing work.
- Propose a commit after each meaningful unit of work with conventional commits. Only user can commit
- If you don't know, ask

## MCP Server

An MCP (Model Context Protocol) server provides tools for efficient repository introspection:

**Available tools:**
- `get_machine_ip` — get pebble/vps IP from vars.nix
- `list_services` — enumerate all homelab services
- `get_service_path` — resolve service module paths

**How it works:**
- Server runs as subprocess during Claude Code sessions
- Communicates via stdin/stdout using JSON-RPC
- Provides cached, parsed data instead of repeated file reads
- Configured in `.mcp.json` at repo root

**Setup:** See `.agent/mcp/README.md` for development and deployment.

**Why MCP?** Faster than file reads, caches results, abstracts parsing logic.

## Skills

Agent skills live in `.agent/skills/<name>/SKILL.md`. The `.claude/skills` directory symlinks to `.agent/skills` so Claude Code discovers them automatically.

Available skills (invoke with `/<name>`):
- `implement-plan` — work through one PLAN.md item end-to-end
- `security-fix` — work through one SECURITY-TODO.md item
- `nix-verify` — verify a NixOS option or package exists before using it
- `oci-digest` — get the linux/amd64 sha256 digest for a container image tag
- `new-homelab-service` — scaffold a new homelab service (module, README, Caddy, DNS, secrets)
- `kanidm-oauth2-client` — add OIDC/OAuth2 authentication to an existing service
- `new-sops-secret` — generate and encrypt a new secret with proper ownership/permissions
- `netavark-firewall` — fix Podman container firewall ordering issues
- `service-module-preflight` — load minimal context before editing a homelab service module

To add a new skill: create `.agent/skills/<name>/SKILL.md` with YAML frontmatter (`name`, `description`, `user-invocable: true`), then copy it to `~/.claude/skills/<name>/SKILL.md` for global access.

## Commands
- `just build` — build without switching
- `just switch` — build and switch locally
- `just deploy pebble` — remote deploy pebble via deploy-rs
- `just deploy-vps` — remote deploy VPS via deploy-rs
- `just provision-vps IP` — initial VPS provisioning via nixos-anywhere
- `just ssh-vps` — SSH to VPS
- `just netbird-status` — show NetBird connection status on pebble
- `just check` — flake check
- `just edit-secrets` — edit homelab secrets (secrets/secrets.yaml)
- `just edit-secrets-vps` — edit VPS secrets (secrets/vps.yaml)
