# machines/nixos/vps/pocket-id.nix — Pocket ID passkey-only OIDC provider
#
# Minimal IdP supporting WebAuthn/FIDO2 passkeys. Replaces the embedded Dex
# IdP that ships with NetBird management. Runs alongside the NetBird stack on
# the VPS so auth availability is independent of pebble.
#
# Served at https://pocket-id.grab-lab.gg via Caddy (caddy.nix).
#
# POST-DEPLOY SETUP (completed 2026-04-20):
#   1. Browse to https://pocket-id.grab-lab.gg/setup  (v2.x path)
#   2. Create admin account with a passkey; register backup passkey.
#   3. Admin → OIDC Clients → Add client:
#        Name:            NetBird
#        Public client:   ON  ← REQUIRED: dashboard is a SPA, never sends a secret;
#                               confidential client → 400 "client id or secret not provided"
#        PKCE:            ON
#        Redirect URIs:   https://netbird.grab-lab.gg/nb-auth
#                         https://netbird.grab-lab.gg/nb-silent-auth
#      → note Client ID (no secret needed for public client)
#   4. Admin → API Keys → Create token → note the API Token
#   5. Admin → Users → create your user account.
#   6. Admin → OIDC Clients → NetBird → assign user.
#
# ⚠ FIRST LOGIN after switching from embedded Dex:
#   The IDP manager syncs users from Pocket ID and creates them with
#   blocked=1 / pending_approval=1. Approve via SQLite before first login:
#     sudo sqlite3 /var/lib/netbird-mgmt/store.db \
#       "UPDATE users SET blocked=0, pending_approval=0, role='owner'
#        WHERE id='<pocket-id-user-uuid>';"
#   Then log in. No container restart needed (SQLite is read live).
#
# NetBird ↔ Pocket ID integration: see netbird-server.nix (EmbeddedIdP disabled).
#
# SECRETS (add to secrets/vps.yaml via `just edit-secrets-vps`):
#   pocket-id/env: |
#       ENCRYPTION_KEY=<openssl rand -base64 32>
{
  config,
  lib,
  vars,
  ...
}:

let
  cfg = config.my.services.pocketId;
in
{
  options.my.services.pocketId = {
    enable = lib.mkEnableOption "Pocket ID passkey-only OIDC provider";
  };

  config = lib.mkIf cfg.enable {

    sops.secrets."pocket-id/env" = { };

    systemd.tmpfiles.rules = [
      "d /var/lib/pocket-id 0750 root root -"
    ];

    virtualisation.oci-containers.containers.pocket-id = {
      image = "ghcr.io/pocket-id/pocket-id:v2.6.0@sha256:49c6a96d92b8f92f27afd17edff98873776ec16b757afd31ba8a4f767f10366a";
      ports = [ "127.0.0.1:1411:1411" ];
      volumes = [ "/var/lib/pocket-id:/app/data" ];
      environment = {
        APP_URL = "https://pocket-id.${vars.domain}";
        TRUST_PROXY = "true";
        VERSION_CHECK_DISABLED = "true";
        ANALYTICS_DISABLED = "true";
        ALLOW_USER_SIGNUPS = "disabled";
      };
      # Contains: ENCRYPTION_KEY=<base64>
      environmentFiles = [ config.sops.secrets."pocket-id/env".path ];
    };
  };
}
