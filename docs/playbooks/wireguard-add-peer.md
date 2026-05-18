---
kind: playbook
tags: [wireguard, vpn, peers, mobile]
---

# Add a WireGuard Peer (Mobile Device)

## Overview

WireGuard peers are statically configured in `homelab/wireguard-server/default.nix`. Adding a device requires three steps: generate a keypair, add the public key to the VPS config, and generate a client config for the device.

## WireGuard Subnet

```
10.10.0.1  VPS (hub)
10.10.0.2  pebble
10.10.0.3  boulder
10.10.0.4  phone1
10.10.0.5  (next available)
```

Pick the next available IP and increment for each new device.

---

## Step 1 — Generate a keypair

Generate the keypair on pebble or any trusted machine (not the VPS).

```bash
wg genkey | tee /tmp/new-device.key | wg pubkey > /tmp/new-device.pub
cat /tmp/new-device.pub   # public key → goes into Nix config (safe to commit)
cat /tmp/new-device.key   # private key → goes into client config only, never committed
```

---

## Step 2 — Add the peer to VPS config

Edit `homelab/wireguard-server/default.nix`. Add a new peer block inside `peers = [ ... ]`:

```nix
{
  # <device name> — <assigned IP>
  publicKey = "<paste public key here>"; # gitleaks:allow
  allowedIPs = [ "10.10.0.X/32" ];      # next available IP
}
```

---

## Step 3 — Deploy VPS

```bash
just deploy-vps
```

The new peer is registered. The device can now connect even before you configure it — WireGuard handshakes are mutual, so the device just needs to know the VPS public key and endpoint.

---

## Step 4 — Create the client config

Create a file `<device>.conf`:

```ini
[Interface]
Address = 10.10.0.X/32
DNS = 192.168.10.50
PrivateKey = <device private key from /tmp/new-device.key>

[Peer]
PublicKey = Va6gsgUqcxtgW8wLNCiBGVv+dr3xe9J27pbniMRHExU=
Endpoint = <VPS_IP>:51820
AllowedIPs = 10.10.0.0/24, 192.168.10.0/24
PersistentKeepalive = 25
```

**DNS:** `192.168.10.50` is pebble's Pi-hole. All `*.grab-lab.gg` queries resolve correctly via the tunnel. Public DNS is also forwarded through Pi-hole.

**AllowedIPs:** `10.10.0.0/24` covers WireGuard peers (direct access to pebble/boulder via their overlay IPs); `192.168.10.0/24` covers homelab services via Caddy on pebble.

---

## Step 5 — Load onto device

**QR code (iOS/Android WireGuard app):**

```bash
qrencode -t ansiutf8 < <device>.conf
```

Scan with the WireGuard app → Add Tunnel → Scan QR Code.

**File import:** Transfer `<device>.conf` to the device and import in the WireGuard app.

---

## Verification

After connecting on the device:

```bash
# On VPS — confirm handshake established
sudo wg show wg0
# Peer line should show: latest handshake: X seconds ago

# From device — ping pebble overlay IP
ping 10.10.0.2

# From device — ping pebble LAN IP (tests routing)
ping 192.168.10.50

# From device — load a homelab service
curl -sk https://grafana.grab-lab.gg | head -5
```

---

## Removing a Peer

Remove the peer block from `homelab/wireguard-server/default.nix` and redeploy:

```bash
just deploy-vps
```

The peer is immediately disconnected — WireGuard drops the session when the peer is no longer in the config.
