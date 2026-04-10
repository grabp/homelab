# AGENTS.md

## Project
NixOS bare-metal homelab for HP Elitedesk 705 G4 (AMD Ryzen, 16GB RAM, single SSD).
Single flake managing all services. Target: nixos-25.11.

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
- `just deploy elitedesk` — remote deploy via deploy-rs
- `just check` — flake check
- `just edit-secrets` — edit sops secrets
