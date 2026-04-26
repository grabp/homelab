# PLAN.md — Homelab Improvement Implementation Plan

Each item has a unique ID, status, affected files, exact changes required, and verification steps.
Work through items in order. After completing each item, change `Status: NOT STARTED` → `Status: COMPLETE`.
See `.agent/skills/implement-plan/SKILL.md` for the agent protocol to follow.

---

## P-01 — Fix critical doc misalignment: IDP-STRATEGY.md still describes embedded Dex as live

Status: COMPLETE
References: Deliverable Task 1, Finding #1

**Affected files:** `docs/IDP-STRATEGY.md`

**Changes required:**
1. Replace the "Chosen approach" section opening with: "NetBird uses Pocket ID (OCI container on the VPS) as its OIDC provider. Embedded Dex was replaced in Stage 10b — see PROGRESS.md."
2. Add a banner at the top of the file:
   ```
   > **Status:** Updated for Stage 10b. Pocket ID replaced embedded Dex as the NetBird IdP.
   > Kanidm remains the homelab service SSO provider. See ARCHITECTURE.md §Auth.
   ```
3. Remove any prose that treats Dex as the current/recommended choice. Retain one sentence: "Dex was used during Stage 10a and replaced in Stage 10b."
4. Search for the word "Dex" throughout and either remove, historicize, or replace with "Pocket ID" as appropriate.

**Verification:** `grep -n "Dex\|dex" docs/IDP-STRATEGY.md` — remaining hits should only appear in historical context sentences.

---

## P-02 — Fix critical doc misalignment: NETBIRD-SELFHOSTED.md recommends embedded Dex

Status: COMPLETE
References: Deliverable Task 1, Finding #2

**Affected files:** `docs/NETBIRD-SELFHOSTED.md`

**Changes required:**
1. Add this banner at the very top of the file (before the H1):
   ```markdown
   > **Archived research document.** Superseded by Stage 10b.
   > The production stack uses Pocket ID (not embedded Dex) for NetBird auth.
   > See PROGRESS.md Stage 10b and docs/IDP-STRATEGY.md for the current setup.
   > This file is retained as research context for future migrations.
   ```
2. Do NOT delete the file — it contains useful research. Just make its status clear.
3. Do NOT move the file yet (that is P-09, the doc restructure).

**Verification:** First 10 lines of the file contain the "Archived research document" banner.

---

## P-03 — Fix critical doc misalignment: STAGES.md phase table still shows Stage 10 incomplete

Status: COMPLETE (superseded by docs/roadmap/)
References: Deliverable Task 1, Finding #3

**Affected files:** `docs/STAGES.md` (deleted, content moved to `docs/roadmap/`)

**Changes required:**
1. Content from STAGES.md was extracted into individual stage files under `docs/roadmap/`.
2. STAGES.md has been deleted. All references updated to point to `docs/roadmap/`.
3. See docs/roadmap/index.md for navigation.

**Verification:** `ls docs/roadmap/stage-*.md | wc -l` — 22 files (stages 1–10b and 11–18).

---

## P-04 — Fix critical doc misalignment: STRUCTURE.md references phantom directories

Status: COMPLETE
References: Deliverable Task 1, Finding #4

**Affected files:** `docs/STRUCTURE.md`

**Changes required:**
1. Remove all references to `modules/monitoring/`, `modules/nfs/`, `modules/backup/` from the directory tree. These directories do not exist — monitoring, NFS, and backup live under `homelab/<n>/default.nix`.
2. Add an explicit placeholder for `boulder/`:
   ```
   │       └── boulder/           # ⚠ NOT YET CREATED (Stage 11, Phase 2)
   ```
3. Remove the reference to `modules/` top-level directory entirely from the tree.
4. Verify `users/admin/default.nix` description matches the actual file contents.

**Verification:** Run `tree -L 3 -I 'result|result-*|.git' .` in the repo root and confirm the rendered tree is consistent with what `docs/STRUCTURE.md` describes.

---

## P-05 — Fix important misalignment: .sops.yaml stale comment

Status: COMPLETE
References: Deliverable Task 1, Finding #9

**Affected files:** `.sops.yaml`

