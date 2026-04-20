{ config, lib, pkgs, vars, ... }:

let
  cfg = config.my.services.pihole;
in
{
  options.my.services.pihole = {
    enable = lib.mkEnableOption "Pi-hole DNS sinkhole";

    webPort = lib.mkOption {
      type = lib.types.port;
      default = 8089;
      description = "Host port for the Pi-hole web UI (mapped to container port 80)";
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "pihole/pihole:2025.02.1";
      description = "Pi-hole OCI image with version tag";
    };
  };

  config = lib.mkIf cfg.enable {
    # FTLCONF_webserver_api_password=<password> — add to secrets/secrets.yaml
    sops.secrets."pihole/env" = { };

    # Persistent ZFS-backed directories for Pi-hole state and dnsmasq extras
    systemd.tmpfiles.rules = [
      # Pi-hole's FTL process runs as UID/GID 1000 (pihole user) inside the container.
      # SQLite WAL mode requires write access to the directory (to create .db-wal/.db-shm).
      # The directory must be owned by 1000:1000, not root, or all DB writes fail with
      # "attempt to write a readonly database".
      "d /var/lib/pihole         0755 1000 1000 -"
      "d /var/lib/pihole-dnsmasq 0755 root root -"
    ];

    # Write wildcard split DNS config. Activation scripts run before services
    # start, so the file is present when the container mounts /etc/dnsmasq.d/.
    # FTLCONF_misc_dnsmasq_lines is unusable for address= directives because
    # Pi-hole v6 splits array items on '=' (treating it as a key-value pair),
    # discarding everything after the first '='.
    system.activationScripts.pihole-dnsmasq-config = lib.stringAfter [ "var" ] ''
      mkdir -p /var/lib/pihole-dnsmasq
      {
        # VPS-hosted services — specific entries override the wildcard below.
        echo "address=/netbird.${vars.domain}/${vars.vpsIP}"
        echo "address=/pocket-id.${vars.domain}/${vars.vpsIP}"

        # Wildcard split DNS: *.grab-lab.gg → Caddy (on pebble)
        echo "address=/${vars.domain}/${vars.serverIP}"
      } > /var/lib/pihole-dnsmasq/04-grab-lab.conf
      # Reload Pi-hole's DNS engine to pick up the new config.
      # Silently ignored if the container isn't running yet (e.g. first boot).
      # Note: `pihole restartdns reload` (soft reload) is not valid in Pi-hole 2025.x;
      # use `restartdns` alone which triggers a full FTL restart inside the container.
      ${pkgs.podman}/bin/podman exec pihole pihole restartdns >/dev/null 2>&1 || true
    '';

    virtualisation.oci-containers.containers.pihole = {
      image = cfg.image;

      ports = [
        "53:53/tcp"
        "53:53/udp"
        "${toString cfg.webPort}:80/tcp"
      ];

      volumes = [
        "/var/lib/pihole:/etc/pihole"
        "/var/lib/pihole-dnsmasq:/etc/dnsmasq.d"
      ];

      environment = {
        TZ = vars.timeZone;
        # Accept queries from all networks (not just the container bridge subnet)
        FTLCONF_dns_listeningMode = "ALL";
        # Cloudflare DNS upstreams instead of Pi-hole's default (Google)
        FTLCONF_dns_upstreams = "1.1.1.1;1.0.0.1";
        # Tell Pi-hole v6 to read custom dnsmasq configs from /etc/dnsmasq.d/
        # (disabled by default in v6; our 04-grab-lab.conf is written there via
        # system.activationScripts)
        FTLCONF_misc_etc_dnsmasq_d = "true";
        # Conditional forwarding for .lan/.local → router (UniFi hostnames, DHCP names).
        # server=/domain/ip in dnsmasq conf-dir files is a known Pi-hole v6 bug (#6279)
        # that returns 0ms NXDOMAIN without forwarding. FTLCONF_dns_revServers is the
        # correct Pi-hole v6 mechanism. Format: "enable,CIDR,server#port,domain"
        FTLCONF_dns_revServers = "true,192.168.1.0/24,${vars.routerIP}#53,lan;true,192.168.1.0/24,${vars.routerIP}#53,local";
      };

      # Contains FTLCONF_webserver_api_password — decrypted by sops at /run/secrets/pihole/env
      environmentFiles = [
        config.sops.secrets."pihole/env".path
      ];

      extraOptions = [
        "--cap-add=NET_ADMIN"
        # No --dns override: container inherits host resolv.conf (1.1.1.1/8.8.8.8).
        # --dns=127.0.0.1 caused gravity to fail on first boot because FTL isn't
        # ready yet when the container's own DNS is needed for blocklist downloads.
      ];
    };

    # -------------------------------------------------------------------------
    # TODO: Declarative adlists (container-friendly implementation)
    #
    # Implement as a systemd oneshot that runs after the container starts,
    # using `podman exec pihole sqlite3 /etc/pihole/gravity.db` to insert
    # into the adlist table, then `podman exec pihole pihole -g` to update
    # gravity. Each insert must check for existence first (idempotent).
    #
    # Service ordering:
    #   after   = [ "podman-pihole.service" ]
    #   requires = [ "podman-pihole.service" ]
    #
    # --- PHASE 1: Security & Malware Protection (enable immediately) ----------
    # These focus on security without breaking social media functionality.
    # Test for 1–2 weeks before enabling Phase 2.
    #
    #   [enabled] Steven Black — Unified Hosts (Malware + Ads)
    #     https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
    #
    #   [enabled] Phishing Army — Extended Protection
    #     https://phishing.army/download/phishing_army_blocklist_extended.txt
    #
    #   [optional] MalwareDomains — additional malware coverage
    #     https://mirror1.malwaredomains.com/files/domains.txt
    #
    # --- PHASE 2: Broader Ad & Tracking Blocking (enable after Phase 1) ------
    # Uncomment only after confirming Meta products (Instagram, Facebook) work.
    # Common allowlist domains if broken: facebook.com, fbcdn.net,
    # instagram.com, cdninstagram.com
    #
    #   [disabled] AdAway — Default Blocklist
    #     https://adaway.org/hosts.txt
    #
    #   [disabled] Peter Lowe — Ad Servers
    #     https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext
    #
    #   [disabled] Disconnect.me — Simple Tracking
    #     https://s3.amazonaws.com/lists.disconnect.me/simple_tracking.txt
    #
    #   [disabled] Disconnect.me — Simple Ad
    #     https://s3.amazonaws.com/lists.disconnect.me/simple_ad.txt
    # -------------------------------------------------------------------------

    # When nixos-rebuild switch reloads the firewall (e.g. a new port was opened),
    # NixOS flushes and rewrites ALL iptables chains — including the NETAVARK_*
    # chains that Podman/Netavark wrote for port 53 DNAT. If podman-pihole is not
    # restarted afterward, the DNAT rules are gone and external DNS queries time out
    # even though the container is running.
    # partOf: restart this service whenever firewall.service restarts.
    # after:  ensure we start after the firewall so rules are added last.
    systemd.services.podman-pihole = {
      after = [ "firewall.service" ];
      partOf = [ "firewall.service" ];
    };

    networking.firewall.allowedTCPPorts = [ 53 cfg.webPort ];
    networking.firewall.allowedUDPPorts = [ 53 ];
  };
}
