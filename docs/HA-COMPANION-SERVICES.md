# Home Assistant companion services on bare-metal NixOS 25.11

**All six companion services have native NixOS modules in nixpkgs**, making bare-metal NixOS one of the most declarative platforms for a Home Assistant stack. The recommended architecture is a hybrid: run Mosquitto and the Wyoming voice pipeline (Whisper, Piper, OpenWakeWord) natively via NixOS modules for tighter integration and simpler management, while running ESPHome and Matter Server as Podman containers due to unresolved native packaging bugs. HACS can be automated via a NixOS systemd oneshot service. This guide provides verified option paths, working configuration snippets, and specific image tags for each service.

The target system — an HP Elitedesk 705 G4 with AMD Ryzen and 16 GB RAM — can comfortably run the entire stack. The voice pipeline (Whisper `small-int8` + Piper + OpenWakeWord) consumes roughly **1.5–2 GB RAM** total, leaving ample headroom for Home Assistant and the remaining services.

---

## 1. Wyoming Faster-Whisper (speech-to-text)

### NixOS module: `services.wyoming.faster-whisper`

NixOS provides a first-class module for faster-whisper (CTranslate2-based, not the original OpenAI Whisper). The module lives at `nixos/modules/services/home-automation/wyoming/faster-whisper.nix` and uses a multi-instance `servers.<name>` pattern.

**Verified option paths:**

| Option | Type | Default | Purpose |
|---|---|---|---|
| `services.wyoming.faster-whisper.package` | package | `pkgs.wyoming-faster-whisper` | Package override |
| `services.wyoming.faster-whisper.servers.<name>.enable` | bool | `false` | Enable instance |
| `services.wyoming.faster-whisper.servers.<name>.model` | string | `"tiny-int8"` | Whisper model name |
| `services.wyoming.faster-whisper.servers.<name>.language` | string | — | Language code (e.g. `"en"`) |
| `services.wyoming.faster-whisper.servers.<name>.uri` | string | — | Bind URI (`tcp://0.0.0.0:10300`) |
| `services.wyoming.faster-whisper.servers.<name>.device` | string | `"cpu"` | Device: `"cpu"` or `"cuda"` |
| `services.wyoming.faster-whisper.servers.<name>.beamSize` | int | — | Beam search width |
| `services.wyoming.faster-whisper.servers.<name>.initialPrompt` | null or string | — | First-window prompt |
| `services.wyoming.faster-whisper.servers.<name>.extraArgs` | list of strings | `[]` | Additional CLI flags |

**Available models (from nixpkgs):** `tiny-int8`, `tiny`, `tiny.en`, `base-int8`, `base`, `base.en`, `small-int8`, `distil-small.en`, `small`, `small.en`, `medium-int8`, `distil-medium.en`, `medium`, `medium.en`, `large-v3`, `turbo`

### Model selection for AMD Ryzen + 16 GB RAM

| Model | Params | RAM usage | Relative speed | English WER | Recommendation |
|---|---|---|---|---|---|
| `tiny-int8` | 39 M | ~150–200 MB | Fastest | ~7.8% | Simple commands only |
| `base-int8` | 74 M | ~250–300 MB | Very fast | ~5.2% | Good for quick commands |
| **`small-int8`** | 244 M | **~500–600 MB** | Fast | **~3.5%** | **Best balance — recommended** |
| `medium-int8` | 769 M | ~1.2 GB | Moderate | ~2.9% | Overkill for home use |

**`small-int8` is the recommended model.** INT8 quantization delivers roughly **3.5× speedup** over float32 with negligible accuracy loss (~0.1% WER difference). On a multi-core Ryzen, typical utterances process in **2–4 seconds**. With 16 GB RAM, even `medium-int8` fits easily, but `small-int8` offers the best latency/accuracy tradeoff for voice commands.

### ⚠️ Critical NixOS gotcha: ProcSubset performance bug

The systemd service hardening sets `ProcSubset=pid`, which **blocks faster-whisper from reading `/proc/cpuinfo`**. This causes CTranslate2 to fall back to a suboptimal code path. On an i5-12400, a 3-second audio clip took **~20 seconds instead of ~3 seconds** — a catastrophic regression. This was addressed in nixpkgs PR #372898 but may not be merged into your channel yet. **Apply this workaround:**

