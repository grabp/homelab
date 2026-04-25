# Stage 13: Paperless-ngx + Stirling-PDF

## Status
NOT STARTED

## What Gets Built
Paperless-ngx document management (native module) with NAS storage for documents, Stirling-PDF toolkit (container) for PDF operations.

## Key Files
- `homelab/paperless/default.nix`

## Dependencies
- Stage 12 (PostgreSQL)
- NAS mount for `/mnt/nas/documents`

## Verification Steps
- [ ] `https://paperless.grab-lab.gg` loads Paperless web UI
- [ ] Document upload → OCR processing → searchable
- [ ] `https://pdf.grab-lab.gg` loads Stirling-PDF
- [ ] PDF operations (merge, split, convert) work

## Estimated Complexity
Medium. NFS mount dependencies require careful systemd ordering.
