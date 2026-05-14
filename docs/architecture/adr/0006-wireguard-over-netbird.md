---
kind: adr
number: "0006"
title: Raw WireGuard hub-and-spoke over NetBird
status: accepted
date: 2026-05-14
---

# ADR 0006: Raw WireGuard hub-and-spoke over NetBird

## Status

Accepted — replaced NetBird (Stages 7a/7b/10b) in May 2026.

## Context

The homelab used NetBird as a VPN overlay: a VPS-hosted control plane (3 OCI containers), Pocket ID as OIDC/passkey IdP, coturn STUN/TURN relay, and a NetBird client on pebble, boulder, and VPS. The actual requirement was simple: a few static mobile devices that need to reach homelab services remotely.

## Decision

Replace the entire NetBird/Pocket ID stack with raw WireGuard in a hub-and-spoke topology. VPS is the hub (listening on UDP 51820). pebble and boulder connect outbound as spokes. Mobile devices connect to the VPS hub.

## Rationale

| Concern | NetBird | Raw WireGuard |
|---------|---------|--------------|
| Peer discovery | Dynamic (management server) | Static (Nix config) |
| Auth infrastructure | Pocket ID OIDC + passkeys | None (keypairs) |
| OCI containers on VPS | 3 (management, signal, dashboard) | 0 |
| TURN relay for CGNAT | Required (coturn) | Not needed — hub routes for clients |
| Version pin workaround | nixpkgs-unstable overlay for 0.68.x | None |
| Stale relay bug | 6h restart timer workaround | Does not apply |
| Adding a device | Dashboard click | Edit Nix, redeploy VPS |
| Removed VPS services | coturn, Pocket ID | — |

Dynamic peer discovery (NetBird's main value) is unnecessary for a handful of known, static devices. Hub-and-spoke through the VPS eliminates the need for TURN relay because traffic never requires peer-to-peer NAT traversal — all packets route through the VPS's public IP.

## Consequences

- **Removed:** `homelab/netbird-client/`, `homelab/netbird-server/`, `homelab/pocket-id/`, `nixpkgs-unstable` flake input, systemd-resolved on pebble/boulder, coturn firewall ports, NetBird/Pocket ID DNS overrides in Pi-hole.
- **Added:** `homelab/wireguard/default.nix` (client module), `machines/nixos/vps/wireguard.nix` (server), `docs/playbooks/wireguard-add-peer.md`.
- Adding a new device requires editing `machines/nixos/vps/wireguard.nix` and running `just deploy-vps` — no dashboard, no OIDC flow.
- Kanidm remains the sole IdP for all service SSO (no more two-tier architecture — Pocket ID's tier is removed).