**Changes required:**
Replace the comment block near the VPS creation rule that says:
```yaml
# After running `just gen-vps-hostkey` and adding &vps above:
#   1. Uncomment `- *vps` below
```
with:
```yaml
# VPS host key is active (see &vps above and *vps in creation rules below).
# To add a new host: just gen-<host>-hostkey, add &<host> to keys,
# add *<host> to relevant creation_rules, then run: just rekey
```

**Verification:** The word "Uncomment" must not appear in `.sops.yaml`.

---

## P-06 — Fix important misalignment: Traefik references on VPS

Status: COMPLETE
References: Deliverable Task 1, Finding #6

**Affected files:** `docs/ARCHITECTURE.md`, `docs/VPS-LOKI-SHIPPING.md`, `docs/SERVICE-CONFIGS.md`

**Changes required:**
1. `grep -rn "Traefik\|traefik" docs/` — list all hits.
2. For each hit, replace "Traefik" with "Caddy" unless it appears in a historical/comparison context.
3. In `docs/ARCHITECTURE.md`, add one sentence in the VPS section: "We use native NixOS Caddy (`services.caddy`) on the VPS for TLS termination — not Traefik or a Caddy container."

**Verification:** `grep -rn "[Tt]raefik" docs/` returns zero hits (or only hits in comparison tables where it is clearly labeled as "not used").

---

## P-07 — Fix important misalignment: remove stale ⚠️ VERIFY markers in HA companion doc

Status: COMPLETE
References: Deliverable Task 1, Finding #7

**Affected files:** `docs/HA-COMPANION-SERVICES.md`

**Changes required:**
1. `grep -n "VERIFY" docs/HA-COMPANION-SERVICES.md` — list all markers.
2. For each marker whose subject is confirmed in a `homelab/*/default.nix` module, remove the marker and replace with "(verified in Stage 9, see PROGRESS.md)".
3. Leave markers that refer to things genuinely not yet confirmed (e.g. future boulder services).

**Verification:** `grep -c "VERIFY" docs/HA-COMPANION-SERVICES.md` returns a count that you can justify (ideally 0 for things already deployed).

---

## P-08 — Create the six new Claude Code skills

Status: COMPLETE (5 skills created; deploy-host excluded per user request)
References: Deliverable Task 4

**Affected files (all new):**
- `.agent/skills/new-homelab-service/SKILL.md` ✓
- `.agent/skills/kanidm-oauth2-client/SKILL.md` ✓
- `.agent/skills/new-sops-secret/SKILL.md` ✓
- `.agent/skills/netavark-firewall/SKILL.md` ✓
- `.agent/skills/deploy-host/SKILL.md` (excluded)
- `.agent/skills/service-module-preflight/SKILL.md` ✓

**Changes required:**
Create each skill as a subdirectory with a `SKILL.md` file (Claude Code requires `<name>/SKILL.md` structure).
For each file, after creation verify:
- Frontmatter is valid YAML (name, description, model, tools, argument-hint, disable-model-invocation).
- Description field starts with "Use this skill" (required for Claude Code auto-triggering).
- File is under 500 lines.
- Add `user-invocable: true` so the skill appears in `/skills`.

**Verification:**
```bash
for d in .agent/skills/*/; do
  f="$d/SKILL.md"
  echo "=== $f ==="; wc -l "$f"; head -3 "$f"
done
```
Six new skill directories present, each with valid `SKILL.md` frontmatter.

---

## P-09 — Create and wire the MCP server

Status: COMPLETE
References: Deliverable Task 5

**Affected files (all new):**
- `.agent/mcp/pyproject.toml`
- `.agent/mcp/homelab_mcp/__init__.py`
- `.agent/mcp/homelab_mcp/repo.py`
- `.agent/mcp/homelab_mcp/server.py`
- `.agent/mcp/tests/test_tools.py`
- `.agent/mcp/justfile`
- `.mcp.json` (repo root)
- `flake.nix` (add `devShells.mcp`)

**Changes required:**
1. Create all files with content from deliverable Task 5.2.
2. In `.mcp.json`, update `PEBBLE_IP` and `VPS_IP` to match values in `machines/nixos/vars.nix`.
3. In `flake.nix`, add the `devShells.mcp` block from the deliverable.
4. Run the tests:
   ```bash
   cd .agent/mcp && pip install -e ".[dev]" && pytest -q
   ```
   All tests must pass before marking complete.
