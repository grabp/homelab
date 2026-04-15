# VPS Log Shipping to Loki

## Status: TODO — not implemented

Researched 2026-04-16. Implement as part of Stage 10 hardening, or as a standalone task before Stage 8.

---

## Problem

The VPS runs the NetBird control plane (management, signal, dashboard, coturn, caddy). Its logs are
currently only visible by SSH-ing into the VPS and running `journalctl`. They are not visible in
Grafana/Loki on pebble.

Current state:
- `pebble` — Loki on `127.0.0.1:3100`, Promtail reading journald → Loki (working)
- `vps` — **no log shipper configured**

---

## Recommended approach: Grafana Alloy over NetBird mesh

Run `services.alloy` on the VPS. Alloy collects journald logs and pushes them to Loki on pebble
over the NetBird WireGuard mesh (encrypted, no public exposure).

```
VPS (alloy, loki.source.journal) --[NetBird WireGuard mesh]--> pebble (loki :3100)
```

### Why this approach

- NetBird mesh is already working (Stage 7b complete) — zero extra network setup
- WireGuard encryption in transit — no auth needed on the Loki push API
- `services.alloy` exists in nixpkgs (verified: options are `enable`, `configPath`,
  `environmentFile`, `extraFlags`, `package`; alloy 5.1.0 in nixos-25.11)
- **Promtail is EOL as of 2026-03-02** — Grafana has ended commercial support and will not
  issue future updates. `services.alloy` is the official replacement. Do not add new promtail
  instances.
- Alloy uses the River/Alloy config syntax (`.alloy` files), not YAML

### Why NOT other approaches

**Option B — expose Loki via Caddy on pebble with auth:**
- Makes Loki reachable from the internet (even with auth)
- `auth_enabled = false` in current Loki config means no tenant isolation or push auth
- Traffic routes pebble ↔ Cloudflare ↔ VPS instead of direct mesh
- Adds attack surface without meaningful benefit when VPN is available

**Option C — Promtail on VPS:**
- Promtail is EOL (2026-03-02). Do not use for new deployments.

---

## Security analysis

