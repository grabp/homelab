---
kind: adr
number: "0007"
title: VPS public IP stored as local secret, not in git
status: accepted
date: 2026-05-18
---

# ADR 0007: VPS Public IP as Local Secret

## Status

Accepted — implemented 2026-05-18.

## Context

The VPS public IP was committed in `machines/nixos/vars.nix`. Anyone reading the repository could discover the homelab's public entry point. The IP is needed at Nix **build time** (WireGuard peer endpoint, deploy-rs hostname), so it cannot be a runtime sops secret.

## Decision

Move `vpsIP` out of git-tracked `vars.nix` into a gitignored `machines/nixos/local.nix`. The canonical encrypted backup lives in `secrets/admin.yaml` (sops, admin key + GPG only — no machine keys). A `just setup-local` recipe decrypts it to regenerate `local.nix`.

Use `path:.` instead of `.` as the flake URI throughout the justfile. The `path:` scheme copies the project directory (including gitignored files) into the Nix store, making `local.nix` visible to `builtins.pathExists` and `import`. The bare `.` URI uses git-filtered files only.

`vars.nix` uses a lazy `throw` (not `abort`) so missing `local.nix` only fails at evaluation time when `vars.vpsIP` is actually accessed. Builds that don't need the VPS IP (e.g., docs-site) continue to work without `local.nix`.

## Consequences

**Good:**
- VPS public IP never appears in git history after this commit
- `just setup-local` gives a one-command bootstrap on a fresh clone
- New IPs (after Hetzner reprovision) stay out of git permanently

**Honest threat model:**
- Git history before this commit still contains the old IP. This is intentional — a git history rewrite is not planned. The user will change the Hetzner IP separately; the *new* IP will never appear in git.
- ACME CT logs from `netbird.grab-lab.gg` TLS certificates historically disclosed the old IP.
- Cloudflare DNS records (admin-visible, not proxied) still contain the old IP.
- This change removes the casual leak vector for *future* IPs, not historical ones.

**Trade-off:**
- `path:.` copies the full project tree into the Nix store on each build. On this repo (~few MB), the overhead is negligible.
- Fresh clones require `just setup-local` before any `deploy-*` or `build` targeting the VPS.

## Alternatives Considered

- **`--impure` flag with `builtins.getEnv`**: rejected — requires passing `--impure` everywhere and exposes arbitrary env vars to the Nix sandbox.
- **Runtime-only secret**: rejected — WireGuard peer endpoint and deploy-rs hostname are baked into the NixOS closure at build time.
