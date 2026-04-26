---
name: implement-plan
description: Use this skill when the user says "implement plan item P-XX", "work on P-XX", "do the next PLAN item", or "continue the improvement plan". Reads PLAN.md, works through exactly one item end-to-end, verifies, and updates the status. Mirrors the security-fix protocol adapted for the homelab improvement plan.
model: inherit
tools: Read, Write, Edit, Bash, Glob, Grep
argument-hint: [P-XX item ID]
disable-model-invocation: false
user-invocable: true
---

Work through plan item `$ARGUMENTS` from PLAN.md.

## Protocol

1. **Read the item** from PLAN.md — note the status, affected files, exact changes required, and verification steps.

2. **If status is COMPLETE**, stop immediately and tell the user.

3. **Read every affected file in full** before touching anything.

4. **State the change** before making it: which file, which section, and why.

5. **Make the change** using Edit/Write as appropriate.

6. **Run the verification command(s)** specified in the item. Report output verbatim.

7. **If verification fails**, fix the error and re-verify before proceeding.

8. **Update PLAN.md** — change `Status: NOT STARTED` to `Status: COMPLETE` for the item. Also update the completion summary table at the bottom.

9. **Propose a commit** in conventional commit format. Do not commit — the user commits.

## Constraints

- Never invent NixOS options. If unsure an option exists, say so and stop.
- Use patterns from docs/patterns/ as templates.
- For NixOS changes: always run `nix flake check` as part of verification.
- For Python/MCP changes (P-09): always run `pytest -q` as part of verification.
- Before any deploy, spell out required manual steps and wait for user confirmation.
- If a plan item's requirements contradict the current codebase in a way that matters, say so immediately instead of proceeding blindly.

## Order constraint

P-10 (this skill) must be complete before any other item. If the user asks to run a different item first, do P-10 first and then ask them to re-invoke for their intended item.

Items P-01 through P-07 are independent and can be done in any order.
P-08 (skills) and P-09 (MCP server) are independent of each other but should come after P-01–P-07.
P-11 (per-service READMEs) should come after P-01–P-07.
P-12 depends on P-11.
P-13 depends on P-11 and P-12.
