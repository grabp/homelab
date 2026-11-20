---
kind: handoff
created: 2026-11-20
service: zigbee2mqtt
machine: pebble
status: scaffolded, never built, never deployed
delete_when: zigbee2mqtt is deployed and PROGRESS.md says COMPLETE
---

# Handoff — Zigbee2MQTT on pebble, migrating off HA's ZHA

Scaffolded on a macOS machine that cannot build x86_64 or decrypt sops, so
nothing here has been built or deployed. Everything below needs doing on the
Linux box. Delete this file once the service is up.

## What this change does

Adds Zigbee2MQTT as a native NixOS service on pebble and takes the Zigbee
coordinator (Home Assistant Connect ZBT-1, Silabs EFR32 / EmberZNet 7.5.1.0)
away from Home Assistant. ZHA stops being available; Zigbee devices reach HA
over MQTT discovery through the existing Mosquitto broker instead.

The existing Zigbee network is **migrated, not rebuilt** — devices do not need
re-pairing, provided the steps below are followed in order.

## Files already changed (committed, not verified)

| File | Change |
|------|--------|
| `homelab/zigbee2mqtt/default.nix` | new — `my.services.zigbee2mqtt`, native `services.zigbee2mqtt` |
| `homelab/zigbee2mqtt/README.md` | new — includes the full Migration section; read it before touching anything |
| `homelab/home-assistant/default.nix` | removed `--device=/dev/ttyUSB0:/dev/ttyUSB0` from the container |
| `homelab/home-assistant/README.md` | documents that ZHA is gone and why |
| `homelab/mosquitto/default.nix` | new broker user `zigbee2mqtt` + ACL + password hash |
| `homelab/caddy/default.nix` | `@zigbee host zigbee.${vars.domain}` → `127.0.0.1:8090` |
| `homelab/default.nix` | imports `./zigbee2mqtt` |
| `machines/nixos/pebble/default.nix` | `my.services.zigbee2mqtt.enable = true` |
| `homelab/homepage/{default.nix,README.md}` | dashboard tile under Home Automation |
| `scripts/hex2bytes.py` | new — converts backup hex fields to the decimal byte arrays z2m requires |
| `PROGRESS.md` | row marking this SCAFFOLDED and blocked on secrets |

Design choices worth not re-litigating: native module over OCI (it exists in
the locked nixpkgs and brings systemd hardening plus `dialout` handling);
frontend bound to `127.0.0.1:8090` because it has no auth of its own and 8080
is docs-site; `adapter = "ember"` because the ZBT-1 is Silabs and autodetect
can land on the legacy `ezsp` driver; secrets delivered as
`ZIGBEE2MQTT_CONFIG_*` env vars because `services.zigbee2mqtt.settings` is
serialised into the world-readable Nix store.

## THE ONE IRREVERSIBLE STEP

The NixOS module's `preStart` copies `configuration.yaml` from the store on
every start, so z2m cannot persist a generated network key. If z2m's **first**
start happens with no `/var/lib/zigbee2mqtt/coordinator_backup.json` and
unpinned parameters, it re-forms the Zigbee network on the coordinator and
every paired device is orphaned for good. There is no undo.

`machines/nixos/pebble/default.nix` currently has `enable = true`. Set it to
`false` for the first deploy, place the backup, then flip it back.

## Inputs you must carry from the macOS machine

1. **The ZHA coordinator backup.** `~/Documents/ZHA backup 2026-11-20T15-57-23.554Z.json`
   on the Mac. Verified complete: `source: bellows@0.49.0`, full 16-byte
   `network_key`, `channel: 25`, 4 children / 5 `nwk_addresses`. Contains the
   network key and the TC link key — move it over a trusted channel and keep it
   out of git.
   If more than ~5 devices are paired today, that backup is stale; take a fresh
   one from HA (Settings → Devices & services → ZHA → Configure → Network
   settings) before starting.
2. **The MQTT password.** Generated on the Mac into a session scratchpad that
   is now gone — though if the sops entry from step 5 already contains it, it
   is recoverable with `just edit-secrets-pebble` and nothing needs carrying. The hash committed in `homelab/mosquitto/default.nix`
   (`$7$101$ZbXpXd1n…`) pairs with that password. If it was not saved to a
   password manager, generate a new one and replace the hash — see step 4.

## Steps

1. `just setup-local` — decrypts the VPS IP into gitignored
   `machines/nixos/local.nix`. Nothing evaluates without it; this is also why
   `nix flake check` was never run (see Verification below).
2. Set `my.services.zigbee2mqtt.enable = false` in
   `machines/nixos/pebble/default.nix`.
3. Extract the secret values from the backup:
   ```bash
   scripts/hex2bytes.py -f <backup>.json -k network_key -e
   scripts/hex2bytes.py -f <backup>.json -k ext_pan_id  -e
   python3 -c 'import json,sys;print(int(json.load(open(sys.argv[1]))["network_info"]["pan_id"],16))' <backup>.json
   ```
   `-f` reads from the file rather than argv, keeping the key out of shell
   history and out of `ps`.
4. MQTT password. If you saved the one from the Mac, use it as-is. Otherwise:
   ```bash
   PW=$(openssl rand -base64 24)
   nix shell nixpkgs#mosquitto --command mosquitto_passwd -c -b /tmp/p zigbee2mqtt "$PW"
   sed 's/^zigbee2mqtt://' /tmp/p   # replace the hash in homelab/mosquitto/default.nix
   rm /tmp/p
   ```
