---
kind: roadmap
stage: 7a
title: VPS Provisioning + NetBird Control Plane
status: complete
---

# Stage 7a: VPN — VPS Provisioning + NetBird Control Plane (OCI containers)

## Status
COMPLETE (2026-04-15)

## Architecture
Embedded Dex IdP (built into `netbirdio/management:latest` since v0.62.0). NetBird server via `virtualisation.oci-containers`. Native NixOS Caddy for TLS termination. `services.netbird.server` NixOS module NOT used (not production-ready as of nixos-25.11).

Status: Deployed, setup wizard completed, setup key encrypted into secrets.

## Files Created
- `machines/nixos/vps/disko.nix` — ext4 disk layout for Hetzner CX22 (`/dev/sda`, GPT + EF02 BIOS boot partition)
- `machines/nixos/vps/default.nix` — base VPS config: GRUB boot, virtio kernel modules, sops from `vps.yaml`, ACME defaults
- `machines/nixos/vps/netbird-server.nix` — NetBird control plane: OCI containers (management + signal + dashboard) + native coturn; embedded Dex via `EmbeddedIdP.Enabled = true` in management.json
- `machines/nixos/vps/caddy.nix` — native Caddy reverse proxy: HTTP-01 ACME, gRPC h2c proxy for management/signal, `/oauth2/*` proxy for embedded Dex, dashboard SPA

## Files Modified
- `flake.nix` — added `mkNixos "vps"` call alongside pebble
- `flakeHelpers.nix` — `deployHostname` returns `vars.vpsIP` for VPS (Pattern 18)
- `.sops.yaml` — added VPS age key and `vps.yaml` creation rule
- `justfile` — added `gen-vps-hostkey`, `provision-vps`, `deploy-vps`, `ssh-vps`
- `homelab/pihole/default.nix` — added `address=/netbird.grab-lab.gg/${vars.vpsIP}` for split-DNS exception
- `machines/nixos/vars.nix` — added `vpsIP = "204.168.181.110"`

## Configuration (current — embedded Dex + Caddy)
- OCI containers via `virtualisation.oci-containers` (Podman):
  - `netbirdio/management:latest` (`:8080`) — management REST API + gRPC + embedded Dex IdP
  - `netbirdio/signal:latest` (`:10000`) — peer coordination (still separate image in v0.68.x)
  - `netbirdio/dashboard:latest` (`:3000`) — React web UI
- `management.json`: `EmbeddedIdP.Enabled = true`, `EmbeddedIdP.Issuer = "https://netbird.grab-lab.gg/oauth2"`. `IdpManagerConfig` omitted (only for external IdPs). OIDC endpoint auto-configured by binary.
- Dashboard env: `AUTH_AUTHORITY=/oauth2`, `AUTH_CLIENT_ID=netbird-dashboard`, redirect URIs `/nb-auth` and `/nb-silent-auth`
- Native `services.coturn` — STUN/TURN relay, TLS cert from Caddy's data dir, HMAC secret via sops
- Native `services.caddy` — TLS termination via HTTP-01 ACME; gRPC h2c proxying; `/oauth2/*` → management
- `users.users.turnserver.extraGroups = ["caddy"]` — coturn reads Caddy-managed ACME certs
- `management.json` generated at runtime by systemd oneshot using `jq` to inject TURN password + encryption key
- 2 secrets in `secrets/vps.yaml`: `netbird/turn_password`, `netbird/encryption_key`