5. Verify MCP registration:
   ```bash
   claude mcp list   # should show 'homelab' server
   ```

**Build verification:**
```bash
nix flake check
cd .agent/mcp && pytest -q
```

**Verification:** `claude mcp list` shows `homelab` as a connected server with status `ok`.

---

## P-10 — Add the `implement-plan` skill itself

Status: COMPLETE
References: This file

**Affected files (new):** `.agent/skills/implement-plan/SKILL.md`

**Changes required:**
Create `.agent/skills/implement-plan/SKILL.md` with the content from the companion skill file.
Claude Code requires skills to be in `<name>/SKILL.md` subdirectory format (not flat `.md` files).
Also update `.claude/skills` symlink to point to `.agent/skills` so project skills are discovered.
This skill must be created BEFORE P-08 is started (since P-08 uses the same workflow).
Actually: do P-10 FIRST, then P-01 through P-09 use it.

**Verification:** `.agent/skills/implement-plan/SKILL.md` exists and has valid frontmatter.

---

## P-11 — Doc restructure: create per-service README.md files

Status: COMPLETE
References: Deliverable Task 2
Depends on: P-01 through P-07 (doc fixes should be done first so READMEs start clean)

**Affected files:** One new `homelab/<service>/README.md` per service

**Changes required:**
For each directory under `homelab/` that has a `default.nix`:
1. Read the corresponding section from `docs/SERVICE-CONFIGS.md`.
2. Create `homelab/<service>/README.md` with frontmatter and sections: Purpose, Ports, Secrets, Depends on, DNS, OIDC (if applicable), Known gotchas, Backup/restore.
3. The README should be ≤150 lines.

Do this for services in this order (most-documented first, easiest to verify):
- caddy, pihole, grafana, loki, prometheus
- vaultwarden, kanidm, homepage, uptime-kuma
- home-assistant, mosquitto, wyoming, matter-server, netbird
- backup

**Verification:** `ls homelab/*/README.md | wc -l` — matches number of service directories.

---

## P-12 — Doc restructure: slim PROGRESS.md and create docs/roadmap/

Status: COMPLETE
References: Deliverable Task 2
Depends on: P-11

**Affected files:** `PROGRESS.md`, new `docs/roadmap/stage-*.md` files

**Changes required:**
1. For each completed stage (1–10b), extract the narrative block from PROGRESS.md into `docs/roadmap/stage-NN-<name>.md`.
2. Replace the narrative in PROGRESS.md with a one-line pointer: `- Stage N: COMPLETE — see docs/roadmap/stage-NN-<name>.md`
3. PROGRESS.md should end up ≤150 lines: just the current-stage header, the completion table, and pointers.

**Verification:** `wc -l PROGRESS.md` — under 150. `ls docs/roadmap/` — one file per completed stage.

---

## P-13 — MkDocs portal: set up and wire to Caddy

Status: COMPLETE
References: Deliverable Task 3
Depends on: P-11, P-12 (so the doc tree is stable before building the site)

**Affected files:**
- `mkdocs.yml` (new, repo root)
- `homelab/docs-site/default.nix` (new)
- `homelab/default.nix` (add import)
- `machines/nixos/pebble/default.nix` (enable the module)
- `justfile` (add docs-serve, docs-build targets)

**Changes required:**
1. Create `mkdocs.yml` from deliverable Task 3 content. Update `site_url` to actual domain from `machines/nixos/vars.nix`.
2. Create `homelab/docs-site/default.nix` from deliverable Task 3 content.
3. Wire into homelab/default.nix and pebble/default.nix.
4. Add justfile targets.
5. Build test:
   ```bash
   nix build .#docs-site
   ```

**Verification:**
```bash
nix build .#docs-site && echo "BUILD OK"
curl -I http://localhost:8000  # from: mkdocs serve
```

---

## P-14 — Split NIX-PATTERNS.md into individual pattern files

Status: COMPLETE
Depends on: P-07 (so stale VERIFY markers are cleaned first)

**Changes required:**
1. Create `docs/patterns/` directory.
2. For each `## Pattern N` section in `docs/NIX-PATTERNS.md`, create
   `docs/patterns/<NN>-<slug>.md` where slug is a 2-4 word kebab-case
   description of the pattern (e.g. `19-netavark-firewall.md`).
