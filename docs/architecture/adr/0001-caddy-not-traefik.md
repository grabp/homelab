---
kind: adr
status: accepted
date: 2025-04-19
title: Use native NixOS Caddy instead of Traefik
---

# ADR 0001: Use native NixOS Caddy instead of Traefik

## Context

The homelab needed a reverse proxy for TLS termination and routing to services. Two primary options were evaluated:

1. **Traefik** — popular cloud-native reverse proxy with Docker service discovery
2. **NixOS native Caddy** (`services.caddy`) — integrated with NixOS module system

## Decision

Use **native NixOS Caddy** (`services.caddy`) instead of Traefik.

**Rationale:**
- NixOS has a first-class, well-maintained Caddy module
- Declarative configuration in Nix expression language — no separate config file syntax
- Automatic Let's Encrypt certificate management via HTTP-01 challenge
- No container overhead or Docker socket mounting required
- Consistent with "native modules where available" architecture principle

## Consequences

**Positive:**
- Simpler configuration — Caddyfile syntax embedded in Nix
- One less container to manage (no Traefik container on VPS)
- Native systemd integration (automatic reloading on config change)

**Negative:**
- Traefik's built-in dashboard not available (mitigated: use Homepage dashboard)
- Docker service discovery not automatic (mitigated: all services use localhost binding)

---

**Supersedes:** None (initial decision)
