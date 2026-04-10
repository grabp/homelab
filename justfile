# justfile — NixOS homelab task runner
# Install just: nix-shell -p just

# ── Local Operations ──────────────────────────
switch:
    sudo nixos-rebuild switch --flake .

test:
    nixos-rebuild test --flake . --use-remote-sudo

build:
    nixos-rebuild build --flake .

debug:
    nixos-rebuild switch --flake . --use-remote-sudo --show-trace --verbose

# ── Remote Deployment ─────────────────────────
deploy host="elitedesk":
    nix run github:serokell/deploy-rs -- -s .#{{host}}

deploy-all:
    nix run github:serokell/deploy-rs -- -s .

# ── Flake Management ──────────────────────────
update:
    nix flake update

update-input input:
    nix flake update {{input}}

check:
    nix flake check

show:
    nix flake show

# ── Secrets ───────────────────────────────────
edit-secrets:
    sops secrets/secrets.yaml

rekey:
    find secrets -name '*.yaml' -exec sops updatekeys {} \;

# ── Maintenance ───────────────────────────────
gc:
    sudo nix-collect-garbage --delete-old

clean:
    sudo nix profile wipe-history --profile /nix/var/nix/profiles/system --older-than 7d

history:
    nix profile history --profile /nix/var/nix/profiles/system

fmt:
    nix fmt

repl:
    nix repl -f flake:nixpkgs

# ── Installation helpers ───────────────────────
# Run on target machine during installation
# 1. Boot NixOS ISO
# 2. Identify disk: lsblk -d -o NAME,SIZE,MODEL
# 3. Update disko.nix device path
# 4. Run: just disko-install /dev/sdX
disko-install disk:
    sudo nix run github:nix-community/disko/latest -- \
      --mode destroy,format,mount \
      ./machines/nixos/elitedesk/disko.nix \
      --arg diskoFile ./machines/nixos/elitedesk/disko.nix

# Generate hostId for networking.hostId in elitedesk/default.nix
gen-hostid:
    head -c4 /dev/urandom | od -A none -t x4 | tr -d ' \n' && echo
