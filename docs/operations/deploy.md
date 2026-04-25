---
kind: runbook
tags: [deploy, deploy-rs, nixos-anywhere]
---

# Deployment Runbook

## Normal Deployment (deploy-rs)

Deploy config changes to running machines. IPs from `machines/nixos/vars.nix` — never use domain names ([Pattern 18](../patterns/18-ssh-ip-addresses.md)).

```bash
# pebble (homelab server)
just deploy pebble
# Target: 192.168.10.50

# VPS
just deploy-vps
# Target: 204.168.181.110
```

**How it works:** deploy-rs builds locally, copies closure via SSH, activates. Auto-rollback on failure.

**Pre-deploy checks:**
```bash
just build   # test build without deploying
just check   # validate flake
```

---

## Initial Provisioning (nixos-anywhere)

For bare-metal or fresh VPS. Requires ≥1 GB RAM.

### VPS provisioning workflow

```bash
# 1. Create VPS, get public IP (e.g., 204.168.181.110)

# 2. DNS record (Cloudflare, no proxy)
# A netbird.grab-lab.gg → 204.168.181.110

# 3. Generate + derive age key
just gen-vps-hostkey
nix shell nixpkgs#ssh-to-age -c sh -c \
  'ssh-to-age < machines/nixos/vps/keys/ssh_host_ed25519_key.pub'
# Output: age1xxxxx...

# 4. Add to .sops.yaml
# keys:
#   - &vps age1xxxxx...
# creation_rules:
#   - path_regex: secrets/vps\.yaml$
#     key_groups: [age: [*admin, *vps]]

# 5. Create secrets
just edit-secrets-vps

# 6. Provision
just provision-vps 204.168.181.110

# 7. Verify
ssh admin@204.168.181.110
# Check: systemctl status, lsblk, ip addr

# 8. Subsequent updates: deploy-rs
just deploy-vps
```

**What nixos-anywhere does:** kexec-boots target into NixOS installer (RAM), partitions via disko, installs flake, reboots.

**VPS disko (Pattern 13):** `/dev/sda`, GPT, ESP 512M, ext4 root, GRUB (SeaBIOS).

**Full details:** [docs/patterns/13-nixos-anywhere-vps.md](../patterns/13-nixos-anywhere-vps.md)

---

## Rollback

### Automatic (deploy-rs)
deploy-rs auto-rolls back on activation failure. No manual action needed.

### Manual (console access)
If deployment breaks SSH:
1. Physical/IPMI console → reboot
2. GRUB menu → select previous generation
3. Boot, make permanent (optional):
   ```bash
   sudo /run/current-system/bin/switch-to-configuration boot
   ```

### List/rollback generations
```bash
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system

# Rollback to previous
sudo nix-env --rollback --profile /nix/var/nix/profiles/system
sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch
```

---

## Common Failures

### Wrong machine deployed (Pattern 18)

**Symptom:** VPS config deployed to pebble (or vice versa).

**Cause:** DNS returned wrong IP (Pi-hole misconfiguration).

**Fix:**
1. Console → reboot → select previous generation from GRUB
2. Verify `flakeHelpers.nix` uses `deployHostname` → returns IPs from `vars.nix`
3. Verify `justfile` uses IPs, not domains
4. Re-deploy to correct machine

**Prevention:** Always use IPs, never domains for SSH/deploy.

### ACME failures on VPS

**Symptom:** `acme-netbird.grab-lab.gg.service` fails, Caddy can't get cert.

**Cause:** Ports 80/443 not open.

**Fix:**
```nix
# machines/nixos/vps/default.nix
networking.firewall.allowedTCPPorts = [ 80 443 ];
```

### deploy-rs hangs/times out

**Causes:**
- Target unreachable (`ping <IP>`)
- SSH auth not working (`ssh admin@<IP>`)
- Service startup blocking (`journalctl -f` on target)

**Debug:**
```bash
ssh admin@192.168.10.50

nix run github:serokell/deploy-rs -- -s .#pebble --debug-logs

ssh admin@192.168.10.50 journalctl -f
```

### nixos-anywhere fails

**Common causes:**
- RAM < 1 GB (target can't kexec)
- Wrong disk device (`/dev/sda` vs `/dev/vda` — check `lsblk` via rescue console)
- SSH key not in root's authorized_keys
- Firewall blocking SSH (provider console)

**Recovery:** Rescue mode → check disk layout, fix disko.nix if device differs, retry.

---

## Post-Deploy Verification

### pebble
```bash
ssh admin@192.168.10.50
systemctl status caddy pihole grafana loki prometheus
zpool status
sudo iptables -L -n -v
just netbird-status
```

### VPS
```bash
ssh admin@204.168.181.110
podman ps
systemctl status caddy coturn
curl -I https://netbird.grab-lab.gg
sudo iptables -L -n -v
```

---

## References

- Pattern 13: nixos-anywhere VPS — [docs/patterns/13-nixos-anywhere-vps.md](../patterns/13-nixos-anywhere-vps.md)
- Pattern 18: IP-based deploy — [docs/patterns/18-ssh-ip-addresses.md](../patterns/18-ssh-ip-addresses.md)
- Stage 1: Base deployment — [docs/roadmap/stage-01-base-system.md](../roadmap/stage-01-base-system.md)
- Stage 7a: VPS provisioning — [docs/roadmap/stage-07a-vps-netbird.md](../roadmap/stage-07a-vps-netbird.md)
