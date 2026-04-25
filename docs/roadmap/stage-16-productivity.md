# Stage 16: Productivity Apps — Outline, Vikunja, Karakeep, Actual Budget

## Status
NOT STARTED

## What Gets Built
Outline wiki (container), Vikunja tasks (container), Karakeep bookmarks (container), Actual Budget (container). All on port-remapped configs to avoid conflicts.

## Key Files
- Container configs in boulder's default.nix or individual modules

## Dependencies
- Stage 12 (PostgreSQL for Outline, Vikunja)
- **Stage 7c (Kanidm) — required for Outline, strongly recommended for all services**

## ⚠️ Blocking Dependency
**Outline requires OIDC and has no local auth fallback.** It cannot be deployed until Stage 7c (Kanidm) is complete and the `outline` OAuth2 client is provisioned. Attempting to deploy Outline before Kanidm exists will result in an unusable wiki. Vikunja, Karakeep, and Actual Budget can fall back to local auth if needed.

## Verification Steps
- [ ] `https://wiki.grab-lab.gg` — Outline loads
- [ ] `https://tasks.grab-lab.gg` — Vikunja loads
- [ ] `https://bookmarks.grab-lab.gg` — Karakeep loads
- [ ] `https://budget.grab-lab.gg` — Actual Budget loads
- [ ] Data persists across container restarts

## Estimated Complexity
Low-medium. Multiple containers but each is straightforward.