3. Add frontmatter to each: `kind: pattern`, `number: N`, `tags: [...]`.
4. Keep `docs/NIX-PATTERNS.md` but replace its body with a table of
   contents pointing to the individual files. Do not delete it — external
   references may still point there.

**Verification:** `ls docs/patterns/*.md | wc -l` equals the number of
patterns in the original file.

---

## P-15 — Create docs/architecture/adr/ files

Status: COMPLETE

**Changes required:**
Create one file per decision already made in this homelab. Extract the
reasoning from ARCHITECTURE.md rather than inventing new content:
1. `docs/architecture/adr/0001-caddy-not-traefik.md`
2. `docs/architecture/adr/0002-pocket-id-not-dex.md`
3. `docs/architecture/adr/0003-oci-over-nixos-server-module.md`
4. `docs/architecture/adr/0004-restic-not-syncoid.md`
5. `docs/architecture/adr/0005-kanidm-1_9-pin.md`

Each file: frontmatter (`kind: adr`, `status: accepted`, `date`), then
Context / Decision / Consequences (3 short sections, ≤60 lines total).

**Verification:** `ls docs/architecture/adr/*.md | wc -l` equals 5.

---

## P-16 — Move research docs to docs/archive/ and add frontmatter

Status: COMPLETE
Depends on: P-02, P-14, P-15

**Changes required:**
1. `git mv docs/NETBIRD-SELFHOSTED.md docs/archive/netbird-selfhosted-research.md`
2. `git mv docs/HA-COMPANION-SERVICES.md docs/archive/ha-companion-services-research.md`
3. Add frontmatter (`kind: archive`, `status: archived`, `superseded_by: ...`)
   to both files.
4. Add frontmatter to every remaining doc under `docs/` that doesn't have it yet.
5. Create `docs/index.md` — a simple Q→doc table (≤80 lines).

**Verification:** `grep -rL "^---" docs/**/*.md` returns only files that
intentionally have no frontmatter (none should remain after this item).

---

## P-17 — Create docs/architecture/ non-ADR files

Status: COMPLETE
References: Deliverable Task 2
Depends on: P-01 (IDP fix), P-06 (Traefik fix), P-15 (ADRs exist first)

**Affected files (all new):**
- `docs/architecture/overview.md`
- `docs/architecture/auth.md`
- `docs/architecture/ports-and-dns.md`

**Changes required:**
1. Create `docs/architecture/overview.md` by distilling the topology,
   machines, and network sections from `docs/ARCHITECTURE.md` into a
   focused ≤150-line overview. Include: machine roles (pebble, vps,
   future boulder), network topology (CGNAT, relay, LAN), the wildcard
   DNS/Caddy entry-point pattern. Add frontmatter:
   `kind: architecture`, `tags: [topology, networking]`.

2. Create `docs/architecture/auth.md` as the single source of truth for
   authentication. Merge and supersede the auth content scattered across
   `docs/IDP-STRATEGY.md` and `docs/ARCHITECTURE.md §Auth`. Sections:
   Two-tier design (Pocket ID on VPS for NetBird, Kanidm on pebble for
   services), per-service auth table, OIDC flow diagram (text/mermaid),
   known gotchas. Add frontmatter: `kind: architecture`, `tags: [auth,
   oidc, kanidm, pocket-id]`, `supersedes: [docs/IDP-STRATEGY.md]`.

3. Create `docs/architecture/ports-and-dns.md` as a generated reference
   table. Do NOT hand-write the values — derive them from the actual
   modules:
   ```bash
   # Ports: scan homelab/*/default.nix for port assignments
   grep -rh "port\s*=\s*[0-9]" homelab/*/default.nix | sort -t= -k2 -n

   # DNS: scan for virtualHosts and customDNS entries
   grep -rh "virtualHosts\.\|customDNS\." homelab/*/default.nix | sort
   ```
   Format as two markdown tables (Ports, DNS). Add a comment at the top:
   Add frontmatter: `kind: architecture`, `tags: [ports, dns]`.

4. Add a `docs-update` recipe to `justfile`:
   ```make
   docs-update:
       # Regenerate ports-and-dns.md from live module scan
       cd docs/architecture && ../../scripts/gen-ports-dns.sh > ports-and-dns.md
   ```
   (The script can be a simple bash wrapper around the greps above.)

