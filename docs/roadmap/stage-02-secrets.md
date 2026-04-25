# Stage 2: Secrets Management

## Status
COMPLETE (verified 2026-04-11)

## Files Created
- `.sops.yaml` — age keys for admin (koksownik) and pebble
- `secrets/secrets.yaml` — encrypted secrets file

## Configuration
- sops-nix configured in `machines/nixos/pebble/default.nix`
- Age key derived from SSH host key (`/etc/ssh/ssh_host_ed25519_key`)
- Admin key stored at `~/.config/sops/age/keys.txt` on koksownik

## Verification (All Passed)
- [x] `sops secrets/secrets.yaml` opens editor and encrypts on save
- [x] `nixos-rebuild switch` decrypts secrets successfully
- [x] `cat /run/secrets/test_secret` shows decrypted value
- [x] Secret file permissions correct (readable by root)
