# NIX-PATTERNS.md — Validated Nix Code Patterns

Every pattern below is verified against official documentation or production repositories.

Patterns have been split into individual files under [`docs/patterns/`](./patterns/).

---

## Pattern Index

| # | Pattern | Tags |
|---|---------|------|
| 1 | [flake.nix with deploy-rs, disko, and sops-nix](./patterns/01-flake-with-deploy-disko-sops.md) | flake, deploy-rs, disko, sops-nix |
| 2 | [flakeHelpers.nix — DRY machine definitions](./patterns/02-dry-machine-definitions.md) | flake, helpers, DRY |
| 3 | [disko single-disk ZFS with ephemeral root](./patterns/03-zfs-ephemeral-root.md) | disko, zfs, ephemeral |
| 4 | [disko single-disk ext4 (simpler alternative)](./patterns/04-ext4-simple.md) | disko, ext4 |
| 5 | [Custom NixOS module with options](./patterns/05-custom-module-options.md) | module, options, OCI-containers |
| 6 | [sops-nix secret declaration](./patterns/06-sops-secrets.md) | sops-nix, secrets |
| 7 | [Caddy with Cloudflare DNS plugin](./patterns/07-caddy-cloudflare.md) | caddy, cloudflare, TLS |
| 8 | [systemd service with sops-nix secrets injection](./patterns/08-systemd-sops-service.md) | systemd, secrets, hardening |
| 9 | [Justfile for NixOS homelab operations](./patterns/09-justfile-commands.md) | just, justfile, commands |
| 10 | [Native Wyoming service with systemd ProcSubset override](./patterns/10-wyoming-procsubset.md) | wyoming, home-assistant, systemd, hardening |
| 11 | [HACS auto-installation via systemd oneshot](./patterns/11-hacs-install.md) | home-assistant, hacs, systemd |
| 12 | [Multi-machine flake with deploy-rs (homelab + VPS)](./patterns/12-multi-machine-flake.md) | flake, deploy-rs, multi-machine |
| 13 | [nixos-anywhere VPS provisioning with minimal ext4 disko](./patterns/13-nixos-anywhere-vps.md) | vps, nixos-anywhere, provisioning, ext4 |
| 14 | [NetBird client with sops-nix setup key and self-hosted management URL](./patterns/14-netbird-client.md) | netbird, client, vpn, overlay |
| 15 | [systemd-resolved with DNSStubListener=no (NetBird + Pi-hole coexistence)](./patterns/15-systemd-resolved-netbird.md) | systemd-resolved, netbird, pihole, DNS |
| 16 | [systemd restart and ordering dependencies for homelab services](./patterns/16-systemd-dependencies.md) | systemd, dependencies, firewall, sops, ordering |
| 17 | [Podman volume directories — own by container UID, not root](./patterns/17-podman-volume-uid.md) | podman, volumes, permissions, sqlite |
| 18 | [Always use IP addresses for SSH, never domain names](./patterns/18-ssh-ip-addresses.md) | ssh, deployment, DNS, safety |
| 19 | [NetBird server via OCI containers on NixOS VPS (Pocket ID OIDC)](./patterns/19-netbird-server-oci.md) | netbird, server, OCI-containers, pocket-id, VPS |
| 20 | [Hybrid VPS — NixOS-managed Caddy + OCI NetBird containers](./patterns/20-vps-native-caddy.md) | vps, caddy, TLS, native |
| 21 | [Kanidm with declarative OAuth2 client provisioning](./patterns/21-kanidm-oauth2.md) | kanidm, OAuth2, OIDC, provisioning |
| 22 | [Caddy forward_auth with Kanidm](./patterns/22-caddy-forward-auth.md) | caddy, kanidm, forward-auth, oauth2-proxy |
| 23 | [Grafana OIDC with Kanidm](./patterns/23-grafana-kanidm-oidc.md) | grafana, kanidm, OIDC, SSO |

---

## Quick Reference by Topic

### Secrets & Security
- Pattern 6: sops-nix secrets
- Pattern 8: systemd + sops-nix
- Pattern 14: NetBird setup key

### Networking & DNS
- Pattern 7: Caddy + Cloudflare
- Pattern 15: systemd-resolved + Pi-hole
- Pattern 18: SSH with IPs
- Pattern 20: VPS native Caddy
- Pattern 22: Caddy forward_auth

### Containers & OCI
- Pattern 5: Custom modules with options
- Pattern 16: systemd dependencies
- Pattern 17: Podman volume ownership
- Pattern 19: NetBird server OCI

### Deployment & Provisioning
- Pattern 1: flake.nix structure
- Pattern 2: DRY helpers
- Pattern 12: Multi-machine flake
- Pattern 13: nixos-anywhere VPS

### Storage & ZFS
- Pattern 3: ZFS ephemeral root
- Pattern 4: Simple ext4

### Identity & Auth
- Pattern 21: Kanidm OAuth2
- Pattern 23: Grafana + Kanidm

### Home Automation
- Pattern 10: Wyoming ProcSubset
- Pattern 11: HACS installation

### Operations
- Pattern 9: Justfile commands

---

## Legacy Note

This file previously contained all pattern content inline (1,500+ lines). Patterns were split into individual files in P-14 for better maintainability and discoverability. The original content is preserved in the git history.