5. **Appears already done** — `secrets/pebble.yaml` gained a `zigbee2mqtt: env:`
   entry at 2026-11-20T16:50Z (sops 3.13.3), which is the right path for the
   module's `sops.secrets."zigbee2mqtt/env"`. Its contents could not be checked
   from the Mac (no decryption key), so open it once with
   `just edit-secrets-pebble` and confirm three things before deploying:
   the network key came from the ZHA backup rather than being generated; the
   password matches the hash committed in `homelab/mosquitto/default.nix`; and
   all four lines are present. If any doubt, redo steps 3-4.

   Expected shape, same nesting style as `caddy/env`:
   ```
   zigbee2mqtt:
     env: |
       ZIGBEE2MQTT_CONFIG_MQTT_PASSWORD=<from step 4>
       ZIGBEE2MQTT_CONFIG_ADVANCED_NETWORK_KEY=<from step 3>
       ZIGBEE2MQTT_CONFIG_ADVANCED_PAN_ID=<from step 3>
       ZIGBEE2MQTT_CONFIG_ADVANCED_EXT_PAN_ID=<from step 3>
   ```
   No new `.sops.yaml` creation rule is needed — the existing
   `secrets/pebble\.yaml$` rule covers it.
6. `just check`, then `just build`. Both are untried — expect to fix real
   errors here, not just typos.
7. Snapshot the ZFS dataset holding `/var/lib/homeassistant` so `zigbee.db`
   survives as a rollback.
8. In HA: Settings → Devices & services → ZHA → ⋮ → **Disable**. Then on pebble
   `systemctl stop podman-homeassistant` to free the serial port. Both stacks
   driving the radio at once corrupts things regardless of backups.
9. `just deploy pebble` (still `enable = false`) so the `zigbee2mqtt` user and
   group exist.
10. Place the backup where z2m restores from (`dist/zigbee.js`, `backupPath`):
    ```bash
    install -d -o zigbee2mqtt -g zigbee2mqtt -m 0700 /var/lib/zigbee2mqtt
    install -o zigbee2mqtt -g zigbee2mqtt -m 0600 <backup>.json \
      /var/lib/zigbee2mqtt/coordinator_backup.json
    ```
    This is also the only route for the TC link key — there is no config option
    for it. A stale `tx_counter` is fine; the frame counter is bumped on
    restore.
11. Confirm the serial device. `ls -l /dev/serial/by-id/` on pebble; if the
    ZBT-1 shows a stable by-id path, set
    `my.services.zigbee2mqtt.serialPort` to it. The stick is a CP2102N so it
    lands on `ttyUSB0` today, but that number is not stable if another USB
    serial device ever appears.
12. Flip `enable = true`, `just deploy pebble`, then
    `journalctl -fu zigbee2mqtt`. Mains-powered devices report within a minute;
    battery devices when they next wake (trip a door sensor to hurry it).

## After it is up

- Delete the HA ZHA integration (not just disable) to free the old entity IDs,
  then set each device's `friendly_name` in the z2m frontend to its old name
  before fixing automations and dashboards. Entity IDs change regardless — this
  only limits the blast radius.
- Rebuild Zigbee groups and binds in the frontend; they do not migrate.
- `permit_join` is deployed as `false`. Turn it on from the frontend only while
  adding a device.
- Check `https://zigbee.${vars.domain}` resolves — Pi-hole already answers the
  wildcard `address=/${vars.domain}/${pebbleIP}`, so no DNS record was added.
- Update `PROGRESS.md` (the row currently says SCAFFOLDED) and delete this file.

## Verification status — read before trusting any of this

`nix flake check` **was never run successfully.** It fails during evaluation
with `error: VPS IP not set: create machines/nixos/local.nix`, which is the
pre-existing `just setup-local` requirement; `just setup-local` itself failed on
the Mac with `Recovery failed because no master key was able to decrypt the
file` (no sops key present there). Nothing in this change was built.

What *was* verified, by lazy evaluation of `.#nixosConfigurations.pebble` plus
reading the 2.6.3 package source:

- All edited `.nix` files parse; `settings` renders as expected
  (`adapter = "ember"`, `channel = 25`, `frontend` on `127.0.0.1:8090`,
  `mqtt.server = mqtt://127.0.0.1:1883`, `homeassistant.enabled = true`).
- `systemd.services.zigbee2mqtt` gets `EnvironmentFile =
  [ "/run/secrets/zigbee2mqtt/env" ]`; `DeviceAllow = [ "/dev/ttyUSB0" ]`.
- HA's `extraOptions` no longer contains the device.
- Caddy emits the `@zigbee` block to `127.0.0.1:8090`; the mosquitto listener
  carries the new user and ACL.
- `ZIGBEE2MQTT_CONFIG_*` overrides exist in this exact version
  (`dist/util/settings.js`, `applyEnvironmentVariables`) and JSON-parse array
  and number types, so the byte-array form works.
- The committed mosquitto hash was checked against the generated password by
  recomputing PBKDF2-HMAC-SHA512 (101 iterations, stored salt, 64-byte output).
- The store-generated `zigbee2mqtt.yaml` could **not** be realised — it is an
  x86_64-linux derivation and the Mac had no remote builder.

## Rollback

Valid only while z2m has not re-formed the network: `systemctl stop
zigbee2mqtt`, re-add `--device=/dev/ttyUSB0:/dev/ttyUSB0` to the HA container,
re-enable the ZHA integration, restore the snapshot from step 7. Once a new
network has been formed on the coordinator, rollback means re-pairing every
device by hand.