## Bugs Fixed During Deployment
1. **Hetzner uses SeaBIOS (BIOS), not UEFI**: switched from systemd-boot to GRUB with EF02 partition in disko.nix
2. **Missing virtio kernel modules**: added `boot.initrd.availableKernelModules = ["virtio_pci" "virtio_blk" "virtio_scsi" "sd_mod" "sr_mod"]`
3. **Coturn permission denied on secrets**: sops secrets default to root-only — added `owner = "turnserver"`, `mode = "0440"`
4. **deploy-rs used domain name, deployed to wrong machine**: fixed via Pattern 18 (IPs only) in `flakeHelpers.nix` and `justfile`
5. **Ports 80/443 not open for ACME**: added `networking.firewall.allowedTCPPorts = [80 443]` to VPS config
6. **Pi-hole didn't pick up DNS override**: must restart Pi-hole container after dnsmasq config changes
7. **ACME assertion error**: use `users.users.turnserver.extraGroups = ["caddy"]` instead of changing cert group
8. **nginx not starting**: `services.nginx.virtualHosts` does NOT auto-enable nginx — `services.nginx.enable = true` must be set explicitly (no longer relevant; nginx removed in favour of Caddy)
9. **Wrong image name in first migration attempt**: `netbirdio/netbird:management-latest` does NOT exist on Docker Hub. Correct image is `netbirdio/management:latest`. Signal is still a separate `netbirdio/signal:latest` image (not merged). deploy-rs rolled back automatically.
10. **Wrong embedded Dex path**: initial attempt used `/idp/` path; correct path is `/oauth2/` (the binary registers Dex routes at `/oauth2`). Dashboard redirect URIs are `/nb-auth` and `/nb-silent-auth` (not `/auth` and `/silent-auth`).
11. **Unregistered redirect_uri BAD_REQUEST**: Dex auto-registers only `/api/reverse-proxy/callback` for the dashboard client. The dashboard PKCE flow sends `/nb-auth`; Dex rejected it. Fix: add `EmbeddedIdP.DashboardRedirectURIs = ["https://${domain}/nb-auth", "https://${domain}/nb-silent-auth"]` to management.json.
12. **AUTH_REDIRECT_URI must be a relative path**: the dashboard JavaScript prepends `window.location.origin` to the value. Full URL `"https://domain/nb-auth"` produces doubled `"https://domainhttps://domain/nb-auth"`. Use `"/nb-auth"` and `"/nb-silent-auth"` (relative paths).
13. **setup_required: false blocked the setup wizard**: old `store.db` from Zitadel-era deployment caused the management server to report setup as already complete. The `/setup` page redirected straight to Dex login, but `idp.db` had no users. Fix: stop management container, delete `store.db` and `idp.db`, restart — instance reverts to `setup_required: true`.

## Pre-Deploy Workflow (Completed)
1. Created Hetzner CX22 VPS at IP `204.168.181.110`
2. Created Cloudflare DNS A record: `netbird.grab-lab.gg → 204.168.181.110` (DNS only, no proxy)
3. Generated SSH host key via `just gen-vps-hostkey`
4. Added VPS age key to `.sops.yaml`
5. Created `secrets/vps.yaml` with TURN password and encryption key
6. Provisioned via `just provision-vps 204.168.181.110`
7. Deployed pebble with Pi-hole DNS override via `just deploy pebble`
8. Restarted Pi-hole to load split-DNS config

## Verification (Passed 2026-04-15)
- [x] `podman ps` on VPS shows 3 containers: `netbird-management` (:8080), `netbird-signal` (:10000), `netbird-dashboard` (:3000)
- [x] `systemctl is-active caddy coturn` — both active
- [x] `curl https://netbird.grab-lab.gg/oauth2/.well-known/openid-configuration` returns Dex discovery JSON with `"issuer": "https://netbird.grab-lab.gg/oauth2"`
- [x] `https://netbird.grab-lab.gg` loads NetBird dashboard (HTTP 200)
- [x] TLS certificate from Let's Encrypt (E8 CA), served by Caddy via HTTP-01 ACME
- [x] Pi-hole split-DNS: `netbird.grab-lab.gg → 204.168.181.110`

## Remaining Manual Steps (Required Before Stage 7b)
- [x] Complete setup wizard at `https://netbird.grab-lab.gg/setup` — admin account created (2026-04-15)
- [x] Create setup key in Dashboard → Setup Keys (reusable, "homelab-servers" group) (2026-04-15)
- [x] Encrypt setup key into `secrets/secrets.yaml` as `netbird.setup_key` (`sops-nix path: netbird/setup_key`) via `just edit-secrets` (2026-04-15)
