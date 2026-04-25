---
kind: pattern
number: 14
tags: [netbird, client, vpn, overlay]
---

# Pattern 14: NetBird client with sops-nix setup key and self-hosted management URL

The NixOS `services.netbird.clients.<name>` module creates a per-client systemd service (`netbird-wt0.service`) and an optional login oneshot (`netbird-wt0-login.service`).

**⚠️ nixos-25.11 ships netbird 0.60.2 — you MUST override it.**
nixpkgs 25.11 is stuck on 0.60.2. The `netbirdio/management:latest` container (and all current desktop/mobile clients) are on 0.68.x. The relay and signaling protocol changed between these versions: WireGuard handshakes never complete (`Last WireGuard handshake: -` for all peers), ICE connects briefly then drops with "ICE disconnected, do not switch to Relay. Reset priority to: None", `Forwarding rules: 0`. Fix: pull netbird from `nixpkgs-unstable` via an overlay. Add `nixpkgs-unstable` input to `flake.nix` and use `lib.mkMerge` in the module (required because `nixpkgs.overlays` must coexist with an explicit `config = lib.mkIf ...` block — mixing top-level config with explicit `config =` is a module error).

**Other verified gotchas in nixos-25.11:**
- `login.managementUrl` does **NOT** exist as a module option.
- `config.ManagementURL = "https://..."` does **NOT** work in 0.60.2 — stored as `url.URL` Go struct, not string. Crashes with "cannot unmarshal string". Set via `--management-url` flag on first login; persists in `/var/lib/netbird-wt0/config.json`.
- `openInternalFirewall` does **NOT** exist. Use `openFirewall = true`.
- **Do NOT use `login.enable = true`** — the oneshot gets SIGTERM'd during `nixos-rebuild switch` due to a daemon socket race ("Start request repeated too quickly").
- `sops-install-secrets.service` does **NOT** exist — sops-nix uses activation scripts.
- `services.resolved` belongs in the machine config, not this module.

```nix
# flake.nix — add input alongside nixpkgs
nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
```

```nix
# homelab/netbird/default.nix
{ config, lib, inputs, ... }:

let
  cfg = config.my.services.netbird;
in {
  options.my.services.netbird.enable = lib.mkEnableOption "NetBird VPN client";

  # lib.mkMerge required: can't mix top-level config attrs with explicit `config =`
  config = lib.mkMerge [
    {
      # nixos-25.11 ships 0.60.2 — protocol-incompatible with 0.68.x server/clients
      nixpkgs.overlays = [
        (final: prev: {
          inherit (inputs.nixpkgs-unstable.legacyPackages.${prev.stdenv.system}) netbird;
        })
      ];
    }

    (lib.mkIf cfg.enable {
      sops.secrets."netbird/setup_key" = { };

      services.netbird.clients.wt0 = {
        port = 51820;
        openFirewall = true;
        ui.enable = false;
      };

      services.netbird.useRoutingFeatures = "both";

      networking.firewall.extraCommands = ''
        iptables -A FORWARD -i wt0 -j ACCEPT
        iptables -A FORWARD -o wt0 -j ACCEPT
      '';

      networking.firewall.allowedUDPPorts = [ 51820 ];
    })
  ];
}
```

**One-time login after first deploy** (run on pebble; ManagementURL and credentials persist in `/var/lib/netbird-wt0/config.json` across reboots):
```bash
sudo netbird-wt0 up \
  --management-url https://netbird.grab-lab.gg \
  --setup-key-file /run/secrets/netbird/setup_key
```

Route advertisement (192.168.10.0/24) and DNS nameserver groups are configured **in the NetBird Dashboard**, not in NixOS. See `docs/NETBIRD-SELFHOSTED.md` for the step-by-step dashboard configuration.

**Source:** Verified against nixos-25.11, netbird 0.68.1 (overlay from nixpkgs-unstable), management server 0.68.3 ✅.
