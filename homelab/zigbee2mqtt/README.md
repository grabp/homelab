---
service: zigbee2mqtt
stage: extra
machine: pebble
status: scaffolded
---

# Zigbee2MQTT

## Purpose

Zigbee coordinator bridge. Talks to the USB coordinator over serial, publishes
device state to Mosquitto, and exposes devices to Home Assistant via MQTT
discovery. Replaces Home Assistant's built-in ZHA integration — the two cannot
share one coordinator stick.

Runs as a native NixOS service (`services.zigbee2mqtt`), not a container, so it
inherits the upstream module's systemd hardening and `dialout` group handling.

## Ports

| Port | Protocol | Exposed | Purpose |
|------|----------|---------|---------|
| 8090 | TCP | localhost only | Web frontend (Caddy proxies `zigbee.${domain}` here) |
| 1883 | TCP | outbound | MQTT client connection to Mosquitto on 127.0.0.1 |

The frontend has **no authentication of its own** and is bound to 127.0.0.1.
Do not move it to `0.0.0.0`.

## Hardware

| Item | Value |
|------|-------|
| Adapter | Home Assistant Connect ZBT-1 (Silabs EFR32, EmberZNet) |
| Driver | `ember` (`my.services.zigbee2mqtt.adapter`) — not the legacy `ezsp` |
| Serial device | `/dev/ttyUSB0` (`my.services.zigbee2mqtt.serialPort`) |
| Channel | 25 (`my.services.zigbee2mqtt.channel`) |
| Exclusive? | Yes — removed from the Home Assistant container's `--device` list |

If a second USB serial device is ever plugged into pebble, switch `serialPort`
to a `/dev/serial/by-id/...` path; `ttyUSB` numbering is not stable.

## Secrets

`secrets/pebble.yaml` → key `zigbee2mqtt/env`, env-file format:

```
ZIGBEE2MQTT_CONFIG_MQTT_PASSWORD=<plaintext password>
ZIGBEE2MQTT_CONFIG_ADVANCED_NETWORK_KEY=[<16 bytes, comma separated>]
ZIGBEE2MQTT_CONFIG_ADVANCED_PAN_ID=<1-65534>
ZIGBEE2MQTT_CONFIG_ADVANCED_EXT_PAN_ID=[<8 bytes, comma separated>]
```

Edit with `just edit-secrets-pebble`.

Only `MQTT_PASSWORD` is generated — `openssl rand -base64 24` is plenty, since
the broker is LAN-only and the credential is never typed by a human.

The three Zigbee values are **migration values read out of the ZHA coordinator
backup**, not fresh randomness. Generating them forms a new network and
permanently orphans every paired device. See the Migration section below.

```bash
scripts/hex2bytes.py -f <zha-backup>.json -k network_key -e
scripts/hex2bytes.py -f <zha-backup>.json -k ext_pan_id  -e
python3 -c 'import json,sys;print(int(json.load(open(sys.argv[1]))["network_info"]["pan_id"],16))' <zha-backup>.json
```

For a genuinely new network with nothing paired, generate the key with
`python3 -c 'import secrets;print("["+",".join(str(b) for b in secrets.token_bytes(16))+"]")'`
and let `pan_id`/`ext_pan_id` default to `GENERATE` — but then pin whatever
Zigbee2MQTT picks, because this module's `preStart` overwrites the file it
would otherwise persist them in.

These go through env vars rather than `services.zigbee2mqtt.settings` because
the NixOS module serialises `settings` into the world-readable Nix store.
Zigbee2MQTT applies `ZIGBEE2MQTT_CONFIG_*` overrides on top of
`configuration.yaml` (`dist/util/settings.js`, `applyEnvironmentVariables`).

The same password also needs a **hash** in `homelab/mosquitto/default.nix` for
the `zigbee2mqtt` broker user:

```bash
nix shell nixpkgs#mosquitto --command mosquitto_passwd -c -b /tmp/p zigbee2mqtt '<password>'
cat /tmp/p   # paste the part after "zigbee2mqtt:"
```

Rotating one means rotating both: the sops plaintext and the module's hash are
the same credential in two places.

## Depends on

- `my.services.mosquitto` — broker; unit orders `after`/`wants` on it
- `my.services.caddy` — TLS frontend at `zigbee.${domain}`
- Home Assistant MQTT integration (configured in the HA UI, not in Nix)

## DNS

Covered by the Pi-hole wildcard `address=/${domain}/${pebbleIP}` — no
per-service record. Caddy routes `zigbee.${domain}` inside the wildcard block.

## OIDC

None. Zigbee2MQTT has no OIDC support. Access control is "LAN + wildcard DNS
only"; if it needs to be guarded, put it behind `oauth2-proxy` the way Homepage
is (see `homelab/homepage/default.nix`).

## Known gotchas

- **The module rewrites `configuration.yaml` on every start.** `preStart` copies
  the store copy over the live file, so anything Zigbee2MQTT writes back is
  lost. This is why `network_key`, `pan_id`, and `ext_pan_id` must be pinned
  explicitly and never left as `GENERATE` — a regenerated key silently orphans
  every paired device.