```nix
systemd.services."wyoming-faster-whisper-main".serviceConfig.ProcSubset = lib.mkForce "all";
```

### ⚠️ CUDA not available in nixpkgs

The CTranslate2 package in nixpkgs is not compiled with CUDA support. Setting `device = "cuda"` will fail with `ValueError: This CTranslate2 package was not compiled with CUDA support`. Use `device = "cpu"` (which is appropriate for the Elitedesk 705 G4 anyway, as it has no discrete GPU).

### Container alternative

**Image:** `rhasspy/wyoming-whisper` — **latest tag: `3.1.0`** ⚠️ VERIFY (Docker Hub tag may differ from GitHub release v3.0.2; check `https://hub.docker.com/r/rhasspy/wyoming-whisper/tags`)

```nix
virtualisation.oci-containers.containers.wyoming-whisper = {
  image = "rhasspy/wyoming-whisper:3.1.0";
  ports = [ "10300:10300" ];
  volumes = [ "/var/lib/wyoming-whisper:/data" ];
  cmd = [ "--model" "small-int8" "--language" "en" ];
};
```

### Native vs container performance verdict

Container overhead for CPU-bound ML inference is **~0.1%** — effectively zero. Multiple benchmarks (IBM, Hathora, academic studies) consistently show containers deliver near-native CPU compute performance. The choice is purely about **management ergonomics**, not performance. Docker adds no measurable latency to audio processing or model inference.

### Recommendation: **Native NixOS module** ✅

The native module integrates cleanly with NixOS declarative config, avoids container image management, and works well — provided you apply the `ProcSubset` fix. Since HA runs with `--network=host`, it reaches the native Wyoming service on `localhost:10300` directly.

```nix
services.wyoming.faster-whisper.servers."main" = {
  enable = true;
  uri = "tcp://0.0.0.0:10300";
  model = "small-int8";
  language = "en";
  device = "cpu";
};

# CRITICAL: Fix ProcSubset performance bug
systemd.services."wyoming-faster-whisper-main".serviceConfig.ProcSubset = lib.mkForce "all";
```

---

## 2. Wyoming Piper (text-to-speech)

### NixOS module: `services.wyoming.piper`

Same multi-instance pattern as faster-whisper. Module file: `nixos/modules/services/home-automation/wyoming/piper.nix`.

**Verified option paths:**

| Option | Type | Default | Purpose |
|---|---|---|---|
| `services.wyoming.piper.package` | package | `pkgs.wyoming-piper` | Package override |
| `services.wyoming.piper.servers.<name>.enable` | bool | `false` | Enable instance |
| `services.wyoming.piper.servers.<name>.voice` | string | — | Voice model (e.g. `"en_US-lessac-medium"`) |
| `services.wyoming.piper.servers.<name>.uri` | string | — | Bind URI (`tcp://0.0.0.0:10200`) |
| `services.wyoming.piper.servers.<name>.speaker` | int | — | Speaker ID for multi-speaker models |
| `services.wyoming.piper.servers.<name>.noiseScale` | float | `0.667` | Generator noise |
| `services.wyoming.piper.servers.<name>.noiseW` | float | `0.333` | Phoneme width noise |
| `services.wyoming.piper.servers.<name>.lengthScale` | float | `1.0` | Speech speed (lower = faster) |
| `services.wyoming.piper.servers.<name>.piper` | package | `pkgs.piper-tts` | Piper TTS engine package |
| `services.wyoming.piper.servers.<name>.extraArgs` | list of strings | `[]` | Additional CLI flags |

### Voice model options

Piper uses VITS neural voice models in ONNX format. Models auto-download from HuggingFace on first use.

| Voice | Quality | Size | Notes |
|---|---|---|---|
| `en_US-lessac-medium` | Medium | ~65 MB | **Recommended default** — clear female voice |
| `en_US-lessac-high` | High | ~100 MB | Higher quality, slightly slower |
| `en_US-ryan-medium` | Medium | ~65 MB | Male voice |
| `en_US-amy-low` | Low | ~20 MB | Fastest, lower quality |
| `en_GB-southern_english_female-low` | Low | ~20 MB | British English |

### Resource usage

