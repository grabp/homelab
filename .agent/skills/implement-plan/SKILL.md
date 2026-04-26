---
name: implement-plan
description: Use this skill when the user says "implement stage XX", "work on stage XX", "do the next stage", or "continue the roadmap". Reads docs/roadmap/stage-XX-*.md, works through exactly one stage end-to-end, verifies, and updates PROGRESS.md status.
model: inherit
tools: Read, Write, Edit, Bash, Glob, Grep
argument-hint: [stage number, e.g., "11" or "stage-11"]
disable-model-invocation: false
user-invocable: true
---

Work through roadmap stage `$ARGUMENTS` from docs/roadmap/.

## Protocol

1. **Parse the stage number** from `$ARGUMENTS` (e.g., "11", "stage-11", "Stage 11" → stage 11).

2. **Find and read the stage file** using Glob pattern `docs/roadmap/stage-{number}-*.md`.

3. **Check PROGRESS.md** — if stage is already COMPLETE, stop and tell the user.

4. **Read the stage file** fully — note:
   - What Gets Built
   - Key Files
   - Dependencies (check these are satisfied)
   - Verification Steps

5. **Read every affected file in full** before making changes.

6. **State the change** before making it: which file, which section, and why.

7. **Make the changes** using Edit/Write as appropriate.

8. **Run the verification steps** specified in the stage file. Report output verbatim.

9. **If verification fails**, fix the error and re-verify before proceeding.

10. **Update PROGRESS.md**:
    - Change stage status from `NOT STARTED` to `✅ COMPLETE` in the table
    - Update "Current Stage" header to next stage if this was current
    - Update stage file's frontmatter status from `not-started` to `complete`

11. **Propose a commit** in conventional commit format. Do not commit — the user commits.

## Constraints

- Never invent NixOS options. If unsure an option exists, use /nix-verify or say so and stop.
- Use patterns from docs/patterns/ as templates — reference by pattern ID in comments.
- For NixOS changes: always run `nix flake check` as part of verification.
- For service additions: follow the scaffold from /new-homelab-service skill pattern.
- Before any deploy, spell out required manual steps and wait for user confirmation.
- If a stage's requirements contradict the current codebase, say so immediately instead of proceeding.
- Check stage dependencies before starting — if blocked, stop and report.

## Stage Dependencies

Phase 1 (Stages 1-10b) must complete before Phase 2 (Stages 11-18).

Within Phase 2:
- Stage 11 (boulder base) must come first
- Stages 12-16 can be done in any order after 11
- Stage 17 (Windows VM) should come after Stage 11
- Stage 18 (Whisper migration) depends on Stage 11

## Special Cases

- **Stage 11 (boulder base)**: Similar to Stage 1 for pebble, requires physical hardware provisioning.
- **Stages with PostgreSQL**: Use shared PostgreSQL instance from Stage 12.
- **OAuth2 integration**: Use /kanidm-oauth2-client or reference Stage 7c patterns.
- **Container services**: Follow podman patterns from docs/patterns/.