**Verification:**
```bash
ls docs/architecture/*.md   # overview.md, auth.md, ports-and-dns.md (plus adr/)
grep -c "^---" docs/architecture/overview.md   # frontmatter present (returns 2)
grep -c "^---" docs/architecture/auth.md
grep -c "^---" docs/architecture/ports-and-dns.md
```

---

## P-18 — Create docs/operations/ runbooks

Status: COMPLETE
References: Deliverable Task 2
Depends on: P-01–P-07 (doc fixes complete so content is accurate)

**Affected files (all new):**
- `docs/operations/deploy.md`
- `docs/operations/secrets.md`
- `docs/operations/backup-and-restore.md`
- `docs/operations/monitoring.md`

**Changes required:**
All content already exists — it is scattered across PROGRESS.md stage
notes, NIX-PATTERNS.md, and ARCHITECTURE.md. Extract and consolidate,
do not invent.

1. `docs/operations/deploy.md` — distill from NIX-PATTERNS.md Pattern 18
   (IP-based deploy), Pattern 13 (nixos-anywhere VPS provisioning), and
   the deploy sections of PROGRESS.md Stages 1, 7a, 10. Sections:
   Normal deploy (deploy-rs, `just deploy pebble`), VPS deploy, Initial
   provisioning (nixos-anywhere), Rollback procedure, Common failures.
   Frontmatter: `kind: runbook`, `tags: [deploy, deploy-rs]`.

2. `docs/operations/secrets.md` — distill from NIX-PATTERNS.md Pattern 6
   (sops-nix declaration) and the secrets sections of PROGRESS.md
   Stages 2, 7a. Sections: Adding a new secret, Rotating a secret,
   Adding a new host to a creation rule, Rekeying, Recovery (lost key).
   Frontmatter: `kind: runbook`, `tags: [secrets, sops]`.

3. `docs/operations/backup-and-restore.md` — distill from PROGRESS.md
   Stage 10 backup section and homelab/backup/default.nix. Sections:
   What is backed up (and what is not), Sanoid snapshot schedule, Restic
   to NAS, Restore procedure (step by step), Bare-metal recovery order.
   Frontmatter: `kind: runbook`, `tags: [backup, restic, sanoid]`.

4. `docs/operations/monitoring.md` — distill from PROGRESS.md Stage 6
   and homelab/{prometheus,grafana,loki}/default.nix. Sections:
   Stack overview (Prometheus → Grafana, Loki ← Alloy), Accessing
   dashboards, Alert routing (Telegram via Alertmanager), Adding a new
   scrape target, Querying logs in Loki (example LogQL).
   Frontmatter: `kind: runbook`, `tags: [monitoring, grafana, loki]`.

Each runbook must be ≤200 lines. If content would exceed that, summarise
and link to the relevant PROGRESS.md stage or NIX-PATTERNS.md pattern.

**Verification:**
```bash
ls docs/operations/*.md   # four files present
for f in docs/operations/*.md; do echo "=== $f ==="; wc -l "$f"; done
# each should be under 200 lines
grep -l "^kind:" docs/operations/*.md | wc -l   # should equal 4
```

---

## P-19 — Create docs/patterns/index.md

Status: COMPLETE
References: Deliverable Task 2
Depends on: P-14 (individual pattern files must exist first)

**Affected files (new):** `docs/patterns/index.md`

