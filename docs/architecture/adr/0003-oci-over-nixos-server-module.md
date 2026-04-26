---
kind: adr
status: accepted
date: 2025-04-19
title: Use OCI containers instead of native NixOS module for NetBird server
---

# ADR 0003: Use OCI containers instead of native NixOS module for NetBird server

## Context

NetBird server can be deployed on NixOS via two approaches:

1. **Native NixOS module** (`services.netbird.server`) — 41+ options in nixpkgs
2. **OCI containers** (`virtualisation.oci-containers`) — official NetBird images

## Decision

Use **OCI containers** via `virtualisation.oci-containers` for the NetBird server stack (management, signal, relay, dashboard).

**Rationale:**
- The `services.netbird.server` NixOS module is not production-ready as of nixos-25.11
- Official NetBird images are maintained upstream with rapid release cycle
- OCI pattern proven stable for Pi-hole, Home Assistant, ESPHome, Matter Server
- VPS has sufficient resources (4 GB RAM, NetBird stack uses ~300–500 MB)
- Avoids coupling NetBird lifecycle to nixpkgs update cadence

## Consequences

**Positive:**
- Always running latest stable NetBird release
- Consistent with other containerized services (Pi-hole, Home Assistant)
- Easier to follow upstream documentation and examples

**Negative:**
- Container networking requires attention (mitigated: use host network for simplicity)
- Manual image digest pinning needed for reproducibility (tracked in container config)

---

**Supersedes:** None (initial decision — native module evaluated and rejected)
