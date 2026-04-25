---
kind: pattern
number: 17
tags: [podman, volumes, permissions, sqlite]
---

# Pattern 17: Podman volume directories — own by container UID, not root

**Problem:** `systemd.tmpfiles.rules` with type `d` defaults to `root root` ownership. Rootful Podman shares the host UID namespace — no remapping. If the containerised process drops privileges after startup (e.g., Pi-hole's FTL binds port 53 as root, then drops to UID 1000), it can no longer create files in the host-owned directory. SQLite WAL mode needs to create `<db>-wal` and `<db>-shm` alongside the database file; if the directory is not writable by the running UID, every write fails with:

```
attempt to write a readonly database
```

The database *file* itself may be owned correctly (`1000:1000 rw-rw----`) and still be unwritable — because SQLite's WAL lock files must be created in the same directory, and directory write permission is what's missing.

**Fix:** set the `d` rule owner to the UID the container process actually runs as. For Pi-hole v6, that is UID/GID 1000 (`pihole` user inside the container).

```nix
systemd.tmpfiles.rules = [
  # UID 1000 = pihole user inside the container (rootful Podman, no UID remapping).
  # SQLite WAL mode requires directory write access to create .db-wal/.db-shm files.
  "d /var/lib/pihole 0755 1000 1000 -"
];
```

**Immediate fix for an already-created directory** (tmpfiles `d` only adjusts ownership if it created the directory; an existing `root:root` directory must be fixed manually):

```bash
sudo chown 1000:1000 /var/lib/pihole
# No container restart needed — directory permissions take effect immediately.
```

**Checklist when adding a new Podman volume:**
1. Find out what UID the container process runs as after startup (`podman exec <name> ps aux`).
2. If it drops to a non-root UID, set that UID in the `d` tmpfiles rule.
3. If the directory already exists on the host, run `sudo chown UID:GID /var/lib/<service>`.
4. Containers using `--network=host` or that stay as root throughout are unaffected.

**Source:** Diagnosed live on Pi-hole v6 (pihole/pihole:2025.02.1). SQLite WAL behaviour confirmed in SQLite documentation — the directory containing the database must be writable for WAL lock file creation ✅.
