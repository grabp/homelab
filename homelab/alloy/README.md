---
service: alloy
stage: 10
machine: pebble, vps, boulder
status: deployed
---

# Alloy

## Purpose

Grafana Alloy log shipper. Reads the systemd journal and pushes log streams to
Loki using the River (`.alloy`) config syntax. Replaced EOL Promtail in Stage 10.

Runs on every machine that ships logs:

| Machine | Target | Transport |
|---------|--------|-----------|
| pebble | `localhost:3100` | loopback |
| vps | `100.102.154.38:3100` | NetBird overlay (wt0) |
| boulder | `192.168.10.50:3100` | LAN (eth0) |

Enabled automatically on pebble when `my.services.loki` is enabled. Enabled
explicitly on vps and boulder via `my.services.alloy`.

## Ports

No inbound ports. Alloy only makes outbound push requests to Loki.

## Secrets

None.

## Depends on

- Loki reachable at the configured `lokiUrl` — push fails silently if Loki is down
  (Alloy retries with backoff; logs are buffered in the WAL up to disk limits)
- pebble firewall: port 3100 open on `wt0` (VPS) and `eth0` (boulder)

## DNS

Not applicable.

## OIDC

Not applicable.

## Known gotchas

- Config lives at `/etc/alloy/config.alloy` via `environment.etc`. If the file
  was previously written as a regular file (not a symlink), NixOS will not
  overwrite it on redeploy — delete it manually and redeploy.
- River/Alloy syntax (`.alloy` files) is **not** YAML. Component IDs must be
  unique within a pipeline — use `loki.write.pebble`, not `loki.write.default`.
- `/var/lib/alloy` must be pre-created with correct ownership (`alloy:alloy 0750`)
  via `systemd.tmpfiles.rules` — Alloy will fail to start otherwise.
- `hostLabel` becomes the `host=` label on all log streams. It must match the
  machine hostname for Loki alert rules (`host="pebble"`, `host="vps"`, etc.) to
  fire correctly.
- Promtail is EOL as of 2026-03-02 — do not add new Promtail instances.

## Backup / restore

State: `/var/lib/alloy/` — WAL (write-ahead log) and journal position tracking.
The WAL buffers unsent log batches; loss means those batches are dropped, not
the underlying journal entries. Not critical to back up.
