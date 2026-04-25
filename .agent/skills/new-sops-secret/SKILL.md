---
name: new-sops-secret
description: Use this skill whenever the user needs a new secret in the homelab — phrases like "generate a token for", "new API key", "add secret", "I need a password for X". Handles generation with appropriate entropy, encryption with sops, declaration in the Nix module, and ownership/mode bits. Saves the agent from rediscovering the owner=user|group + mode=0400|0440 decision tree from scratch.
model: inherit
tools: Read, Write, Edit, Bash, Glob, Grep
argument-hint: <secret-name> [--hex | --base64 | --passphrase] [--bytes N]
disable-model-invocation: false
user-invocable: true
---

# New sops-encrypted secret

## Pre-flight
1. `Read .sops.yaml` — confirm the secret's target file has a creation_rule and which hosts (`*pebble`, `*vps`) can decrypt it.
2. `Read homelab/<service>/default.nix` — identify the consuming systemd service's User and Group.
3. Decide the owner/mode matrix:
   - Read by the service itself as User=X → `owner = "X"; mode = "0400";`
   - Read by a sidecar (e.g. Kanidm provisioning reads it on behalf of another service) → `group = "<sidecar-group>"; mode = "0440";`
   - Read at runtime by a container's env file → owner = root, mode = 0400, and pass via `environmentFiles`, NOT bind-mount.

## Generate
Pick entropy source:
- API tokens, client secrets: `openssl rand -hex 32`
- Binary keys / symmetric encryption: `openssl rand -base64 48`
- Human-typeable (rarely needed): `pwgen -s 32 1`

Do NOT print the generated value to chat. Pipe to clipboard or temp file:
```bash
openssl rand -hex 32 | xclip -selection clipboard   # Linux
# then: just edit-secrets secrets/<file>.yaml, paste
```

## Declare in Nix
```nix
sops.secrets."<key-name>" = {
  sopsFile = ../../secrets/<file>.yaml;
  owner = "<systemd-user>";
  group = "<systemd-group>";
  mode  = "0400";   # or 0440 per matrix above
  restartUnits = [ "<service>.service" ];   # ensures secret rotation triggers restart
};
```

## If a new host is being added to the rule
Append `*<host>` to the creation_rule, then:
```bash
just rekey     # re-encrypts all sops files for the updated key set
```

## Verification (after deploy)
```bash
ssh <host> "sudo ls -la /run/secrets/<key-name>"   # expect right owner, right mode
ssh <host> "sudo systemctl status <service>"      # no 'secret not found' errors
ssh <host> "sudo journalctl -u <service> -n 30"
```

## Common mistakes this skill prevents
- Forgetting `restartUnits` → secret rotates but service still has old value until next reboot.
- Using `mode = "0444"` (world-readable) on a production secret.
- Declaring the secret but forgetting to add the host to `.sops.yaml` creation_rules → decryption fails silently at activation with a cryptic "no key to decrypt" in the journal.
- Committing the plaintext accidentally via `edit-secrets` abort — always `git diff --cached` before commit.
