---
name: netavark-firewall
description: Use this skill whenever editing, creating, or debugging any module under homelab/ that uses virtualisation.oci-containers. Also trigger when the user reports a "container is running but unreachable" or "port refused" problem. Encodes Pattern 19 (Netavark vs NixOS firewall ordering). Trigger phrases: "container not reachable", "port closed", "oci-container", "netavark".
model: inherit
tools: Read, Edit, Grep
argument-hint: <service-name>
disable-model-invocation: false
user-invocable: true
---

# Netavark firewall ordering (Pattern 19)

## The problem
NixOS's firewall.service and podman/netavark races: if podman-<svc>.service starts before firewall.service, the published port rules are later flushed when firewall.service activates, leaving the container running but unreachable.

## The fix (must appear for every container that publishes ports)
In `homelab/<service>/default.nix`:

```nix
systemd.services."podman-<service>" = {
  partOf = [ "firewall.service" ];
  after  = [ "firewall.service" ];
};
```

## When it is NOT needed
- Container has `network = "host"` (uses the host's netns).
- Container only communicates via internal unix sockets.
- Container does not publish ports (internal-only, talked to by other containers in the same pod).

## Pre-flight checks when editing
1. `Grep -n 'oci-containers.containers' homelab/<service>/default.nix`
2. Look for `ports = [...]` or `-p` in `extraOptions`. If there, the fix is required.
3. `Grep -n 'partOf.*firewall' homelab/<service>/default.nix`. If missing, add it.

## Verification
```bash
ssh <host> "sudo systemctl list-dependencies podman-<service>.service | grep -i firewall"
ssh <host> "sudo ss -tlnp | grep <port>"
ssh <host> "sudo nft list chain inet nixos-fw nixos-fw | grep <port>"
```
All three must show the expected plumbing.

## If already broken on a live host
`systemctl restart podman-<service>.service` after firewall has come up — that's a workaround, not a fix. Add the partOf/after block and redeploy.
