---
kind: roadmap
stage: 13
title: Paperless-ngx + Stirling-PDF
status: complete
---

# Stage 13: Paperless-ngx + Stirling-PDF

## Status
✅ COMPLETE (deployed 2026-04-30)

## What Gets Built
Paperless-ngx document management (native module) with local ZFS storage for documents,
Stirling-PDF toolkit (container) for PDF operations.

## Key Files
- `homelab/paperless/default.nix` — Paperless-ngx native module, PostgreSQL via Unix socket
- `homelab/stirling-pdf/default.nix` — Stirling-PDF OCI container

## Files Modified
- `machines/nixos/boulder/default.nix` — enabled `paperless` and `stirlingPdf`
- `homelab/caddy/default.nix` — added `@paperless` and `@pdf` vhost handlers
- `homelab/homepage/default.nix` — added "Documents" service group

## Dependencies
- Stage 12 (PostgreSQL) — shared PostgreSQL instance on boulder

## Design Decisions

### Paperless Storage
Documents are stored on local ZFS (`/var/lib/paperless`) rather than NAS-mounted
storage. This avoids NFS permission issues with Synology Windows ACLs.
Backup coverage: restic backs up `/var/lib` by default.

### Database Connection
Uses PostgreSQL Unix socket with peer authentication (no password needed).
`PAPERLESS_DBHOST = "/run/postgresql"` enables this.

### OCR Languages
Polish + English (`PAPERLESS_OCR_LANGUAGE = "pol+eng"`).

### OCR Error Handling
Some PDFs trigger Ghostscript soft errors during PDF/A conversion.
`continue_on_soft_render_error = true` allows processing to continue.
`optimize = 0` disables JPEG transcoding to avoid transcode failures.

## Verification Steps (All Passed 2026-04-30)
- [x] `https://paperless.grab-lab.gg` loads Paperless web UI
- [x] Document upload → OCR processing → searchable
- [x] `https://pdf.grab-lab.gg` loads Stirling-PDF
- [x] PDF operations (merge, split, convert) work
- [x] Services appear in Homepage "Documents" group

## Post-Deploy Notes
- Paperless admin account created on first boot using `paperless/admin_password` secret
- Documents stored in `/var/lib/paperless/media/`
- Consumption directory at `/var/lib/paperless/consume/`
