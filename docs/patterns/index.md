---
kind: index
tags: [patterns]
---

# Patterns Index

This directory contains verified NixOS patterns extracted from the original `docs/NIX-PATTERNS.md`. Each pattern has been split into its own file for easier reference and linking. If you arrived here via a stale link to NIX-PATTERNS.md, you can find the original content preserved as a table of contents pointing to these individual files.

| # | Pattern | Summary | Tags |
|---|---------|---------|------|
| 1 | [01-flake-with-deploy-disko-sops](./01-flake-with-deploy-disko-sops.md) | flake.nix with deploy-rs, disko, and sops-nix | [flake, deploy-rs, disko, sops-nix] |
| 2 | [02-dry-machine-definitions](./02-dry-machine-definitions.md) | flakeHelpers.nix — DRY machine definitions | [flake, helpers, DRY] |
| 3 | [03-zfs-ephemeral-root](./03-zfs-ephemeral-root.md) | disko single-disk ZFS with ephemeral root | [disko, zfs, ephemeral] |
| 4 | [04-ext4-simple](./04-ext4-simple.md) | disko single-disk ext4 (simpler alternative) | [disko, ext4] |
| 5 | [05-custom-module-options](./05-custom-module-options.md) | Custom NixOS module with options | [module, options, OCI-containers] |
| 6 | [06-sops-secrets](./06-sops-secrets.md) | sops-nix secret declaration | [sops-nix, secrets] |
| 7 | [07-caddy-cloudflare](./07-caddy-cloudflare.md) | Caddy with Cloudflare DNS plugin | [caddy, cloudflare, TLS] |
| 8 | [08-systemd-sops-service](./08-systemd-sops-service.md) | systemd service with sops-nix secrets injection | [systemd, secrets, hardening] |
| 9 | [09-justfile-commands](./09-justfile-commands.md) | Justfile for NixOS homelab operations | [just, justfile, commands] |
| 10 | [10-wyoming-procsubset](./10-wyoming-procsubset.md) | Native Wyoming service with systemd ProcSubset override | [wyoming, home-assistant, systemd, hardening] |
| 11 | [11-hacs-install](./11-hacs-install.md) | HACS auto-installation via systemd oneshot | [home-assistant, hacs, systemd] |
| 12 | [12-multi-machine-flake](./12-multi-machine-flake.md) | Multi-machine flake with deploy-rs (homelab + VPS) | [flake, deploy-rs, multi-machine] |
| 13 | [13-nixos-anywhere-vps](./13-nixos-anywhere-vps.md) | nixos-anywhere VPS provisioning with minimal ext4 disko | [vps, nixos-anywhere, provisioning, ext4] |
| 14 | [14-netbird-client](./14-netbird-client.md) | NetBird client with sops-nix setup key and self-hosted management URL | [netbird, client, vpn, overlay] |
| 15 | [15-systemd-resolved-netbird](./15-systemd-resolved-netbird.md) | systemd-resolved with DNSStubListener=no (NetBird + Pi-hole coexistence) | [systemd-resolved, netbird, pihole, DNS] |
| 16 | [16-systemd-dependencies](./16-systemd-dependencies.md) | systemd restart and ordering dependencies for homelab services | [systemd, dependencies, firewall, sops, ordering] |
| 17 | [17-podman-volume-uid](./17-podman-volume-uid.md) | Podman volume directories — own by container UID, not root | [podman, volumes, permissions, sqlite] |
| 18 | [18-ssh-ip-addresses](./18-ssh-ip-addresses.md) | Always use IP addresses for SSH, never domain names | [ssh, deployment, DNS, safety] |
| 19 | [19-netbird-server-oci](./19-netbird-server-oci.md) | NetBird server via OCI containers on NixOS VPS (Pocket ID OIDC) | [netbird, server, OCI-containers, pocket-id, VPS] |
| 20 | [20-vps-native-caddy](./20-vps-native-caddy.md) | Hybrid VPS — NixOS-managed Caddy + OCI NetBird containers | [vps, caddy, TLS, native] |
| 21 | [21-kanidm-oauth2](./21-kanidm-oauth2.md) | Kanidm with declarative OAuth2 client provisioning | [kanidm, OAuth2, OIDC, provisioning] |
| 22 | [22-caddy-forward-auth](./22-caddy-forward-auth.md) | Caddy forward_auth with Kanidm | [caddy, kanidm, forward-auth, oauth2-proxy] |
| 23 | [23-grafana-kanidm-oidc](./23-grafana-kanidm-oidc.md) | Grafana OIDC with Kanidm | [grafana, kanidm, OIDC, SSO] |
