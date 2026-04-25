---
kind: adr
status: accepted
date: 2025-04-22
title: Use Restic instead of Syncoid for VPS backups
---

# ADR 0004: Use Restic instead of Syncoid for VPS backups

## Context

The three-tier backup strategy includes ZFS replication to NAS via Syncoid. However, the VPS (Hetzner CX22) does not use ZFS — it uses ext4 on a 20 GB disk.

Two options for VPS backups:

1. **Syncoid** — ZFS-to-ZFS replication (requires ZFS on VPS)
2. **Restic** — file-level backup to any target (local, SFTP, S3)

## Decision

Use **Restic** for VPS backups to an off-site target (Hetzner backup or rsync to NAS).

**Rationale:**
- VPS runs ext4, not ZFS — Syncoid (ZFS send/receive) is impossible
- Restic provides deduplication, encryption, and flexible backends
- Single backup tool across all machines (consistency)
- File-level granularity suitable for VPS control plane state (~GB scale)

## Consequences

**Positive:**
- Works on any filesystem (ext4, ZFS, etc.)
- Encrypted backups by default
- Deduplication saves space for incremental backups

**Negative:**
- No ZFS snapshot atomicity on VPS (mitigated: small data volume, low change rate)
- Requires separate backup target configuration for VPS vs NAS-attached machines

---

**Supersedes:** Initial plan to use Syncoid universally (Syncoid retained for ZFS machines only)
