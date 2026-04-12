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
- docs/STAGES.md — staged implementation plan (follow this order)
- docs/NIX-PATTERNS.md — verified code patterns (use these, don't invent)
- docs/SERVICE-CONFIGS.md — per-service configs and gotchas
- docs/STRUCTURE.md — repo layout (follow exactly)

## Critical Rules
- Never invent NixOS options. If unsure whether an option exists, say so.
- Use code patterns from docs/NIX-PATTERNS.md as templates.
- One stage at a time per docs/STAGES.md.
- Update PROGRESS.md after completing work.
- Propose a commit after each meaningful unit of work with conventional commits. Only user can commit
- If you don't know, ask

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
