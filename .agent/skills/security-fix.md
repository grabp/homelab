---
name: security-fix
description: Work through a SECURITY-TODO.md item for this homelab. Use when starting a new security remediation item (S-01, S-02, etc.) or when the user says "let's do S-XX".
argument-hint: [S-XX item ID]
disable-model-invocation: true
---

Work through security remediation item `$ARGUMENTS` from SECURITY-TODO.md.

## Protocol

1. **Read the item** from SECURITY-TODO.md — note the finding reference (F-XX), affected files,
   exact changes required, and verification steps.

2. **Read every affected file in full** before touching anything.

3. **State the change** before making it: which file, which line(s), and why.

4. **Make the change** using Edit (never invent NixOS options — if unsure, say so and ask).

5. **Build** to catch eval errors:
   ```bash
   nix build .#nixosConfigurations.pebble.config.system.build.toplevel --no-link
   ```
   For VPS-only changes:
   ```bash
   nix build .#nixosConfigurations.vps.config.system.build.toplevel --no-link
   ```

6. **If the build fails**, fix the error and rebuild before proceeding.

7. **Report** the exact diff, the build result, and the verification steps the user must run
   after deploying.

8. **Update SECURITY-TODO.md** — change `Status: NOT STARTED` to `Status: COMPLETE` for the item.

9. **Propose a commit** in conventional commit format. Do not commit — the user commits.

## Constraints (from SECURITY-SESSION.md)

- Never invent NixOS options. If unsure an option exists, say so and ask.
- Use patterns from docs/NIX-PATTERNS.md as templates.
- `just build` targets the local machine (koksownik) which is not in this flake.
  Always use `nix build .#nixosConfigurations.<host>...` directly.
- Before deploying, spell out any required manual steps (secrets rotation,
  dashboard config, SSH commands) and wait for confirmation.
- If a finding contradicts the fix approach, say so immediately.