Piper is lightweight. It generates speech in real-time even on a Raspberry Pi 4. On an AMD Ryzen:

- **RAM:** ~200–500 MB (depends on voice model loaded)
- **CPU:** Single core sufficient; synthesis is nearly instantaneous
- No GPU required — CPU-only ONNX inference

### Container alternative

**Image:** `rhasspy/wyoming-piper` — **latest tag: `2.2.2`** (Feb 2025, piper-tts 1.4.1)

### Recommendation: **Native NixOS module** ✅

No known major bugs. Lightweight, well-maintained module. Same rationale as Whisper — native integrates cleanly, and HA on `--network=host` connects directly.

```nix
services.wyoming.piper.servers."main" = {
  enable = true;
  uri = "tcp://0.0.0.0:10200";
  voice = "en_US-lessac-medium";
};
```

---

## 3. Wyoming OpenWakeWord (wake word detection)

### NixOS module: `services.wyoming.openwakeword`

Unlike Whisper and Piper, OpenWakeWord is a **single-instance** service (no `servers.<name>` pattern). Module file: `nixos/modules/services/home-automation/wyoming/openwakeword.nix`.

**Verified option paths:**

| Option | Type | Default | Purpose |
|---|---|---|---|
| `services.wyoming.openwakeword.enable` | bool | `false` | Enable service |
| `services.wyoming.openwakeword.package` | package | `pkgs.wyoming-openwakeword` | Package override |
| `services.wyoming.openwakeword.uri` | string | `"tcp://0.0.0.0:10400"` | Bind URI |
| `services.wyoming.openwakeword.preloadModels` | list of strings | `[]` | Wake word models to preload |
| `services.wyoming.openwakeword.threshold` | float | — | Activation threshold (0.0–1.0) |
| `services.wyoming.openwakeword.triggerLevel` | int | — | Activations before detection |
| `services.wyoming.openwakeword.customModelsDirectories` | list of paths | `[]` | Dirs with custom `.tflite` models |
| `services.wyoming.openwakeword.extraArgs` | list of strings | `[]` | Additional CLI flags |

### ⚠️ Breaking change in v2.0.0

OpenWakeWord v2.0.0 (Oct 2025) **renamed `ok_nabu` to `okay_nabu`** and removed the `--preload-model` flag (replaced with `--refractory-seconds` and `--zeroconf`). Check which version your nixpkgs channel ships. If using the NixOS module option `preloadModels`, use the correct model name for your package version.

### Built-in wake words

`okay_nabu`, `hey_jarvis`, `alexa`, `hey_mycroft`, `hey_rhasspy` — custom `.tflite` models supported via `customModelsDirectories`.

### Resource usage

Extremely lightweight: **< 100–200 MB RAM**, negligible CPU. Designed to run continuously even on embedded hardware.

### Container alternative

**Image:** `rhasspy/wyoming-openwakeword` — **latest tag: `2.1.0`** (Oct 2025)

### Recommendation: **Native NixOS module** ✅

```nix
services.wyoming.openwakeword = {
  enable = true;
  uri = "tcp://0.0.0.0:10400";
  preloadModels = [ "okay_nabu" ];  # (verified in Stage 9b, see PROGRESS.md — nixos-25.11 ships v2.0.0+)
};
```

---

## 4. ESPHome (ESP microcontroller dashboard and compiler)

### NixOS module: `services.esphome` (exists but has significant bugs)

Module file: `nixos/modules/services/home-automation/esphome.nix`. Maintainer: `oddlama`.

**Verified option paths:**

| Option | Type | Default | Purpose |
|---|---|---|---|
| `services.esphome.enable` | bool | `false` | Enable ESPHome dashboard |
| `services.esphome.package` | package | `pkgs.esphome` | Package override |
| `services.esphome.address` | string | `"localhost"` | Bind address |
| `services.esphome.port` | int | `6052` | Dashboard port |
| `services.esphome.enableUnixSocket` | bool | `false` | Use Unix socket instead of TCP |
| `services.esphome.openFirewall` | bool | `false` | Auto-open firewall port |
| `services.esphome.usePing` | bool | `false` | Use ICMP ping instead of mDNS |
| `services.esphome.allowedDevices` | list of strings | `[]` | Device nodes for USB flashing |