**Changes required:**
Create a single index file that lists every pattern with:
- Pattern number
- File link (`[slug](./NN-slug.md)`)
- One-line summary (the first sentence of the pattern body)
- Tags (from the pattern's frontmatter)

Format as a markdown table. Do not summarise the patterns yourself —
extract the first sentence of each `docs/patterns/-*.md` body
programmatically:

```bash
for f in docs/patterns/[0-9]*.md; do
  num=$(grep "^number:" "$f" | awk '{print $2}')
  tags=$(grep "^tags:" "$f" | sed 's/tags: //')
  summary=$(awk '/^---/{p++} p==2{getline; print; exit}' "$f")
  echo "| $num | [$(basename $f .md)](./$f) | $summary | $tags |"
done
```

Add frontmatter: `kind: index`, `tags: [patterns]`.
Add a one-paragraph intro explaining what NIX-PATTERNS.md was and that
it has been split — for anyone who arrives via a stale link.

**Verification:**
```bash
wc -l docs/patterns/index.md   # should be roughly: 2 + num_patterns rows + header
# Confirm the table has the right number of rows:
grep "^|" docs/patterns/index.md | wc -l   # should equal num_patterns + 2 (header + separator)
```

---

## P-20 — Create docs/roadmap/stages.md

Status: COMPLETE
References: Deliverable Task 2
Depends on: P-03 (STAGES.md table fixed), P-12 (PROGRESS.md slimmed)

**Affected files:**
- `docs/roadmap/stages.md` (new)

**Changes required:**
1. Create `docs/roadmap/stages.md` containing ONLY the phase/stage
   summary table — no per-stage prose. The table columns: Phase, Stage,
   Name, Host, Status. Status values: ✅ Complete, 🔄 In progress,
   ☐ Not started.

   Update statuses to match `PROGRESS.md` (Stages 1–10b ✅, Stage 11 ☐).

   Add frontmatter: `kind: roadmap`, `tags: [stages, roadmap]`.
   Add one intro sentence pointing to individual stage files in
   `docs/roadmap/stage-NN-*.md` for narrative details.

**Verification:**
```bash
head -20 docs/roadmap/stages.md   # should show frontmatter + table header
grep "✅" docs/roadmap/stages.md | wc -l   # should equal 14 (stages 1-10b)
grep "☐" docs/roadmap/stages.md | wc -l   # should equal 8 (stages 11-18)
```

---

## P-21 — Create per-machine README.md files

Status: COMPLETE
References: Deliverable Task 2
Depends on: P-04 (STRUCTURE.md fixed so we know what exists)

**Affected files (all new):**
- `machines/nixos/pebble/README.md`
- `machines/nixos/vps/README.md`

**Changes required:**
Content is derived from `machines/nixos/{host}/default.nix`,
`machines/nixos/{host}/disko.nix`, `.sops.yaml`, and the relevant
PROGRESS.md sections. Do not invent values — read the actual files.

1. `machines/nixos/pebble/README.md` — sections:
   - **Role:** homelab server, primary service host, routing peer
   - **Hardware:** HP ProDesk (from hardware.nix comments + ARCHITECTURE.md)
   - **Network:** static IP from `vars.nix`, interface name, gateway
   - **Disk:** ZFS pool name, device, dataset layout (from disko.nix)
   - **Secrets file:** `secrets/secrets.yaml` (age keys: admin + pebble)
   - **Hostkey path:** `/etc/ssh/ssh_host_ed25519_key`
   - **Deploy:** `just deploy pebble` (uses IP from vars.nix per Pattern 18)
   - **One-time post-provision steps:** NetBird login command (from PROGRESS.md Stage 7b)
   Frontmatter: `kind: host`, `tags: [pebble, homelab]`.
   Target: ≤80 lines.

2. `machines/nixos/vps/README.md` — sections:
   - **Role:** NetBird control plane, Pocket ID IdP, public entry point
   - **Hardware:** Hetzner CX22, public IP from `vars.nix`
   - **Network:** static public IP, no CGNAT
   - **Disk:** ext4 on `/dev/sda` (from disko.nix)
   - **Secrets file:** `secrets/vps.yaml` (age keys: admin + vps)
   - **Hostkey path:** `/etc/ssh/ssh_host_ed25519_key`
   - **Deploy:** `just deploy-vps` (uses IP from vars.nix per Pattern 18)
   - **Initial provisioning:** `just provision-vps ` (nixos-anywhere)
   - **One-time post-provision steps:** NetBird server login, Pocket ID
     setup at `/login/setup`, SQLite user-approval command (from
     PROGRESS.md Stage 7a and 10b)
   Frontmatter: `kind: host`, `tags: [vps, netbird, pocket-id]`.
   Target: ≤80 lines.

**Verification:**
```bash
ls machines/nixos/*/README.md   # two files
for f in machines/nixos/*/README.md; do
  echo "=== $f ==="; wc -l "$f"; grep "^kind:" "$f"
done
# each under 80 lines, frontmatter present
```

---

## P-22 — Disposition leftover docs after restructure

Status: COMPLETE
References: Deliverable Task 2 (final cleanup)
Depends on: P-11 (service READMEs), P-12 (PROGRESS.md slimmed),
            P-15 (ADRs), P-16 (archive pass), P-17 (arch docs),
            P-20 (roadmap/stages.md), P-21 (machine READMEs)

This item must run LAST in the doc restructure sequence. All content
must already be redistributed before these files are touched.

**Affected files:**
- `docs/ARCHITECTURE.md` (convert to redirect)
- `docs/IDP-STRATEGY.md` (archive)
- `docs/SECOND-MACHINE.md` (move to roadmap)
- `docs/SERVICE-CONFIGS.md` (convert to redirect)
- `docs/STRUCTURE.md` (rework as nav guide)
- `docs/VPS-LOKI-SHIPPING.md` (archive)

**Changes required:**

### 1. docs/ARCHITECTURE.md → redirect pointer

Before touching this file, verify its content has been fully
redistributed:
- Topology and machine roles → `docs/architecture/overview.md` (P-17)
- Auth flow → `docs/architecture/auth.md` (P-17)
- Port and DNS tables → `docs/architecture/ports-and-dns.md` (P-17)
- Decisions → `docs/architecture/adr/*.md` (P-15)

Then replace the body with:
```markdown
---
kind: redirect
superseded_by:
  - docs/architecture/overview.md
  - docs/architecture/auth.md
  - docs/architecture/ports-and-dns.md
  - docs/architecture/adr/
---

# Architecture

This file has been split into focused documents:

- **[Overview](./architecture/overview.md)** — topology, machines, networking
- **[Auth](./architecture/auth.md)** — Pocket ID, Kanidm, per-service SSO
- **[Ports & DNS](./architecture/ports-and-dns.md)** — generated reference tables
- **[ADRs](./architecture/adr/)** — one file per architecture decision

```

Do NOT delete the file. External links and `git log` references stay valid.

### 2. docs/IDP-STRATEGY.md → archive

Before touching: verify `docs/architecture/auth.md` exists and covers
the same ground (two-tier IdP design, per-service auth table, OIDC flow).

```bash
git mv docs/IDP-STRATEGY.md docs/archive/idp-strategy-exploration.md
```

Update frontmatter in the moved file:
```yaml
kind: archive
status: archived
superseded_by: docs/architecture/auth.md
```

P-01 already added a "Superseded" banner — leave it, update the
`superseded_by` path to point to `auth.md`.

### 3. docs/SECOND-MACHINE.md → roadmap (not archive)

This is Phase 2 active planning, not stale research. It informs
Stage 11+ work and should stay discoverable.

```bash
git mv docs/SECOND-MACHINE.md docs/roadmap/phase-2-boulder.md
```

Add/update frontmatter:
```yaml
kind: roadmap
status: active
tags: [boulder, phase-2, immich, jellyfin]
```

Add one line at the top of the body:
```markdown
> Active planning document for Phase 2 (Stages 11–18).
> See docs/roadmap/stages.md for the stage overview.
```

### 4. docs/SERVICE-CONFIGS.md → redirect pointer

Before touching: verify every service that has a `homelab//default.nix`
also has a `homelab//README.md` with ports, secrets, and gotchas:
```bash
for d in homelab/*/; do
  svc=$(basename "$d")
  [ -f "$d/README.md" ] || echo "MISSING: $d/README.md"
done
```
If any READMEs are missing, stop and complete P-11 first.

Then replace the body of `docs/SERVICE-CONFIGS.md` with:
```markdown
---
kind: redirect
superseded_by: homelab/*/README.md
---

# Service configurations

Per-service documentation has moved to co-located README files:

| Service | Docs |
|---------|------|
| caddy | [homelab/caddy/README.md](../homelab/caddy/README.md) |
| kanidm | [homelab/kanidm/README.md](../homelab/kanidm/README.md) |
| ... (one row per service) ... |

```
Populate the table by running:
```bash
for d in homelab/*/; do
  svc=$(basename "$d")
  echo "| $svc | [homelab/$svc/README.md](../homelab/$svc/README.md) |"
done
```

### 5. docs/STRUCTURE.md → short navigation guide

The literal directory tree in this file rots after every structural
change. Replace it with a prose navigation guide (≤60 lines) that
describes WHERE things live conceptually, not a tree.

Replace the entire body with sections:
- **Configuration** — `machines/nixos//` is where each host's
  NixOS config lives. `homelab//` is where each service
  module and its docs live. `modules/` contains shared NixOS modules.
- **Secrets** — `secrets/*.yaml` encrypted with sops. `.sops.yaml`
  defines which hosts can decrypt which files.
- **Documentation** — `docs/` tree: `architecture/`, `operations/`,
  `patterns/`, `roadmap/`, `archive/`. Per-service docs live with
  the service module, not in `docs/`.
- **Agent tooling** — `.agent/skills/` for Claude Code skills.
  `.agent/mcp/` for the MCP server. `.mcp.json` registers the server.
- **Generating the current tree** — run `tree -L 3 -I 'result|.git'`
  at the repo root. The tree is not committed because it drifts.

Update frontmatter:
```yaml
kind: architecture
tags: [navigation, structure]
```

### 6. docs/VPS-LOKI-SHIPPING.md → archive

Before touching: verify Stage 10 is marked COMPLETE in PROGRESS.md and
that `docs/roadmap/stage-10-*.md` (created by P-12) covers the
implementation outcome.

```bash
git mv docs/VPS-LOKI-SHIPPING.md \
       docs/archive/vps-loki-shipping-research.md
```

Update frontmatter:
```yaml
kind: archive
status: archived
superseded_by: docs/roadmap/stage-10-hardening.md
```

**Verification:**
```bash
# Redirect pointers exist (not deleted)
ls docs/ARCHITECTURE.md docs/SERVICE-CONFIGS.md docs/STRUCTURE.md

# Archived files moved
ls docs/archive/idp-strategy-exploration.md
ls docs/archive/vps-loki-shipping-research.md

# Roadmap file moved
ls docs/roadmap/phase-2-boulder.md

# No broken internal links in docs/
grep -rh "\](\.\./" docs/ | grep -oP '\.\./[^)]+' | while read l; do
  [ -e "docs/$l" ] || echo "BROKEN: $l"
done

# Frontmatter present in all six files
for f in docs/ARCHITECTURE.md docs/SERVICE-CONFIGS.md docs/STRUCTURE.md \
          docs/archive/idp-strategy-exploration.md \
          docs/archive/vps-loki-shipping-research.md \
          docs/roadmap/phase-2-boulder.md; do
  grep -q "^kind:" "$f" && echo "OK: $f" || echo "MISSING frontmatter: $f"
done
```

**Propose a commit:**
```
docs: disposition leftover docs after restructure (P-22)

- ARCHITECTURE.md, SERVICE-CONFIGS.md, STRUCTURE.md → redirect pointers
- IDP-STRATEGY.md, VPS-LOKI-SHIPPING.md → docs/archive/
- SECOND-MACHINE.md → docs/roadmap/phase-2-boulder.md (active planning)
```

---

## Completion summary

| ID | Description | Status |
|----|-------------|--------|
| P-10 | implement-plan skill (do this first) | COMPLETE |
| P-01 | Fix IDP-STRATEGY.md | COMPLETE |
| P-02 | Fix NETBIRD-SELFHOSTED.md | COMPLETE |
| P-03 | Fix STAGES.md table | COMPLETE |
| P-04 | Fix STRUCTURE.md phantom dirs | COMPLETE |
| P-05 | Fix .sops.yaml comment | COMPLETE |
| P-06 | Fix Traefik references | COMPLETE |
| P-07 | Remove stale VERIFY markers | COMPLETE |
| P-08 | Create six new agent skills | COMPLETE |
| P-09 | Create MCP server | COMPLETE |
| P-11 | Per-service README.md files | COMPLETE |
| P-12 | Slim PROGRESS.md + docs/roadmap/ | COMPLETE |
| P-13 | MkDocs portal | COMPLETE |
| P-14 | Split NIX-PATTERNS.md | COMPLETE |
| P-15 | Create docs/architecture/adr/ | COMPLETE |
| P-16 | Move research docs to docs/archive/ | COMPLETE |
| P-17 | docs/architecture/ non-ADR files        | COMPLETE |
| P-18 | docs/operations/ runbooks               | COMPLETE |
| P-19 | docs/patterns/index.md                  | COMPLETE |
| P-20 | docs/roadmap/stages.md                  | COMPLETE |
| P-21 | Per-machine README.md files             | COMPLETE |
| P-22 | Disposition leftover docs after restructure | COMPLETE |
