---
name: new-homelab-service
description: Use this skill whenever the user wants to add a new self-hosted service to the homelab — phrases like "add X service", "new module for Y", "stand up a Z", or "scaffold a homelab service". This skill generates the full 6-file scaffold (module, README, Caddy vhost, Pi-hole DNS entry, sops declaration, import wiring) in one atomic step so the agent does not need to rediscover the pattern from the existing services each time.
model: inherit
tools: Read, Write, Edit, Bash, Glob, Grep
argument-hint: <service-name> [--oci | --native] [--port N] [--oidc]
disable-model-invocation: false
user-invocable: true
---

# New homelab service scaffold

## When to run
The user wants to add a service that does not yet have a `homelab/<name>/default.nix`. Confirm the service name and whether it ships as an OCI image (most third-party services) or has a native NixOS module (rare; e.g. Kanidm).

## Pre-flight (MUST do in order)
1. `Read PROGRESS.md` — confirm we are not in the middle of another stage.
2. `Read docs/patterns/index.md` (or `docs/NIX-PATTERNS.md` if pre-restructure) — locate Patterns 1 (mkEnableOption), 17 (SHA-pin OCI), 18 (deploy by IP), 20 (Caddy vhost), 22 (Pi-hole DNS).
3. `Glob homelab/*/default.nix` and `Read` two analogous modules (one OCI, one native) as templates.
4. `Read homelab/default.nix` — note how new modules are imported.
5. `Read machines/nixos/pebble/default.nix` — note how `homelab.<svc>.enable` flags are set.
6. Resolve the image digest NOW by running the `oci-digest` skill if `--oci`.

## Generate these 6 files

### 1. `homelab/<name>/default.nix`
Use the verified-working pattern from an existing analogous module. Key invariants:
- Top-level: `{ config, pkgs, lib, ... }:`
- `let cfg = config.homelab.<name>; in`
- `options.homelab.<name> = { enable = lib.mkEnableOption "..."; port = ...; domain = ...; }`
- `config = lib.mkIf cfg.enable { ... }`
- **If OCI:** `virtualisation.oci-containers.containers.<name>` with `image = "<repo>@sha256:<digest>";` NEVER a tag.
- **Netavark firewall fix** (Pattern 19): if the container publishes ports, add
```nix
  systemd.services."podman-<name>" = {
    partOf = [ "firewall.service" ];
    after  = [ "firewall.service" ];
  };
```
- **Secret reference:** if the service needs secrets, declare with `sops.secrets.<name>-<field>.owner = "<systemd-user>"; mode = "0440";`
- **Caddy vhost:** add `services.caddy.virtualHosts.${cfg.domain} = { extraConfig = "import security_headers\nreverse_proxy localhost:${toString cfg.port}"; };`
- **Pi-hole DNS:** add `homelab.pi-hole.customDNS.${cfg.domain} = config.homelab.pi-hole.hostIP;`

### 2. `homelab/<name>/README.md`
Frontmatter (`kind: service`, `touches: [homelab/<name>]`, `tags: [<category>]`), then sections: Purpose, Ports, Secrets, Depends on, DNS, OIDC client (if `--oidc`), Known gotchas, Backup/restore.

### 3. `secrets/<name>.yaml` (if secrets needed)
Don't edit directly. Emit a shell command for the user to run:
`just edit-secrets secrets/<name>.yaml`

### 4. Add to `.sops.yaml` creation_rules
Append a rule matching `secrets/<name>.yaml` with `*pebble` (and `*vps` if the secret ships to the VPS too).

### 5. Wire in `homelab/default.nix`
Add `./<name>` to the `imports` list, preserving alphabetical order.

### 6. Enable on the host
In `machines/nixos/pebble/default.nix` (or vps/), set `homelab.<name>.enable = true;` and set `domain` and `port` if overriding defaults.

## OIDC client path (when --oidc is set)
Additionally:
- Add a Kanidm OAuth2 RP block (see patterns/12 or homelab/kanidm/default.nix): `kanidm.provision.systems.oauth2.<name> = { displayName; originUrl; scopeMaps; basicSecretFile = config.sops.secrets."kanidm-oauth2-<name>".path; };`
- Add a Pocket ID client definition (see homelab/pocket-id/default.nix).
- The basicSecretFile must be mode `0440` and group-owned by the Kanidm group.

## Post-generate verification
Run (report output verbatim, do NOT interpret):

```
nix flake check
nixos-rebuild dry-activate --flake .#pebble --target-host <pebble-ip>
```
Then the user deploys with the `deploy-pebble` skill (NOT by running deploy-rs blindly).

## Things that commonly trip up an LLM without this skill
- Forgetting the Netavark firewall fix → container comes up but ports unreachable.
- Using an image *tag* instead of a digest → Pattern 17 violation; fails review.
- Forgetting the `.sops.yaml` creation_rule → secret cannot be decrypted on the host.
- Forgetting to add both Caddy vhost AND Pi-hole DNS → service reachable via IP:port but not via FQDN.
- Putting Caddy `reverse_proxy` without `import security_headers` → drift from pattern 20.
