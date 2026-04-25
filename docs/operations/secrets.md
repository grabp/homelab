---
kind: runbook
tags: [secrets, sops, sops-nix]
---

# Secrets Management Runbook

## Overview

Secrets encrypted with sops-nix using age. Each host decrypts at boot via SSH host key. Admin edits via age key at `~/.config/sops/age/keys.txt`.

**Files:**
- `.sops.yaml` — age keys + creation rules
- `secrets/secrets.yaml` — pebble secrets (encrypted)
- `secrets/vps.yaml` — VPS secrets (encrypted)
- `/run/secrets/<name>` — decrypted on target (tmpfs, ephemeral)

**Full details:** [docs/roadmap/stage-02-secrets.md](../roadmap/stage-02-secrets.md), [docs/patterns/06-sops-secrets.md](../patterns/06-sops-secrets.md)

---

## Adding a New Secret

```bash
# 1. Edit secrets file
just edit-secrets        # pebble
just edit-secrets-vps    # VPS

# 2. Add in YAML format (plaintext password or key=value env file)
# grafana/admin_password: "YourPasswordHere"
# alertmanager/telegram_env: |
#   TELEGRAM_BOT_TOKEN=123:ABC...
#   TELEGRAM_CHAT_ID=123456

# 3. Declare in NixOS module
# sops.secrets."grafana/admin_password" = {
#   owner = "grafana";
#   restartUnits = [ "grafana.service" ];
# };

# 4. Deploy
just deploy pebble
```

Decrypted to `/run/secrets/<name>` on target. Reference via `config.sops.secrets."name".path`.

---

## Rotating a Secret

```bash
just edit-secrets
# Update value, save, exit

just deploy pebble
# If restartUnits declared, service auto-restarts
```

---

## Adding a New Host

When adding a machine (e.g., `boulder`):

```bash
# 1. Generate SSH host key
just gen-boulder-hostkey

# 2. Derive age key
nix shell nixpkgs#ssh-to-age -c sh -c \
  'ssh-to-age < machines/nixos/boulder/keys/ssh_host_ed25519_key.pub'
# Output: age1xxxxx...

# 3. Add to .sops.yaml
# keys:
#   - &boulder age1xxxxx...
# creation_rules:
#   - path_regex: secrets/secrets\.yaml$
#     key_groups:
#       - age: [*admin, *pebble, *boulder]

# 4. Rekey all secrets
just rekey
```

---

## Rekeying

After adding/removing hosts or rotating SSH keys:

```bash
just rekey
# Re-encrypts secrets without changing plaintext
```

---

## Recovery (Lost Admin Key)

```bash
# 1. Copy host SSH private key from target
ssh admin@192.168.10.50 sudo cat /etc/ssh/ssh_host_ed25519_key > /tmp/host_key

# 2. Derive age key
nix shell nixpkgs#ssh-to-age -c sh -c \
  'ssh-to-age -private-key -i /tmp/host_key'
# Output: AGE-SECRET-KEY-1XXXX...

# 3. Save to ~/.config/sops/age/keys.txt

# 4. Verify
sops secrets/secrets.yaml
```

---

## Secret Permissions

**Defaults:** owner=root, group=root, mode=0400

**Custom (service user):**
```nix
sops.secrets."service/secret" = {
  owner = "servicename";
  mode = "0400";  # read-only for owner
};
```

**Shared (multiple services):**
```nix
# Kanidm client secret read by both Kanidm and Grafana
sops.secrets."kanidm/grafana_client_secret" = {
  owner = "kanidm";
  group = "grafana";
  mode = "0440";  # read for owner and group
  restartUnits = [ "grafana.service" ];  # can declare in multiple modules
};
```

---

## Environment Files

For systemd `EnvironmentFile` (KEY=VALUE format):

```yaml
# secrets/secrets.yaml
pihole/env: |
  WEBPASSWORD=admin123
  FTLCONF_REPLY_ADDR4=192.168.10.50
```

```nix
sops.secrets."pihole/env" = { };

virtualisation.oci-containers.containers.pihole = {
  environmentFiles = [ config.sops.secrets."pihole/env".path ];
};
```

---

## Common Patterns

See `homelab/*/default.nix` for examples.

**Simple password:** YAML value, declare with `owner` + `restartUnits`, reference via `config.sops.secrets."name".path`.

**Environment file:** YAML multi-line (`key: |`), use as `environmentFile`, systemd loads KEY=VALUE pairs.

**Shared secret:** Same secret declared in multiple modules with `owner`, `group`, `mode = "0440"`. sops-nix merges declarations.

---

## Debugging

**Secret not decrypting:** `ls -l /run/secrets/`, `systemctl status sops-nix`, `journalctl -u sops-nix`. Verify `/etc/ssh/ssh_host_ed25519_key` exists.

**Permission denied:** `ls -l /run/secrets/<name>`, `id <servicename>`. Check owner/mode match sops declaration.

**Age key mismatch:** `ssh-to-age < machines/nixos/<host>/keys/ssh_host_ed25519_key.pub`, compare to `.sops.yaml`. If mismatch: update `.sops.yaml`, `just rekey`.

---

## References

- Pattern 6: sops-nix declaration — [docs/patterns/06-sops-secrets.md](../patterns/06-sops-secrets.md)
- Stage 2: Initial secrets setup — [docs/roadmap/stage-02-secrets.md](../roadmap/stage-02-secrets.md)
- Stage 7a: VPS secrets — [docs/roadmap/stage-07a-vps-netbird.md](../roadmap/stage-07a-vps-netbird.md)
- sops-nix upstream — https://github.com/Mic92/sops-nix