- **`devices.yaml` / `groups.yaml` survive**, because the upstream module keeps
  device/group state in separate files inside `/var/lib/zigbee2mqtt`.
- **Coordinator conflict:** re-adding `--device=/dev/ttyUSB0` to the HA
  container will make ZHA and Zigbee2MQTT fight over the serial port; symptoms
  are random coordinator disconnects on both sides.
- **`permit_join = false`** is the deployed state. Turn pairing on from the
  frontend only while adding a device, and turn it back off.
- Migrating from ZHA means **re-pairing every Zigbee device** — the networks
  are separate, and device names/entity IDs in HA will change.

## Migration from ZHA (one-time, 2026-11-20)

Devices do **not** need re-pairing. ZHA and Zigbee2MQTT drive the same
coordinator (HA Connect ZBT-1, Silabs EFR32/EmberZNet), and a Zigbee network
identity is just `network_key` + `pan_id` + `ext_pan_id` + `channel`. Clone
those and the existing network keeps working.

Values come from the ZHA network backup (`source: bellows@0.49.0`,
`backup_time: 2026-11-20T15:57:23Z`). Only the channel is recorded in this
repo; the rest stay in sops, since `pan_id` and `ext_pan_id` identify the
network even though they are not secret like the key is.

| Field | JSON path in the backup | Where it goes |
|-------|-------------------------|---------------|
| channel | `network_info.channel` | `my.services.zigbee2mqtt.channel` (= 25) |
| pan_id | `network_info.pan_id` (bare hex) | sops `zigbee2mqtt/env`, as decimal |
| ext_pan_id | `network_info.extended_pan_id` | sops `zigbee2mqtt/env`, as byte array |
| network_key | `network_info.network_key.key` | sops `zigbee2mqtt/env`, as byte array |
| tc_link_key | `network_info.tc_link_key.key` | nowhere — restored from `coordinator_backup.json` |

Zigbee2MQTT's schema rejects hex strings for these (`advanced.network_key:
should be array or 'GENERATE'`), so they need converting to decimal byte
arrays. `scripts/hex2bytes.py` does that straight out of the backup file.

**Zigbee2MQTT's first start is the destructive step.** With no
`coordinator_backup.json` and `GENERATE`d parameters it re-forms the network on
the stick, which permanently orphans every paired device. Keep
`my.services.zigbee2mqtt.enable = false` until the backup file is in place.

Order:

1. Snapshot the ZFS dataset holding `/var/lib/homeassistant` (keeps `zigbee.db`
   for rollback).
2. In HA: Settings → Devices & services → ZHA → ⋮ → Disable. Then
   `systemctl stop podman-homeassistant` to free the serial port.
3. Deploy with `zigbee2mqtt.enable = false` so the `zigbee2mqtt` user exists.
4. Copy the ZHA backup in as the coordinator backup:
   ```bash
   install -d -o zigbee2mqtt -g zigbee2mqtt -m 0700 /var/lib/zigbee2mqtt
   install -o zigbee2mqtt -g zigbee2mqtt -m 0600 zha-backup.json \
     /var/lib/zigbee2mqtt/coordinator_backup.json
   ```
   Zigbee2MQTT reads this path (`dist/zigbee.js`, `backupPath`) and restores
   rather than forming a new network. The format ZHA exports is the open
   coordinator backup format it expects. A stale `tx_counter` is fine — the
   frame counter is bumped on restore.
5. Add `zigbee2mqtt/env` to `secrets/pebble.yaml`, hash the password into
   `homelab/mosquitto/default.nix`, flip `enable = true`, deploy.
6. `journalctl -fu zigbee2mqtt`. Mains-powered devices report within a minute;
   battery devices when they next wake.

Not carried over — redo by hand:

- **Entity IDs.** Zigbee2MQTT publishes fresh MQTT-discovery entities. Delete
  the ZHA integration (not just disable) to free the old IDs, then set each
  device's `friendly_name` in the frontend to the old name before fixing
  automations and dashboards.
- **Groups and binds.** Zigbee groups and reporting configs must be rebuilt in
  the frontend (`groups.yaml`).
- Devices paired after the backup was taken are absent from the restored tables
  and need individual re-pairing.

Rollback (valid only while Zigbee2MQTT has not re-formed the network): stop
`zigbee2mqtt`, re-add `--device=/dev/ttyUSB0:/dev/ttyUSB0` to the HA container,
re-enable ZHA, restore the snapshot.

## Backup/restore

State lives in `/var/lib/zigbee2mqtt` (`devices.yaml`, `groups.yaml`,
`database.db`, `coordinator_backup.json`). Covered by the pebble ZFS dataset
snapshots/restic job in `homelab/backup/`.

Restoring onto a new coordinator stick also requires the same
`ZIGBEE2MQTT_CONFIG_ADVANCED_*` values from sops — the backup alone is not
enough to rejoin the existing Zigbee network.
