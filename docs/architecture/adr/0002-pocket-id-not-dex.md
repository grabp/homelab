---
kind: adr
status: accepted
date: 2025-04-20
title: Use Pocket ID instead of embedded Dex for NetBird IdP
---

# ADR 0002: Use Pocket ID instead of embedded Dex for NetBird IdP

## Context

NetBird requires an OIDC provider for VPN authentication. Two options were available:

1. **Embedded Dex** — built into `netbirdio/management` container since v0.62.0
2. **External OIDC provider** — Pocket ID, a minimal passkey-only IdP

## Decision

Use **Pocket ID** (`ghcr.io/pocket-id/pocket-id:v1.3.1`) as the external OIDC provider for NetBird, with `EmbeddedIdP.Enabled = false`.

**Rationale:**
- Pocket ID provides WebAuthn/FIDO2 passkey authentication (passwordless)
- Decouples IdP lifecycle from NetBird management container upgrades
- Minimal footprint (~20 MB RAM, SQLite backend)
- Runs co-located on VPS alongside NetBird stack
- `Dex was used during Stage 10a and replaced in Stage 10b.`

## Consequences

**Positive:**
- Stronger authentication (passkeys vs passwords)
- Independent IdP upgrades and backups
- Clean separation of concerns

**Negative:**
- Additional container to manage (mitigated: trivial resource usage)
- User migration required when switching from Dex (one-time cost)

---

**Supersedes:** Stage 10a embedded Dex configuration
