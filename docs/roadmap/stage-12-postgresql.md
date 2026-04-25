# Stage 12: PostgreSQL Shared Instance

## Status
NOT STARTED

## What Gets Built
Single PostgreSQL server for Outline, Vikunja, and Paperless-ngx. Each service gets its own database with separate credentials stored in sops.

## Key Files
- `homelab/postgresql/default.nix` or configure in boulder's `default.nix`

## Dependencies
- Stage 11 (base system)

## Verification Steps
- [ ] `systemctl status postgresql` shows active
- [ ] `psql -U postgres -l` lists databases
- [ ] Databases created: `outline`, `vikunja`, `paperless`
- [ ] Each database user has appropriate permissions

## Estimated Complexity
Low. Native module is straightforward.
