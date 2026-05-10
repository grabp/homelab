# Periodic restart workaround for the NetBird stale-relay bug (netbirdio/netbird#3936).
#
# Behind symmetric NAT / CGNAT, WireGuard hole-punching fails and all
# traffic is relayed through the VPS coturn server.  The TURN relay
# allocations have a 12-hour TTL (CredentialsTTL in management.json).
# When the allocation expires, the NetBird daemon detects a dead peer and
# should re-negotiate — but in practice it can get stuck: the WireGuard
# interface stays "Connected" in the dashboard while the kernel reports
# "Required key not available" for outbound packets.  A service restart
# forces a clean re-handshake and clears the stale session.
#
# Interval: every 6 hours — shorter than the 12-hour TURN TTL so the
# session is always refreshed before expiry, while still being infrequent
# enough to avoid disrupting in-flight connections (reconnect takes ~2s).
#
# Imported by:
#   homelab/netbird/default.nix  — pebble and boulder (via my.services.netbird)
#   machines/nixos/vps/netbird-client.nix — VPS hand-crafted client
{ ... }:
{
  systemd.timers.netbird-wt0-restart = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "6h";
      OnUnitActiveSec = "6h";
      # No Unit override — timer activates netbird-wt0-restart.service by name convention.
    };
  };

  systemd.services.netbird-wt0-restart = {
    description = "Periodic restart of netbird-wt0 to clear stale CGNAT relay sessions";
    serviceConfig = {
      Type = "oneshot";
      # --no-block: fire the restart and return immediately so systemd does not
      # deadlock waiting for this oneshot to exit while it is also waiting for
      # the restarted unit to reach its new start state.
      ExecStart = "/run/current-system/sw/bin/systemctl restart --no-block netbird-wt0.service";
    };
  };
}
