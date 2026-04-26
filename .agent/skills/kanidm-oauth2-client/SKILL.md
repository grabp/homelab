---
name: kanidm-oauth2-client
description: Use this skill any time the user mentions adding OIDC/OAuth2 login to an existing homelab service, federating a new service with Kanidm or Pocket ID, or "wiring single sign-on for X". Trigger on phrases like "add OIDC to", "SSO for", "OAuth2 client", "Kanidm client". This encodes the verified-working co-location pattern with the right ownership/mode bits so the client secret can actually be read at runtime.
model: inherit
tools: Read, Write, Edit, Bash, Glob, Grep
argument-hint: <service-name> [--scopes openid,email,profile,groups]
disable-model-invocation: false
user-invocable: true
---

# Add a Kanidm OAuth2 client

## Pre-flight
1. `Read homelab/kanidm/default.nix` — see how other clients are provisioned under `services.kanidm.provision.systems.oauth2.*`.
2. `Read homelab/pocket-id/default.nix` — see the companion Pocket ID client entry (Pocket ID is the front-end IdP).
3. `Read homelab/<service>/default.nix` — identify the systemd service's User/Group and whether it supports `EnvironmentFile=`.
4. Confirm `redirect_uri` from the service's upstream documentation (this is the #1 source of 400 errors).

## Steps

### 1. Kanidm side (co-location pattern)
In `homelab/kanidm/default.nix` (NOT in the service's module), add:

```nix
services.kanidm.provision.systems.oauth2.<service> = {
  displayName = "<Service>";
  originUrl   = "https://<service>.${config.homelab.baseDomain}/oauth2/callback";
  originLanding = "https://<service>.${config.homelab.baseDomain}/";
  basicSecretFile = config.sops.secrets."kanidm-oauth2-<service>".path;
  scopeMaps."<group-name>" = [ "openid" "email" "profile" "groups" ];
  preferShortUsername = true;
};
```

### 2. Pocket ID side (if the service authenticates via Pocket ID, which is the current default)
Add a matching client in `homelab/pocket-id/default.nix` with the same redirect URI and a separate `basicSecretFile`.

### 3. Secret declaration
Generate:
```
openssl rand -hex 32 > /tmp/secret-value
just edit-secrets secrets/kanidm.yaml   # add key: kanidm-oauth2-<service>
just edit-secrets secrets/pocket-id.yaml  # add key: pocket-id-<service>-secret
```
In `homelab/kanidm/default.nix`:
```nix
sops.secrets."kanidm-oauth2-<service>" = {
  sopsFile = ../../secrets/kanidm.yaml;
  owner = config.services.kanidm.group;   # OR the kanidm user
  group = config.services.kanidm.group;
  mode  = "0440";                          # group-readable, not world
};
```

### 4. Service side
Wire the client-id / client-secret / issuer URL into the service config. For OCI containers: prefer `environmentFiles = [ config.sops.secrets."<service>-oidc-env".path ];` with a k=v file, NOT individual env vars.

## Verification
```bash
systemctl status kanidm           # must be active
journalctl -u kanidm -n 50 | grep -i "oauth2.*<service>"
curl -s https://id.<domain>/.well-known/openid-configuration | jq .
# Then complete a login flow manually
```

## Gotchas the LLM otherwise relearns
- `mode = "0400"` + owner = service user **breaks** because Kanidm reads the file, not the service. Must be `0440` + group = kanidm's group.
- `originUrl` must be the **OAuth callback**, not the service's landing page. Most services document this badly.
- Kanidm requires `https://` even for `.lan` domains; make sure the internal CA is in place first (Stage 11+).
- If the service is behind Caddy, the redirect goes via Caddy so `originUrl` uses the public-facing FQDN, not `localhost:PORT`.
