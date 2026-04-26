---
kind: pattern
number: 9
tags: [just, justfile, commands]
---

# Pattern 9: Justfile for NixOS homelab operations

```just
# justfile — NixOS homelab task runner

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
deploy host="pebble":
    nix run github:serokell/deploy-rs -- -s .#{{host}}

deploy-all:
    nix run github:serokell/deploy-rs -- -s .

# ── Flake Management ─────────────────────────
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
```

**Source:** Derived from ryan4yin/nix-config and NixOS & Flakes Book ✅.
