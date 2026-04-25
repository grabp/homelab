---
kind: pattern
number: 22
tags: [caddy, kanidm, forward-auth, oauth2-proxy]
---

# Pattern 22: Caddy forward_auth with Kanidm

For services without native OIDC support (Uptime Kuma, Homepage), Caddy's `forward_auth` directive proxies authentication to Kanidm.

```nix
# In homelab/caddy/default.nix or the service's own module
services.caddy.virtualHosts."uptime.${vars.domain}" = {
  extraConfig = ''
    forward_auth localhost:8443 {
      uri /ui/oauth2/token/check
      copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
      transport http {
        tls_insecure_skip_verify
      }
    }
    reverse_proxy localhost:3001
  '';
};
```

⚠️ **VERIFY:** Kanidm's exact forward_auth endpoint. `/ui/oauth2/token/check` is the expected path but verify against the Kanidm documentation for your version.

**Alternative:** Use **oauth2-proxy** as a sidecar with Kanidm as the OIDC backend. More setup but better documented for the forward_auth use case:

```nix
# oauth2-proxy sidecar for services without native auth
virtualisation.oci-containers.containers.oauth2-proxy = {
  image = "quay.io/oauth2-proxy/oauth2-proxy:latest";
  environment = {
    OAUTH2_PROXY_PROVIDER = "oidc";
    OAUTH2_PROXY_OIDC_ISSUER_URL = "https://id.${vars.domain}/oauth2/openid/oauth2-proxy/.well-known/openid-configuration";
    OAUTH2_PROXY_CLIENT_ID = "oauth2-proxy";
    OAUTH2_PROXY_UPSTREAM = "http://localhost:3001";  # upstream service
    OAUTH2_PROXY_HTTP_ADDRESS = "0.0.0.0:4180";
  };
  environmentFiles = [ config.sops.secrets."oauth2-proxy/env".path ];
};
```

**Source:** Caddy `forward_auth` directive is documented in Caddy docs ✅. oauth2-proxy OIDC provider pattern is verified against oauth2-proxy docs ✅.