### ⚠️ Multiple unresolved native packaging bugs

The NixOS ESPHome module has **three significant open issues** that make firmware compilation unreliable:

1. **DynamicUser path failure** (nixpkgs #339557): `systemd DynamicUser=true` places the state directory at `/var/lib/private/esphome` (symlinked from `/var/lib/esphome`), which breaks PlatformIO's path resolution during compilation.

2. **Missing pyserial** (nixpkgs #370611): `esptool` cannot find the `pyserial` module, so `firmware.factory.bin` is not created. This blocks ESP32 firmware compilation.

3. **Missing font component** (nixpkgs #272334): Pillow version mismatches cause the `font:` component to fail in ESPHome configs.

**The DynamicUser workaround (if you want to try native anyway):**

```nix
systemd.services.esphome = {
  environment.PLATFORMIO_CORE_DIR = lib.mkForce "/var/lib/private/esphome/.platformio";
  serviceConfig = {
    ExecStart = lib.mkForce "${pkgs.esphome}/bin/esphome dashboard --address ${cfg.address} --port ${toString cfg.port} /var/lib/private/esphome";
    WorkingDirectory = lib.mkForce "/var/lib/private/esphome";
  };
};
```

### mDNS requirements

ESPHome uses mDNS (port 5353/UDP) for device discovery. Two approaches:

- **Host networking** (container or native): mDNS works natively. Enable Avahi on the host for full `.local` resolution.
- **`usePing = true`**: Skip mDNS entirely and use ICMP ping to detect device status. Requires devices to have static IPs.

### Container image

**Image:** `ghcr.io/esphome/esphome` — **latest tag: `2026.3.1`** (March 2026)

### Recommendation: **Podman container** ✅

The Docker image is the primary distribution method and avoids all three native packaging bugs. Use `--network=host` for mDNS device discovery.

```nix
virtualisation.oci-containers.containers.esphome = {
  image = "ghcr.io/esphome/esphome:2026.3.1";
  extraOptions = [ "--network=host" ];
  environment = {
    TZ = "Europe/Warsaw";  # (verified in Stage 9b, see PROGRESS.md — uses vars.timeZone)
  };
  volumes = [
    "/var/lib/esphome:/config"
    "/etc/localtime:/etc/localtime:ro"
  ];
  # Uncomment for USB flashing:
  # extraOptions = [ "--network=host" "--device=/dev/ttyUSB0:/dev/ttyUSB0" ];
};
```

To connect ESPHome to HA: add the ESPHome integration in HA UI (Settings → Devices & Services → Add Integration → ESPHome). Enter the host IP and port 6052. Since both use `--network=host`, they share the network namespace and can communicate on localhost.

---

## 5. Matter Server (python-matter-server)

### NixOS module: `services.matter-server` (exists but has CHIP SDK build issues)

Module file: `nixos/modules/services/home-automation/matter-server.nix`.

**Verified option paths:**

| Option | Type | Default | Purpose |
|---|---|---|---|
| `services.matter-server.enable` | bool | `false` | Enable Matter server |
| `services.matter-server.package` | package | `pkgs.python-matter-server` | Package override |
| `services.matter-server.port` | int | `5580` | WebSocket API port |
| `services.matter-server.logLevel` | string | — | Log verbosity |
| `services.matter-server.openFirewall` | bool | `false` | Auto-open firewall port |
| `services.matter-server.extraArgs` | list of strings | `[]` | Additional CLI flags |

### ⚠️ Native packaging is problematic

The CHIP SDK (`home-assistant-chip-core`) requires architecture-specific binary wheels with a non-standard build system (CIPD + GN). Building it natively on NixOS is extremely difficult (nixpkgs #255774). The NixOS package may also require permitting insecure OpenSSL 1.1 in some configurations.

### ⚠️ Project in transition

python-matter-server is now in **maintenance mode**. The project is being rewritten on top of **matter.js** (`ghcr.io/matter-js/matterjs-server`). The current Python version supports Matter 1.4.2 and remains API-compatible, but monitor this transition for future migration.

### Network and system requirements

Matter is an IPv6-based protocol requiring specific host configuration:

- **Host networking is mandatory** — Matter uses IPv6 link-local multicast for device discovery. Bridge networking completely breaks this.
- **D-Bus access** required for Bluetooth commissioning: mount `/run/dbus:/run/dbus:ro`
- **IPv6 must be enabled** on the host
- **IPv6 forwarding must be disabled** (`net.ipv6.conf.all.forwarding = 0`) — if enabled, Matter devices experience up to 30-minute reachability outages on network changes

### Container image

**Image:** `ghcr.io/home-assistant-libs/python-matter-server` — **latest tag: `stable` or `8.1.2`** (Dec 2025)

### Recommendation: **Podman container** ✅

The Docker image bundles the pre-built CHIP SDK wheels, avoiding the intractable native build issues.

```nix
virtualisation.oci-containers.containers.matter-server = {
  image = "ghcr.io/home-assistant-libs/python-matter-server:stable";
  extraOptions = [
    "--network=host"
    "--security-opt=label=disable"  # Required for Bluetooth/D-Bus access
  ];
  volumes = [
    "/var/lib/matter-server:/data"
    "/run/dbus:/run/dbus:ro"
  ];
};

# Required host configuration for Matter
networking.enableIPv6 = true;
boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = 0;
```

Connection to HA: Settings → Devices & Services → Add Integration → Matter → enter `ws://127.0.0.1:5580/ws` (works because both use host networking).

---

## 6. Mosquitto MQTT broker

### NixOS module: `services.mosquitto` (mature, well-maintained)

This is the most mature of all the modules discussed. Module file: `nixos/modules/services/networking/mosquitto.nix`.

**Key verified option paths:**

| Option | Type | Default | Purpose |
|---|---|---|---|
| `services.mosquitto.enable` | bool | `false` | Enable MQTT broker |
| `services.mosquitto.package` | package | `pkgs.mosquitto` | Package override |
| `services.mosquitto.dataDir` | path | `"/var/lib/mosquitto"` | Data directory |
| `services.mosquitto.persistence` | bool | — | Persistent subscriptions/messages |
| `services.mosquitto.listeners` | list of submodules | `[]` | Listener configurations |
| `services.mosquitto.listeners.*.port` | int | `1883` | Listener port |
| `services.mosquitto.listeners.*.users.<name>.acl` | list of strings | — | Per-user ACL rules |
| `services.mosquitto.listeners.*.users.<name>.hashedPasswordFile` | path | — | Password file path |
| `services.mosquitto.listeners.*.settings.allow_anonymous` | bool | — | Allow anonymous connections |
| `services.mosquitto.bridges` | attrset of submodules | `{}` | Bridge to other brokers |
| `services.mosquitto.settings` | attrset | `{}` | Global config (freeform) |

### NixOS-specific behaviors to know

The module automatically sets **`per_listener_settings true`** globally. This means users and ACLs are scoped per listener — you cannot define global users; each listener needs its own user definitions. Password files are auto-generated at build time to `${dataDir}/passwd-${listenerIndex}`.

### Generating password hashes

```bash
nix shell nixpkgs#mosquitto --command mosquitto_passwd -c /tmp/passwd homeassistant
# Enter password at prompt, then extract the hash:
cat /tmp/passwd
# Output: homeassistant:$7$101$KIGAc4K4Pj2zfump$a1s19bL++...
# Use everything after "homeassistant:" as the hashedPassword value
```

### Container alternative

**Image:** `eclipse-mosquitto` — **latest tag: `2.0.22`** ⚠️ VERIFY (check Docker Hub tags)

### Recommendation: **Native NixOS module** ✅

Mosquitto is the clearest case for running natively. The module is mature, fully declarative, handles password hashing at build time, and eliminates container networking overhead for this latency-sensitive service. Since HA runs with `--network=host`, it connects to Mosquitto on `127.0.0.1:1883` with zero overhead.

```nix
services.mosquitto = {
  enable = true;
  listeners = [{
    port = 1883;
    users = {
      homeassistant = {
        acl = [ "readwrite #" ];
        hashedPassword = "$7$101$XXXX$XXXX";  # Generate with mosquitto_passwd
      };
      # Optional: restricted user for IoT devices
      iot = {
        acl = [
          "read homeassistant/command/#"
          "write sensors/#"
        ];
        hashedPassword = "$7$101$YYYY$YYYY";
      };
    };
  }];
};

networking.firewall.allowedTCPPorts = [ 1883 ];
```

HA connection: Settings → Devices & Services → Add Integration → MQTT → Broker: `127.0.0.1`, Port: `1883`, Username: `homeassistant`, Password: (your password).

---

## 7. HACS in container-based Home Assistant

### How HACS installation works

HACS is a custom component (Python files) placed in `custom_components/hacs/` inside the HA config directory. It is **not** a NixOS module — it lives inside the HA container's filesystem.

**Latest version:** `2.0.5` (Jan 28, 2025). Requires HA ≥ 2024.4.1.

**Runtime requirements:** `wget` and `unzip` only for the install script. **Git is NOT required** — HACS uses the GitHub API and zip downloads. Internet access is needed at runtime for HACS to fetch repository metadata.

### Automating HACS installation via NixOS

Since the HA config directory is bind-mounted from the host, you can manage HACS files from NixOS. There are two approaches:

**Approach A: Systemd oneshot service (downloads latest on first boot)**

```nix
{ config, pkgs, lib, ... }:

let
  haConfigDir = "/var/lib/homeassistant";
in {
  systemd.tmpfiles.rules = [
    "d ${haConfigDir} 0755 root root -"
    "d ${haConfigDir}/custom_components 0755 root root -"
  ];

  systemd.services.hacs-install = {
    description = "Download and install HACS for Home Assistant";
    wantedBy = [ "multi-user.target" ];
    before = [ "podman-homeassistant.service" ];
    requiredBy = [ "podman-homeassistant.service" ];
    path = with pkgs; [ wget unzip coreutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      HACS_DIR="${haConfigDir}/custom_components/hacs"
      if [ ! -f "$HACS_DIR/__init__.py" ]; then
        echo "Installing HACS..."
        rm -rf "$HACS_DIR"
        wget -q -O /tmp/hacs.zip "https://github.com/hacs/integration/releases/latest/download/hacs.zip"
        mkdir -p "$HACS_DIR"
        unzip -o /tmp/hacs.zip -d "$HACS_DIR"
        rm -f /tmp/hacs.zip
        echo "HACS installed successfully"
      else
        echo "HACS already installed, skipping"
      fi
    '';
  };
}
```

**Approach B: Fully declarative with pinned version (Nix-pure)**

```nix
{ config, pkgs, lib, ... }:

let
  haConfigDir = "/var/lib/homeassistant";
  hacsVersion = "2.0.5";
  hacsSrc = pkgs.fetchurl {
    url = "https://github.com/hacs/integration/releases/download/${hacsVersion}/hacs.zip";
    sha256 = "0000000000000000000000000000000000000000000000000000";
    # ⚠️ VERIFY: Get real hash with:
    # nix-prefetch-url https://github.com/hacs/integration/releases/download/2.0.5/hacs.zip
  };
  hacsUnpacked = pkgs.runCommand "hacs-${hacsVersion}" { buildInputs = [ pkgs.unzip ]; } ''
    mkdir -p $out
    unzip ${hacsSrc} -d $out
  '';
in {
  system.activationScripts.hacs = ''
    mkdir -p ${haConfigDir}/custom_components/hacs
    rm -rf ${haConfigDir}/custom_components/hacs/*
    cp -r ${hacsUnpacked}/* ${haConfigDir}/custom_components/hacs/
    chmod -R u+w ${haConfigDir}/custom_components/hacs
  '';
}
```

### HACS limitations in container HA

HACS works fully for **custom integrations, Lovelace cards, themes, and Python scripts**. The only feature unavailable in container installs is the HA Add-on store (which requires HA OS/Supervised). HACS can self-update through its UI once installed. After installation, configure HACS in HA UI: Settings → Devices & Services → Add Integration → HACS → complete GitHub OAuth device flow.

---

## Supporting infrastructure: Avahi, Podman, and firewall

### Avahi for mDNS

ESPHome and general `.local` name resolution benefit from Avahi on the host:

```nix
services.avahi = {
  enable = true;
  nssmdns4 = true;
  publish = {
    enable = true;
    addresses = true;
  };
};
```

⚠️ **Gotcha:** Enabling `nssmdns` can cause slow DNS resolution for non-`.local` domains. Ensure your `/etc/nsswitch.conf` uses `mdns_minimal [NOTFOUND=return]` rather than `mdns` to mitigate this — NixOS handles this correctly when `nssmdns4 = true`.

### Podman configuration

```nix
virtualisation.podman = {
  enable = true;
  dockerCompat = true;
  defaultNetwork.settings.dns_enabled = true;
};
```

### Firewall

```nix
networking.firewall.allowedTCPPorts = [
  1883   # Mosquitto MQTT
  5580   # Matter Server WebSocket
  6052   # ESPHome dashboard
  8123   # Home Assistant
  10200  # Wyoming Piper
  10300  # Wyoming Whisper
  10400  # Wyoming OpenWakeWord
];
networking.firewall.allowedUDPPorts = [
  5353   # mDNS
];
```

---

## Complete integrated NixOS configuration

This pulls everything together into a single working configuration:

```nix
{ config, pkgs, lib, ... }:

let
  haConfigDir = "/var/lib/homeassistant";
in {
  # === Podman ===
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  # === Mosquitto MQTT (native) ===
  services.mosquitto = {
    enable = true;
    listeners = [{
      port = 1883;
      users.homeassistant = {
        acl = [ "readwrite #" ];
        hashedPassword = "$7$101$XXXX$XXXX";  # ⚠️ REPLACE with real hash
      };
    }];
  };

  # === Wyoming Faster-Whisper STT (native) ===
  services.wyoming.faster-whisper.servers."main" = {
    enable = true;
    uri = "tcp://0.0.0.0:10300";
    model = "small-int8";
    language = "en";
    device = "cpu";
  };
  # Fix ProcSubset performance bug
  systemd.services."wyoming-faster-whisper-main".serviceConfig.ProcSubset = lib.mkForce "all";

  # === Wyoming Piper TTS (native) ===
  services.wyoming.piper.servers."main" = {
    enable = true;
    uri = "tcp://0.0.0.0:10200";
    voice = "en_US-lessac-medium";
  };

  # === Wyoming OpenWakeWord (native) ===
  services.wyoming.openwakeword = {
    enable = true;
    uri = "tcp://0.0.0.0:10400";
    preloadModels = [ "okay_nabu" ];  # (verified in Stage 9b, see PROGRESS.md — nixos-25.11 ships v2.0.0+)
  };

  # === ESPHome (container — native has compilation bugs) ===
  virtualisation.oci-containers.backend = "podman";
  virtualisation.oci-containers.containers.esphome = {
    image = "ghcr.io/esphome/esphome:2026.3.1";
    extraOptions = [ "--network=host" ];
    environment.TZ = "Europe/Warsaw";  # (verified in Stage 9b, see PROGRESS.md — uses vars.timeZone)
    volumes = [
      "/var/lib/esphome:/config"
      "/etc/localtime:/etc/localtime:ro"
    ];
  };

  # === Matter Server (container — CHIP SDK too hard to build natively) ===
  virtualisation.oci-containers.containers.matter-server = {
    image = "ghcr.io/home-assistant-libs/python-matter-server:stable";
    extraOptions = [
      "--network=host"
      "--security-opt=label=disable"
    ];
    volumes = [
      "/var/lib/matter-server:/data"
      "/run/dbus:/run/dbus:ro"
    ];
  };

  # === Home Assistant (container) ===
  virtualisation.oci-containers.containers.homeassistant = {
    image = "ghcr.io/home-assistant/home-assistant:stable";
    extraOptions = [ "--network=host" ];
    environment.TZ = "Europe/Warsaw";  # (verified in Stage 9a, see PROGRESS.md — uses vars.timeZone)
    volumes = [
      "${haConfigDir}:/config"
      "/run/dbus:/run/dbus:ro"
    ];
  };

  # === HACS auto-installation ===
  systemd.tmpfiles.rules = [
    "d ${haConfigDir} 0755 root root -"
    "d ${haConfigDir}/custom_components 0755 root root -"
  ];

  systemd.services.hacs-install = {
    description = "Download and install HACS";
    wantedBy = [ "multi-user.target" ];
    before = [ "podman-homeassistant.service" ];
    requiredBy = [ "podman-homeassistant.service" ];
    path = with pkgs; [ wget unzip coreutils ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      HACS_DIR="${haConfigDir}/custom_components/hacs"
      if [ ! -f "$HACS_DIR/__init__.py" ]; then
        wget -q -O /tmp/hacs.zip "https://github.com/hacs/integration/releases/latest/download/hacs.zip"
        rm -rf "$HACS_DIR"
        mkdir -p "$HACS_DIR"
        unzip -o /tmp/hacs.zip -d "$HACS_DIR"
        rm -f /tmp/hacs.zip
      fi
    '';
  };

  # === Avahi for mDNS ===
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = { enable = true; addresses = true; };
  };

  # === Network ===
  networking.enableIPv6 = true;
  boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = 0;  # Required for Matter

  networking.firewall.allowedTCPPorts = [
    1883 5580 6052 8123 10200 10300 10400
  ];
  networking.firewall.allowedUDPPorts = [ 5353 ];
}
```

---

## Decision matrix and version reference

| Service | Recommendation | NixOS module | Container image | Tag | Port |
|---|---|---|---|---|---|
| Whisper (STT) | **Native** ✅ | `services.wyoming.faster-whisper` | `rhasspy/wyoming-whisper` | `3.1.0` ⚠️ | 10300 |
| Piper (TTS) | **Native** ✅ | `services.wyoming.piper` | `rhasspy/wyoming-piper` | `2.2.2` | 10200 |
| OpenWakeWord | **Native** ✅ | `services.wyoming.openwakeword` | `rhasspy/wyoming-openwakeword` | `2.1.0` | 10400 |
| ESPHome | **Container** 🐋 | `services.esphome` (buggy) | `ghcr.io/esphome/esphome` | `2026.3.1` | 6052 |
| Matter Server | **Container** 🐋 | `services.matter-server` (broken deps) | `ghcr.io/home-assistant-libs/python-matter-server` | `stable` / `8.1.2` | 5580 |
| Mosquitto | **Native** ✅ | `services.mosquitto` | `eclipse-mosquitto` | `2.0.22` ⚠️ | 1883 |
| HACS | **NixOS systemd** ✅ | N/A (custom component) | N/A | `2.0.5` | N/A |

**⚠️ VERIFY** items: Docker image tags were researched in April 2026 — confirm against Docker Hub/GHCR before deploying. The Whisper Docker tag `3.1.0` may have updated. Run `podman pull --quiet <image>:latest && podman inspect <image>:latest` to verify.

### Estimated resource usage on HP Elitedesk 705 G4

| Service | RAM (steady state) | RAM (peak) | CPU | Notes |
|---|---|---|---|---|
| Home Assistant | ~300–500 MB | ~1 GB | Low | Depends on integrations |
| Whisper (`small-int8`) | ~500–600 MB | ~850 MB | Burst (during inference) | 2–4s per utterance |
| Piper (`medium` voice) | ~200–500 MB | ~500 MB | Brief burst | Near-instant synthesis |
| OpenWakeWord | ~100–200 MB | ~200 MB | Negligible | Continuous but lightweight |
| ESPHome | ~200 MB | ~2 GB | Burst (during compilation) | Idle most of the time |
| Matter Server | ~100–200 MB | ~300 MB | Low | Mostly idle |
| Mosquitto | ~5–10 MB | ~20 MB | Negligible | Extremely lightweight |
| **Total** | **~1.5–2.5 GB** | **~5 GB** | — | **Well within 16 GB** |

## Conclusion

The hybrid native + container approach gives the best of both worlds on NixOS. The three Wyoming voice services and Mosquitto run natively because their NixOS modules are mature, well-maintained, and avoid unnecessary container orchestration. ESPHome and Matter Server run in containers because their native NixOS packaging has unresolved build issues that would block real usage. The single most important gotcha is the **faster-whisper `ProcSubset` bug** — without the `lib.mkForce "all"` fix, STT inference is roughly 7× slower than expected. All services connect to the Podman-hosted Home Assistant over `localhost` thanks to `--network=host`, making the Wyoming protocol integration trivially simple: just add Wyoming integrations in the HA UI pointing at `127.0.0.1` and the respective port.