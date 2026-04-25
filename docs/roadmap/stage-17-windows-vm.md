# Stage 17: Windows VM — libvirt/QEMU

## Status
NOT STARTED

## What Gets Built
libvirt/QEMU virtualization enabled, Windows 10/11 VM for occasional use cases (specific software, testing).

## Key Files
- VM config stored in `/var/lib/libvirt/`
- virt-manager for GUI management

## Dependencies
- Stage 11 (base system)

## Verification Steps
- [ ] `virt-manager` launches on admin workstation
- [ ] Windows VM boots and is usable
- [ ] RDP access works over LAN/VPN
- [ ] VM does not consume resources when stopped

## Estimated Complexity
Low. libvirt module is well-documented.
