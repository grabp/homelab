---
kind: pattern
number: 21
tags: [kanidm, OAuth2, OIDC, provisioning]
---

# Pattern 21: Kanidm with declarative OAuth2 client provisioning

Kanidm's `services.kanidm.provision` block lets you define users, groups, and OAuth2 resource servers in NixOS config. **No web UI clicking required.** Each service module co-locates its Kanidm client definition alongside its service config.

```nix
# homelab/kanidm/default.nix — verified working pattern (nixos-25.11, kanidm 1.9)
{ config, lib, pkgs, vars, ... }:
{
  # CLI in PATH without enableClient (which requires clientSettings to also be set)
  environment.systemPackages = [ pkgs.kanidmWithSecretProvisioning_1_9 ];

  # Kanidm requires TLS even on localhost. Generate a self-signed cert that:
  # - has basicConstraints=CA:FALSE (kanidm 1.9 rejects CA:TRUE with CaUsedAsEndEntity)
  # - has a SAN for 127.0.0.1 (needed for direct localhost CLI connections)
  # Detect and regenerate bad old certs (CA:TRUE) automatically.
  systemd.services.kanidm-tls-cert = {
    description = "Generate Kanidm self-signed TLS certificate";
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    path = [ pkgs.openssl ];
    script = ''
      install -d -m 750 -o kanidm -g kanidm /var/lib/kanidm
      needs_regen=0
      [ ! -f /var/lib/kanidm/tls.pem ] && needs_regen=1
      if [ -f /var/lib/kanidm/tls.pem ]; then
        openssl x509 -in /var/lib/kanidm/tls.pem -noout -text 2>/dev/null \
          | grep -q "CA:TRUE" && needs_regen=1
      fi
      if [ "$needs_regen" = "1" ]; then
        openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
          -keyout /var/lib/kanidm/tls.key -out /var/lib/kanidm/tls.pem \
          -days 3650 -nodes -subj '/CN=id.${vars.domain}' \
          -addext "basicConstraints=CA:FALSE" \
          -addext "subjectAltName=IP:127.0.0.1,DNS:id.${vars.domain}"
        chown kanidm:kanidm /var/lib/kanidm/tls.key /var/lib/kanidm/tls.pem
        chmod 600 /var/lib/kanidm/tls.key && chmod 644 /var/lib/kanidm/tls.pem
      fi
    '';
  };
  systemd.services.kanidm = {
    requires = [ "kanidm-tls-cert.service" ];
    after    = [ "kanidm-tls-cert.service" ];
  };

  services.kanidm = {
    enableServer = true;
    # nixos-25.11 module defaults to kanidm_1_4 (EOL, removed from nixpkgs).
    # _1_7 is also gone (insecure). Must pin explicitly.
    package = pkgs.kanidmWithSecretProvisioning_1_9;
    serverSettings = {
      origin          = "https://id.${vars.domain}";
      domain          = "id.${vars.domain}";
      bindaddress     = "127.0.0.1:8443";
      ldapbindaddress = "127.0.0.1:636";
      tls_chain       = "/var/lib/kanidm/tls.pem";
      tls_key         = "/var/lib/kanidm/tls.key";
    };
    provision = {
      enable             = true;
      instanceUrl        = "https://127.0.0.1:8443";
      acceptInvalidCerts = true;  # required for self-signed cert
      # owner = "kanidm" REQUIRED — provisioning ExecStartPost runs as kanidm user,
      # default root:root 0400 causes "permission denied"
      adminPasswordFile    = config.sops.secrets."kanidm/admin_password".path;
      idmAdminPasswordFile = config.sops.secrets."kanidm/idm_admin_password".path;

      # IMPORTANT: "admin" is Kanidm's built-in system account — provisioning a
      # person named "admin" → 409 Conflict. Use a distinct username.
      persons."yourname" = {
        displayName   = "Your Name";
        mailAddresses = [ "admin@${vars.domain}" ];
      };
      groups."homelab_users".members  = [ "yourname" ];
      groups."homelab_admins".members = [ "yourname" ];
    };
  };

  sops.secrets."kanidm/admin_password"     = { owner = "kanidm"; };
  sops.secrets."kanidm/idm_admin_password" = { owner = "kanidm"; };
  # mode 0444: readable by both kanidm provisioning and service clients ($__file{})
  sops.secrets."kanidm/grafana_client_secret" = { mode = "0444"; };

  networking.firewall.allowedTCPPorts = [ 636 ];
  # Port 8443 NOT opened — Caddy proxies it via localhost
}
```

```nix
# homelab/grafana/default.nix — OAuth2 client co-located with service
{ config, lib, vars, ... }:
{
  # Kanidm OAuth2 client for Grafana — defined here, not in kanidm/default.nix
  # basicSecretFile: pre-seed the secret from sops → single-phase deploy
  services.kanidm.provision.systems.oauth2."grafana" = {
    displayName     = "Grafana";
    originUrl       = "https://grafana.${vars.domain}/login/generic_oauth";
    originLanding   = "https://grafana.${vars.domain}";
    basicSecretFile = config.sops.secrets."kanidm/grafana_client_secret".path;
    scopeMaps."homelab_users" = [ "openid" "profile" "email" "groups" ];
  };
}
```

**Kanidm OIDC issuer URL pattern (per-client, not global):**
```
https://id.grab-lab.gg/oauth2/openid/<client-name>/.well-known/openid-configuration
```

**Setting a person's login password after first deploy:**
```bash
kanidm --url https://id.grab-lab.gg login --name idm_admin
kanidm --url https://id.grab-lab.gg person credential create-reset-token <username>
# open the printed URL in browser
```

**Known gotchas:**
- **`kanidm_1_4` removed** — explicitly set `package = pkgs.kanidmWithSecretProvisioning_1_9`
- **"admin" username reserved** — use a distinct person username
- **sops ownership** — password secrets need `owner = "kanidm"`; OAuth2 secret needs `mode = "0444"`
- **CA:FALSE required** — self-signed cert must not have `CA:TRUE` (kanidm 1.9 CaUsedAsEndEntity error)
- **`enableClient = true` requires `clientSettings`** — use `environment.systemPackages` instead
- **PKCE enforced** — set `use_pkce = true` in Grafana and equivalent in other clients
- **Groups as SPNs** — `groups` claim is `groupname@kanidm-domain`, not bare name; adjust role mappings
- Per-client issuer URLs (not a single global issuer)
- ES256 token signing (not RS256) — most modern apps handle this

**Source:** `services.kanidm` verified in nixos-25.11 ✅. All gotchas verified in production deployment ✅.