| Property | Alloy/NetBird (recommended) | Caddy/public (avoid) |
|---|---|---|
| Network exposure | None — WireGuard mesh only | Loki HTTP API internet-reachable |
| Authentication required | No (private mesh; only NetBird peers can reach pebble's Loki) | Yes (and `auth_enabled=false` means no push auth exists) |
| Encryption in transit | WireGuard (always on) | TLS, but publicly routable |
| Loki DoS risk | Only NetBird peers | Anyone who can route to the endpoint |
| New firewall rules on pebble | One rule: allow port 3100 from NetBird interface only | Open port 3100 or 443 publicly |
| Complexity | Low | Medium (Caddy virtual host + auth setup) |

**Key risk with the recommended approach:** Loki currently binds `http_listen_address = "127.0.0.1"`.
To receive pushes from the VPS over the mesh, this must be changed to also listen on pebble's
NetBird interface IP. The safest change is to bind on the specific NetBird IP (e.g. `100.x.x.x`),
not `0.0.0.0`. The firewall rule must restrict port 3100 to the NetBird interface only.

---

## Implementation plan

### Step 1 — find pebble's NetBird IP

```bash
just netbird-status   # shows mesh IP, e.g. 100.102.154.38
```

This IP goes into the Alloy `loki.write` endpoint on the VPS.

### Step 2 — update Loki bind address on pebble

In `homelab/loki/default.nix`, change `http_listen_address` to accept connections from the
NetBird interface. Two options:

**Option A (specific IP — safer):**
```nix
server = {
  http_listen_port = cfg.port;
  http_listen_address = "0.0.0.0";  # bind all; restrict via firewall below
};
```

**Option B (stay on loopback and add a second listen — not supported by Loki single-process):**
Loki does not support multiple `http_listen_address` values. Use `0.0.0.0` + firewall.

**Firewall rule (pebble — restrict port 3100 to NetBird interface only):**
```nix
# In machines/nixos/pebble/default.nix or homelab/loki/default.nix
networking.firewall.interfaces."wt0".allowedTCPPorts = [ 3100 ];
# wt0 is the NetBird WireGuard interface name (verify with: ip link show)
```

This is safe: `networking.firewall.interfaces.<iface>.allowedTCPPorts` only opens the port
on that specific interface. Port 3100 remains closed on `eth0` (LAN) and all other interfaces.

### Step 3 — create `machines/nixos/vps/monitoring.nix`

Alloy uses River syntax (`.alloy` files). The `loki.source.journal` component reads journald.

```nix
# machines/nixos/vps/monitoring.nix
{ pkgs, ... }:
{
  services.alloy = {
    enable = true;
    configPath = "/etc/alloy/config.alloy";
  };

  environment.etc."alloy/config.alloy".text = ''
    loki.source.journal "vps_journal" {
      max_age       = "12h"
      relabel_rules = loki.relabel.vps_labels.rules
      forward_to    = [loki.write.pebble.receiver]
    }

    loki.relabel "vps_labels" {
      forward_to = []
      rule {
        source_labels = ["__journal__systemd_unit"]
        target_label  = "unit"
      }
      rule {
        replacement  = "vps"
        target_label = "host"
      }
      rule {
        replacement  = "systemd-journal"
        target_label = "job"
      }
    }

    loki.write "pebble" {
      endpoint {
        # Replace with pebble's NetBird IP (run: just netbird-status)
        url = "http://100.102.154.38:3100/loki/api/v1/push"
      }
    }
  '';

  # Alloy state directory (WAL, positions)
  systemd.tmpfiles.rules = [
    "d /var/lib/alloy 0750 alloy alloy -"
  ];
}
```

### Step 4 — import in VPS default.nix

```nix
# machines/nixos/vps/default.nix
imports = [
  ./disko.nix
  ./netbird-server.nix
  ./caddy.nix
  ./monitoring.nix          # ← add this
  ../../../modules/podman
];
```

### Step 5 — add Grafana datasource label filter (optional but recommended)

After shipping VPS logs, add a label selector in Grafana to distinguish pebble vs vps:
- pebble logs: `{host="pebble", job="systemd-journal"}`
- VPS logs: `{host="vps", job="systemd-journal"}`

No Grafana config changes needed — the labels are set by Alloy relabeling. Filtering is done
in LogQL at query time.

---

## Known gotchas

- **Alloy config syntax** — River/Alloy `.alloy` syntax, not YAML. The `loki.source.journal`
  component is a first-class Alloy component (not a promtail shim). Verify the component name
  hasn't changed from `loki.source.journal` in the nixpkgs-packaged Alloy version (5.1.0).

- **`alloy` user/group** — `services.alloy` creates these automatically. No manual setup needed.

- **`systemd.tmpfiles.rules` for `/var/lib/alloy`** — Alloy needs a writable state dir for its
  WAL (write-ahead log). The NixOS module may or may not create this automatically; add the
  tmpfiles rule as a precaution (same pattern as the promtail `226/NAMESPACE` fix on pebble).

- **NetBird must be connected** — if the VPS NetBird peer disconnects (e.g. coturn/STUN issue),
  Alloy will buffer logs in its WAL and retry. This is safe; no logs are lost while buffered
  (up to WAL size limit).

- **Loki `reject_old_samples_max_age = "168h"` (7 days)** — current pebble Loki config rejects
  log entries older than 7 days. Alloy's WAL will hold logs during mesh outages. If the mesh
  is down for more than 7 days, buffered logs will be rejected by Loki. Acceptable for a homelab.

- **`http_listen_address` is a string in Loki config** — the NixOS Loki module passes this as
  an attrset key under `server`. Verify the exact key name matches (`http_listen_address`, not
  `listenAddress`).

---

## Verification steps (after implementation)

```bash
# 1. Confirm Alloy is running on VPS
ssh admin@204.168.181.110 systemctl status alloy

# 2. Confirm Alloy can reach pebble Loki
ssh admin@204.168.181.110 curl -s http://100.102.154.38:3100/ready

# 3. Query Loki from pebble for VPS logs
# In Grafana → Explore → Loki:
#   {host="vps"} | limit 20

# 4. Confirm pebble logs are unaffected
#   {host="pebble"} | limit 20
```

---

## Files to create/modify

| File | Action |
|---|---|
| `machines/nixos/vps/monitoring.nix` | CREATE — Alloy config |
| `machines/nixos/vps/default.nix` | MODIFY — add `./monitoring.nix` to imports |
| `homelab/loki/default.nix` | MODIFY — change `http_listen_address` to `0.0.0.0` |
| `machines/nixos/pebble/default.nix` | MODIFY — add `networking.firewall.interfaces."wt0".allowedTCPPorts = [ 3100 ]` |

Estimated complexity: **Low**. All components exist in nixpkgs, no new secrets required,
NetBird mesh provides the transport.
