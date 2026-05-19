---
kind: runbook
tags: [remote-build, deploy, apple-silicon, cross-architecture]
---

# Remote Build Runbook

## Overview

The development Mac is aarch64-darwin; all homelab nodes are x86_64-linux.
Two mechanisms enable cross-architecture deployment:

1. **deploy-rs `remoteBuild = true`** — each target builds its own closure.
   Works out of the box, no Mac-side config needed.
2. **Remote builder via `nix.buildMachines`** — boulder (primary) and pebble
   (fallback) accept delegated builds from the Mac's Nix daemon over SSH.
   Enables `nix build`, `nix flake check`, and handles IFD.

## deploy-rs remoteBuild (Tier 1)

No Mac-side setup needed. `remoteBuild = true` is set in `flakeHelpers.nix`.
deploy-rs evaluates locally (platform-independent) and builds on the target.

```bash
# Works from Apple Silicon Mac:
just deploy pebble
just deploy boulder
just deploy-vps
```

## Remote Builder Setup (Tier 2) — One-Time Mac Setup

### Step 1: Generate a dedicated SSH key (as root)

The Nix daemon runs as root on macOS. The SSH connection to the builder
must use a key owned by root.

```bash
sudo ssh-keygen -t ed25519 -N "" \
  -f /var/root/.ssh/nix-builder-key \
  -C "nix-builder@mac"
```

Print the public key:

```bash
sudo cat /var/root/.ssh/nix-builder-key.pub
```

### Step 2: Add the public key to boulder and pebble

Paste the public key into `machines/nixos/boulder/default.nix` and
`machines/nixos/pebble/default.nix` in the `my.builder.authorizedKeys` list.
Deploy both machines (remoteBuild is already enabled, so no builder needed):

```bash
just deploy boulder
just deploy pebble
```

### Step 3: Accept host fingerprints (as root)

```bash
sudo ssh -i /var/root/.ssh/nix-builder-key nixremote@192.168.10.51 true
sudo ssh -i /var/root/.ssh/nix-builder-key nixremote@192.168.10.50 true
```

Type `yes` to accept each host's fingerprint. This populates
`/var/root/.ssh/known_hosts`.

### Step 4: Configure Nix on the Mac

#### Option A: nix-darwin (if using nix-darwin)

```nix
{
  nix.distributedBuilds = true;
  nix.settings.builders-use-substitutes = true;

  nix.buildMachines = [
    {
      hostName     = "192.168.10.51";  # boulder (primary)
      sshUser      = "nixremote";
      sshKey       = "/var/root/.ssh/nix-builder-key";
      systems      = [ "x86_64-linux" ];
      maxJobs      = 8;
      speedFactor  = 2;
      supportedFeatures = [ "nixos-test" "big-parallel" "kvm" "benchmark" ];
    }
    {
      hostName     = "192.168.10.50";  # pebble (fallback)
      sshUser      = "nixremote";
      sshKey       = "/var/root/.ssh/nix-builder-key";
      systems      = [ "x86_64-linux" ];
      maxJobs      = 4;
      speedFactor  = 1;
      supportedFeatures = [ "nixos-test" "big-parallel" "kvm" "benchmark" ];
    }
  ];
}
```

#### Option B: Manual nix.conf (if NOT using nix-darwin)

Create or edit `/etc/nix/machines`:

```
ssh-ng://nixremote@192.168.10.51 x86_64-linux /var/root/.ssh/nix-builder-key 8 2 nixos-test,big-parallel,kvm,benchmark
ssh-ng://nixremote@192.168.10.50 x86_64-linux /var/root/.ssh/nix-builder-key 4 1 nixos-test,big-parallel,kvm,benchmark
```

Add to `/etc/nix/nix.conf` (or `~/.config/nix/nix.conf`):

```ini
builders = @/etc/nix/machines
builders-use-substitutes = true
```

Restart the Nix daemon:

```bash
sudo launchctl kickstart -k system/org.nixos.nix-daemon
```

### Step 5: Verify

```bash
# Should build on boulder, not locally:
nix build .#nixosConfigurations.pebble.config.system.build.toplevel --no-link

# Check the daemon saw the builders:
nix show-config | grep builders

# If it hangs, check SSH manually:
sudo ssh -i /var/root/.ssh/nix-builder-key nixremote@192.168.10.51 "nix store ping"
```

## Deploying Boulder Itself

When deploying boulder, it cannot build itself while being restarted.
Two options:

1. **remoteBuild handles it** — boulder builds, then activates. deploy-rs's
   magic rollback protects against broken configs.
2. **Use pebble as the builder** — Nix will fall back to pebble (speedFactor=1)
   if boulder is unreachable. Or explicitly:
   ```bash
   # Build on pebble, deploy to boulder:
   nixos-rebuild switch --flake .#boulder \
     --target-host admin@192.168.10.51 \
     --build-host admin@192.168.10.50 \
     --fast --use-remote-sudo
   ```

## Troubleshooting

**"a 'x86_64-linux' with features {} is required"** — no builder is reachable.
Check: `sudo ssh -i /var/root/.ssh/nix-builder-key nixremote@192.168.10.51 true`

**"cannot add path … because it lacks a signature"** — `trusted-users` does
not include `nixremote` on the builder. Redeploy the builder config.

**"Failed to find a machine for remote build"** — the derivation requires a
feature (e.g., `kvm`) not listed in `supportedFeatures`. Add it.

**Build hangs indefinitely** — the Nix daemon's root user cannot reach the
builder via SSH. Check `/var/root/.ssh/known_hosts` has the fingerprint.
Run `sudo ssh -v -i /var/root/.ssh/nix-builder-key nixremote@192.168.10.51`
for debug output.

**Connection refused on port 22** — builder's sshd may be down, or the
machine is off. Check `systemctl status sshd` on the builder.

## Architecture

```
┌─────────────────┐
│  Mac (ARM)      │
│  nix daemon     │
│  evaluates flake│
└────────┬────────┘
         │ SSH (ssh-ng://)
         ▼
┌─────────────────┐     ┌─────────────────┐
│ boulder (x86_64)│     │ pebble (x86_64) │
│ primary builder │     │ fallback builder │
│ speedFactor = 2 │     │ speedFactor = 1  │
│ maxJobs = 8     │     │ maxJobs = 4      │
└─────────────────┘     └─────────────────┘
         │                       │
         ▼                       ▼
    nix build output copied back to Mac store
         │
         ▼
    deploy-rs copies closure to target via SSH
    (or with remoteBuild=true, target builds itself)
```

## References

- nix.dev distributed builds tutorial: https://nix.dev/tutorials/nixos/distributed-builds-setup.html
- deploy-rs README (remoteBuild): https://github.com/serokell/deploy-rs
- Pattern 18: Always use IPs for SSH — docs/patterns/18-ssh-ip-addresses.md
