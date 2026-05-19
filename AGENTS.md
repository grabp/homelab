# AGENTS.md

## Project
NixOS homelab. One flake managing **three machines**: homelab server + media server + VPS control plane. Target: nixos-25.11.

**Machines:**
- `pebble` — HP ProDesk (homelab server, deployed, behind CGNAT)
- `boulder` — HP EliteDesk (media/productivity server, deployed, behind CGNAT)
- `vps` — Hetzner CX22 (NetBird control plane, public IP)

## Current State
Read PROGRESS.md first. It tracks what's done and what's next.

## Architecture Docs (read before implementing)
- docs/ARCHITECTURE.md — decisions on ZFS, isolation, networking, secrets
- docs/roadmap/ — staged implementation plan (follow this order)
- docs/patterns/index.md — verified code patterns (use these, don't invent)
- docs/SERVICE-CONFIGS.md — per-service configs and gotchas
- docs/STRUCTURE.md — repo layout (follow exactly)

## Critical Rules
- Never invent NixOS options. If unsure whether an option exists, say so.
- Use code patterns from docs/patterns/ as templates.
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

Agent skills live in `.agent/skills/<name>/SKILL.md`. The `.claude/skills` directory symlinks to `../.agent/skills` (relative to `.claude/`) so Claude Code discovers them automatically.

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

## Remote Builds

Development machine is Apple Silicon (aarch64-darwin). All targets are x86_64-linux.

**deploy-rs** uses `remoteBuild = true` — each target builds its own closure. Works from any architecture.

**Remote builders** (boulder primary, pebble fallback) are configured for `nix build` and `nix flake check` from the Mac. See `docs/operations/remote-build.md` for Mac-side setup.

## Commands

> **First run on a new clone:** `just setup-local` — decrypts VPS IP from `secrets/admin.yaml` into gitignored `machines/nixos/local.nix`. Required before any VPS build or deploy.

- `just build` — build without switching
- `just switch` — build and switch locally
- `just deploy pebble` — remote deploy pebble via deploy-rs
- `just deploy boulder` — remote deploy boulder via deploy-rs
- `just deploy-vps` — remote deploy VPS via deploy-rs
- `just ssh-pebble` — SSH to pebble
- `just ssh-boulder` — SSH to boulder
- `just ssh-vps` — SSH to VPS
- `just provision-pebble IP` — initial pebble provisioning via nixos-anywhere
- `just provision-boulder IP` — initial boulder provisioning via nixos-anywhere
- `just provision-vps IP` — initial VPS provisioning via nixos-anywhere
- `just gen-pebble-hostkey` — generate pebble SSH host key (for sops age derivation)
- `just gen-boulder-hostkey` — generate boulder SSH host key
- `just gen-vps-hostkey` — generate VPS SSH host key
- `just netbird-status` — show NetBird connection status on pebble
- `just check` — flake check
- `just edit-secrets-pebble` — edit pebble secrets (secrets/pebble.yaml)
- `just edit-secrets-boulder` — edit boulder secrets (secrets/boulder.yaml)
- `just edit-secrets-vps` — edit VPS secrets (secrets/vps.yaml)
- `just edit-secrets-admin` — edit admin secrets (secrets/admin.yaml, includes vpsIP)
- `just setup-local` — regenerate machines/nixos/local.nix from secrets/admin.yaml
- `just check-builder` — verify Mac can reach remote builders (run with sudo)
- `just remote-build <host>` — build a host's closure using remote builders
