---
kind: runbook
tags: [monitoring, grafana, loki, prometheus, alertmanager]
---

# Monitoring Runbook

## Stack Overview

**Architecture:** Prometheus → Grafana, Loki ← Alloy (pebble + VPS logs), Alertmanager → Telegram

**Components:**
- **Prometheus** (`:9090`) — Metrics collection, 30d retention. Exporters: node (systemd, system metrics), blackbox (TLS cert probing)
- **Grafana** (`:3000`) — Dashboards: `https://grafana.grab-lab.gg`. Datasources: Prometheus (default), Loki
- **Loki** (`:3100`) — Log aggregation, 30d retention, wt0 interface only (NetBird mesh). Ruler evaluates LogQL alerts
- **Alloy** — Journald shipper (replaced EOL Promtail). pebble → localhost, VPS → pebble over NetBird
- **Alertmanager** (`:9093`) — Routes alerts to Telegram (grouped by alertname, severity)

All services bind to loopback except Loki (`0.0.0.0`, firewalled to wt0).

**Setup details:** See [docs/roadmap/stage-06-monitoring.md](../roadmap/stage-06-monitoring.md)

---

## Accessing Dashboards

### Grafana

```
URL: https://grafana.grab-lab.gg
Login: admin / <from secrets/secrets.yaml: grafana/admin_password>
OIDC: "Sign in with Kanidm" (homelab_admins group = Admin, others = Viewer)
```

### Prometheus

```
URL: https://prometheus.grab-lab.gg
Pages: /targets (scrape health), /alerts (active alerts), /graph (query)
```

---

## Querying Logs in Loki (LogQL)

Via Grafana → Explore → Loki datasource.

**Example queries:**

```logql
# All logs from pebble
{host="pebble"}

# All logs from VPS
{host="vps"}

# SSH auth failures
{unit="sshd.service"} |= "Failed"

# Grafana service logs
{unit="grafana.service"}

# Errors across all services
{job="systemd-journal"} |~ "error|Error|ERROR"

# Count failed SSH by source IP (5m)
sum by (source_ip) (
  count_over_time(
    {unit="sshd.service"} |= "Failed"
    | regexp `from (?P<source_ip>\S+) port`
    [5m]
  )
)

# Sudo auth failures
{unit!="loki.service"} |= "pam_unix(sudo" |= "authentication failure"
```

**LogQL docs:** https://grafana.com/docs/loki/latest/query/

---

## Alert Routing (Telegram)

Prometheus and Loki → Alertmanager → Telegram bot.

**Setup credentials:**
```bash
just edit-secrets
# Add:
# alertmanager/telegram_env: |
#   TELEGRAM_BOT_TOKEN=<from @BotFather>
#   TELEGRAM_CHAT_ID=<from /getUpdates>
```

**Message format:**
```
🔥 FIRING — TLSCertExpiringSoon
Severity: warning
Summary: TLS cert expiring soon on https://grafana.grab-lab.gg
Details: Certificate expires in 29 days

✅ RESOLVED — TLSCertExpiringSoon
```

---

## Active Alerts

### Prometheus (homelab/prometheus/default.nix)

- **TLSCertExpiringSoon** (warning, 1h) — Cert expires < 30 days. Check Caddy ACME renewal.
- **TLSCertExpired** (critical, 5m) — Cert expired. Restart Caddy, check logs.
- **SystemdServiceFailed** (critical, 5m) — Unit in failed state. Check `journalctl -u <unit>`, restart, fix.

### Loki (homelab/loki/default.nix)

- **SSHBruteForce** (warning, 0m) — >10 failed SSH in 5m from same IP. Check fail2ban.
- **SSHRootLogin** (critical, 0m) — Successful root login. Investigate (should be disabled).
- **SudoAuthFailure** (warning, 0m) — Wrong sudo password. Investigate user/source.

---

## Adding a New Scrape Target

1. **Expose metrics** — Service must serve Prometheus metrics (e.g., `:2019/metrics`)
2. **Add scrape config:**
   ```nix
   # homelab/prometheus/default.nix
   services.prometheus.scrapeConfigs = [
     {
       job_name = "newservice";
       static_configs = [{ targets = [ "localhost:2019" ]; }];
     }
   ];
   ```
3. **Deploy and verify:**
   ```bash
   just deploy pebble
   # Check: https://prometheus.grab-lab.gg/targets
   ```

---

## Adding a New HTTPS Probe

Monitor TLS cert expiry for new endpoints.

1. **Add target:**
   ```nix
   # homelab/prometheus/default.nix
   httpsTargets = [
     # ... existing ...
     "https://newservice.grab-lab.gg"
   ];
   ```
2. **Deploy and verify:**
   ```bash
   just deploy pebble
   # Check: https://prometheus.grab-lab.gg/targets → job "tls_probe"
   # Query: probe_ssl_earliest_cert_expiry{instance="https://newservice.grab-lab.gg"}
   ```

---

## Troubleshooting

**Common debugging pattern:** `systemctl status <service>`, `journalctl -u <service> -f`

**Prometheus not scraping:** Check targets at `prometheus.grab-lab.gg/targets`. Test exporter endpoints: `curl localhost:9100/metrics` (node), `curl "localhost:9115/probe?target=https://grafana.grab-lab.gg&module=http_2xx"` (blackbox).

**Grafana datasource failing:** `journalctl -u grafana -f`. Test backends: `curl localhost:9090/api/v1/query?query=up` (Prometheus), `curl localhost:3100/ready` (Loki).

**Loki not receiving logs (pebble):** `systemctl status alloy loki`. Test API: `curl localhost:3100/ready`, `curl -G -s "localhost:3100/loki/api/v1/query" --data-urlencode 'query={job="systemd-journal"}' | jq`.

**VPS logs not reaching Loki:** On VPS: `systemctl status alloy`, `ping 100.102.154.38`, `curl http://100.102.154.38:3100/ready`. On pebble: `sudo iptables -L -n -v | grep 3100` (should show ACCEPT on wt0).

**Alertmanager not sending:** `systemctl show prometheus-alertmanager | grep Environment`. Test Telegram: `curl -X POST "https://api.telegram.org/bot<token>/sendMessage" -d "chat_id=<id>" -d "text=Test"`.

**Alerts not firing:** `curl localhost:9090/api/v1/rules | jq` (Prometheus), `curl localhost:3100/loki/api/v1/rules | jq` (Loki ruler).

---

## References

- Stage 6: Monitoring setup — [docs/roadmap/stage-06-monitoring.md](../roadmap/stage-06-monitoring.md)
- Stage 10: VPS log shipping, Alloy migration — [docs/roadmap/stage-10-hardening-backups.md](../roadmap/stage-10-hardening-backups.md)
- homelab/prometheus/default.nix — Prometheus config, alert rules, Telegram routing
- homelab/grafana/default.nix — Grafana OIDC config
- homelab/loki/default.nix — Loki config, LogQL alert rules
- Prometheus docs — https://prometheus.io/docs/prometheus/latest/querying/basics/
- LogQL docs — https://grafana.com/docs/loki/latest/query/
