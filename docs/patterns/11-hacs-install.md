---
kind: pattern
number: 11
tags: [home-assistant, hacs, systemd]
---

# Pattern 11: HACS auto-installation via systemd oneshot

HACS is a custom component (Python files) placed in the HA config directory — it is not a NixOS package. Since HA's config directory is bind-mounted from the host, a systemd oneshot service can install HACS before HA starts on every fresh deployment.

Two approaches are shown. **Approach A** (downloads latest on first boot) is simpler. **Approach B** (pinned version, Nix-pure) is reproducible and avoids network access at boot.

## Approach A: download latest on first boot (idempotent)

```nix
{ config, pkgs, lib, ... }:

let
  haConfigDir = "/var/lib/homeassistant";
in {
  systemd.tmpfiles.rules = [
    "d ${haConfigDir}                    0755 root root -"
    "d ${haConfigDir}/custom_components  0755 root root -"
  ];

  systemd.services.hacs-install = {
    description = "Install HACS custom component for Home Assistant";
    wantedBy    = [ "multi-user.target" ];
    before      = [ "podman-homeassistant.service" ];
    requiredBy  = [ "podman-homeassistant.service" ];
    path        = with pkgs; [ wget unzip coreutils ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      HACS_DIR="${haConfigDir}/custom_components/hacs"
      if [ ! -f "$HACS_DIR/__init__.py" ]; then
        echo "Installing HACS..."
        wget -q -O /tmp/hacs.zip \
          "https://github.com/hacs/integration/releases/latest/download/hacs.zip"
        rm -rf "$HACS_DIR"
        mkdir -p "$HACS_DIR"
        unzip -o /tmp/hacs.zip -d "$HACS_DIR"
        rm -f /tmp/hacs.zip
        echo "HACS installed."
      else
        echo "HACS already present, skipping."
      fi
    '';
  };
}
```

## Approach B: pinned version, evaluated at build time (no network at boot)

```nix
{ config, pkgs, lib, ... }:

let
  haConfigDir = "/var/lib/homeassistant";
  hacsVersion = "2.0.5";
  hacsSrc = pkgs.fetchurl {
    url    = "https://github.com/hacs/integration/releases/download/${hacsVersion}/hacs.zip";
    sha256 = "0000000000000000000000000000000000000000000000000000";
    # ⚠️ VERIFY: compute with:
    # nix-prefetch-url https://github.com/hacs/integration/releases/download/2.0.5/hacs.zip
  };
  hacsUnpacked = pkgs.runCommand "hacs-${hacsVersion}" {
    buildInputs = [ pkgs.unzip ];
  } ''
    mkdir -p $out
    unzip ${hacsSrc} -d $out
  '';
in {
  system.activationScripts.hacs = ''
    mkdir -p ${haConfigDir}/custom_components/hacs
    rm -rf   ${haConfigDir}/custom_components/hacs/*
    cp -r ${hacsUnpacked}/* ${haConfigDir}/custom_components/hacs/
    chmod -R u+w ${haConfigDir}/custom_components/hacs
  '';
}
```

**Post-install:** After HACS files are in place and HA starts, complete HACS setup in HA UI: Settings → Devices & Services → Add Integration → HACS → complete GitHub OAuth device flow. HACS works fully for custom integrations, Lovelace cards, and themes. The HA Add-on store is unavailable in container installs (requires HA OS/Supervised).

**Source:** HACS GitHub repo + sops-nix README pattern for systemd oneshot services ✅. Approach B uses standard `pkgs.fetchurl` + `pkgs.runCommand` Nix derivation patterns ✅.
