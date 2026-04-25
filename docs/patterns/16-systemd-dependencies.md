---
kind: pattern
number: 16
tags: [systemd, dependencies, firewall, sops, ordering]
---

# Pattern 16: systemd restart and ordering dependencies for homelab services

Three recurring situations require explicit systemd dependencies in this homelab. Apply them mechanically using the decision table below.

## A — OCI containers with published ports (Netavark DNAT flush)

**Problem:** When `nixos-rebuild switch` changes any `networking.firewall.*` option, NixOS reloads `firewall.service`, which flushes and rewrites all iptables chains — including `NETAVARK_INPUT` and `NETAVARK_FORWARD` that Podman/Netavark wrote for port DNAT. If the container is not restarted after the flush, its published ports become unreachable from the network even though the container is still running. The symptom is a timeout (not a connection refused), because the iptables DNAT rule is simply gone.

**Rule:** Any OCI container using Podman's default bridge network with `ports = [...]` needs `partOf`/`after firewall.service`. Containers using `--network=host` publish no ports via Netavark and are not affected.

```nix
# In the service module (e.g. homelab/pihole/default.nix)
systemd.services.podman-<name> = {
  after  = [ "firewall.service" ];  # start after rules are written
  partOf = [ "firewall.service" ];  # restart whenever firewall restarts
};
```

**Applies to these homelab containers:**

| Container | Network mode | Needs fix? |
|-----------|-------------|------------|
| pihole | bridge (`ports = [...]`) | ✅ Yes — implemented |
| homeassistant | `--network=host` | ❌ No |
| esphome | `--network=host` | ❌ No |
| matter-server | `--network=host` | ❌ No |

## B — Services that read sops secrets via EnvironmentFile

**Problem:** sops-nix decrypts secrets during the NixOS activation script (before services start). If a secret value changes in a subsequent deploy, the activation re-decrypts the file, but the running service still has the old value in its environment. Without `restartUnits`, the service is never told to reload.

**Rule:** Any service that reads a secret via `serviceConfig.EnvironmentFile` (not via a config file the service re-reads on SIGHUP) needs `restartUnits` on its sops secret declaration so sops-nix triggers a service restart after re-decryption.

```nix
sops.secrets."service/env" = {
  owner        = config.services.<name>.user;  # if the service runs as non-root
  restartUnits = [ "<name>.service" ];         # restart after secret changes
};
```

**Apply to:**

| Secret | Service | restartUnits needed? |
|--------|---------|----------------------|
| `caddy/env` (CLOUDFLARE_API_TOKEN) | `caddy.service` | ✅ implemented |
| `pihole/env` (web password) | `podman-pihole.service` | ⚠ not yet — low priority (password changes are rare) |
| `grafana_admin_password` | `grafana.service` | ⚠ add in Stage 5 |
| `netbird/setup_key` | n/a — login.enable not used; key is for one-time manual step | ✅ intentional (Stage 7b) |

Note: Grafana injects its admin password via `$__file{/run/secrets/...}` syntax in `settings.security.admin_password`, not via EnvironmentFile — but it still needs a restart to pick up a changed secret because Grafana reads the file at startup, not on every request.

## C — Service start ordering across dependent services

**Problem:** Some services fail or produce errors at startup if their dependencies aren't ready yet. `After` establishes ordering without creating a hard dependency; `Requires` (or `wants` for a soft dependency) additionally ensures the dependency is started.

**Rule:** Use `after` + `wants` (soft: best-effort) when the dependent service retries connections on its own. Use `after` + `requires` (hard) only when the service will crash without the dependency.

```nix
# Home Assistant — MQTT broker should be up before HA tries to connect
systemd.services.podman-homeassistant = {
  after = [ "mosquitto.service" ];
  wants = [ "mosquitto.service" ];  # soft: HA retries MQTT connections anyway
};

# ESPHome and Matter Server — mDNS requires Avahi to be running
systemd.services.podman-esphome = {
  after = [ "avahi-daemon.service" ];
  wants = [ "avahi-daemon.service" ];
};

systemd.services.podman-matter-server = {
  after = [ "avahi-daemon.service" ];
  wants = [ "avahi-daemon.service" ];
};

# Promtail — log shipper should start after Loki is ready to receive
systemd.services.promtail = {
  after = [ "loki.service" ];
  wants = [ "loki.service" ];
};
```

**Full dependency picture for this homelab:**

```
firewall.service
    └─ partOf ─▶ podman-pihole.service
                     └─ (Pi-hole DNS used by Caddy, NetBird, pebble system)

mosquitto.service
    └─ wants/after ─▶ podman-homeassistant.service

avahi-daemon.service
    ├─ wants/after ─▶ podman-esphome.service
    └─ wants/after ─▶ podman-matter-server.service

loki.service
    └─ wants/after ─▶ promtail.service
```

Native services (Prometheus, Grafana, Loki, Uptime Kuma, Homepage, Mosquitto, Wyoming pipeline) need no special ordering beyond what systemd's default `After=network.target` provides — they all bind to localhost and retry connections internally.

**Source:** Discovered via live debugging (Netavark flush). `partOf` and `wants` semantics from systemd man pages. `restartUnits` from sops-nix README ✅.
