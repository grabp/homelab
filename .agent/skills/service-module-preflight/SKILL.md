---
name: service-module-preflight
description: Use this skill ALWAYS before editing any file under homelab/<service>/default.nix. Trigger on any request to modify, extend, fix, or refactor a homelab service module, even if the user does not explicitly ask. Loads the minimum relevant context (stage status, relevant pattern, service README) so the agent does not burn tokens re-reading unrelated docs. This is the "compression skill" that prevents the agent from re-reading 800 lines of NIX-PATTERNS.md for a 3-line edit.
model: inherit
tools: Read, Grep, Glob
argument-hint: <service-name>
disable-model-invocation: false
user-invocable: true
---

# Pre-edit checklist for homelab/<service>/default.nix

## The minimum context load (in order)
1. `Read PROGRESS.md` — confirm the service is in a completed stage (if not, the module may be expected to be incomplete).
2. `Read homelab/<service>/README.md` (if it exists after Task 2 restructure) — the ports/deps/gotchas.
3. `Read homelab/<service>/default.nix` — the module itself. This is the source of truth for what the service *is*.
4. `Grep -nH 'homelab.<service>' machines/nixos/` — where is it enabled, with what options.
5. Relevant patterns only:
   - If editing an OCI container: `Read docs/patterns/17-sha-pinned-images.md` and `docs/patterns/19-netavark-firewall.md`.
   - If editing Caddy vhost: `docs/patterns/20-caddy-vhost.md`.
   - If editing a secret: `docs/patterns/15-sops-ownership.md`.
   - If editing Kanidm/Pocket ID integration: `docs/patterns/12-oauth2-co-location.md`.
   DO NOT load all patterns.

## Hard stops
Refuse to proceed (tell the user) if:
- The service is not yet enabled on any host (`homelab.<svc>.enable = false` everywhere) AND the user is asking to change runtime behavior. Likely they want the `new-homelab-service` skill instead.
- The change would add a new secret but `.sops.yaml` doesn't cover the target file.
- The change adds a published port but no partOf/after for firewall.service exists — route through `netavark-firewall` skill first.

## Before writing the change
State in one sentence:
- Which pattern(s) you're following.
- Which file(s) you will touch.
- What verification command will confirm success.

Then write the change.
