# Certificates

All Let's Encrypt certificates renew on their own (IONOS DNS-01, no open port):

| Certificate | Used by | Renewed by |
|---|---|---|
| `*.homelab.yekvitka.net` (`pi-cluster-tls`) | Grafana, Longhorn, Prometheus, Alertmanager (Envoy gateway) | cert-manager in the cluster |
| `vault.homelab.yekvitka.net` | Vault (node1) | certbot on node1, `systemctl reload vault` |
| `object-store.homelab.yekvitka.net` | RustFS S3 and console (node1) | certbot on node1, RustFS restart |
| `gateway.homelab.yekvitka.net` | OpenWrt LuCI | certbot on node1, pushed to the gateway |

`make configure-cert-renewal` (`ansible/cert_renewal.yml`) installs certbot (pinned, venv `/opt/certbot`) on node1 with the IONOS credentials, a daily `certbot-renew.timer` at 14:30 (outside the backup windows: a RustFS restart must not break a backup) and the deploy hook `/etc/letsencrypt/renewal-hooks/deploy/homelab-certs.sh`. certbot renews 30 days before expiry; the hook only reloads or restarts when the files changed.

The LuCI certificate goes to the gateway with a node1 SSH key that dropbear restricts to `/etc/luci-cert/install.sh` (forced command, `metal/openwrt/script/luci-cert-receiver.sh`), so the IONOS key is not on the gateway.

Gatus on the [offsite VM](offsite.md) checks every certificate from outside and fails below 7 days left.

The certbot steps of `deploy_vault.yml`, `deploy_rustfs.yml` and `make openwrt-certbot-tls` (certificates on the control host) are only needed for a first install.

Test the renewal path without changing anything (Let's Encrypt staging): `/opt/certbot/bin/certbot renew --dry-run` on node1.
