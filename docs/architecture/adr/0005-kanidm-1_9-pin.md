---
kind: adr
status: accepted
date: 2025-04-21
title: Pin Kanidm to version 1.9 explicitly
---

# ADR 0005: Pin Kanidm to version 1.9 explicitly

## Context

The NixOS `services.kanidm` module defaults to `pkgs.kanidm_1_4` (as of early nixos-25.11 cycle). Kanidm 1.4 reached EOL and was removed from nixpkgs, causing evaluation errors.

Options:

1. Use default module package (broken — 1.4 removed)
2. **Explicitly pin `pkgs.kanidmWithSecretProvisioning_1_9`**

## Decision

Explicitly set `services.kanidm.package = pkgs.kanidmWithSecretProvisioning_1_9` and include `pkgs.kanidmWithSecretProvisioning_1_9` in `environment.systemPackages`.

**Rationale:**
- Kanidm 1.4 is EOL and removed from nixpkgs (fails to evaluate)
- Kanidm 1.7 was also marked insecure and removed
- Kanidm 1.9 is the current stable release with provisioning support
- Secret provisioning feature required for declarative OAuth2 client configuration

## Consequences

**Positive:**
- Evaluates successfully on nixos-25.11
- Latest stable features and security patches
- Declarative provisioning works (users, groups, OAuth2 clients)

**Negative:**
- Manual version tracking required when 1.10 releases (nixpkgs will add new package)
- Must verify `CaUsedAsEndEntity` TLS certificate constraints (1.9 is stricter than 1.4)

---

**Supersedes:** Default nixos-25.11 module package (broken)
