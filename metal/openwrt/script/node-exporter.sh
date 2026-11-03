#!/bin/sh
# Prometheus node exporter on the gateway, scraped by kube-prometheus-stack
# (externalnodes-monitoring, gateway.<domain>:9100). It listens on the LAN
# interface only: the cluster reaches it, the home network (wan) does not.
#
# Run on the gateway as root. Safe to re-run, no reboot:
#   ssh root@10.0.0.1 'sh -s' < metal/openwrt/script/node-exporter.sh
set -e

PORT=9100
# Base metrics plus board info, the Wi-Fi uplink, network stats, SoC temperature
# and filesystems
PACKAGES="prometheus-node-exporter-lua prometheus-node-exporter-lua-openwrt
  prometheus-node-exporter-lua-wifi prometheus-node-exporter-lua-netstat
  prometheus-node-exporter-lua-thermal prometheus-node-exporter-lua-filesystem"

MISSING=""
for p in $PACKAGES; do
  apk info -e "$p" >/dev/null 2>&1 || MISSING="$MISSING $p"
done
[ -z "$MISSING" ] || { apk update && apk add $MISSING; }

uci set prometheus-node-exporter-lua.main.listen_interface='lan'
uci set prometheus-node-exporter-lua.main.listen_port="$PORT"
uci commit prometheus-node-exporter-lua

/etc/init.d/prometheus-node-exporter-lua enable
/etc/init.d/prometheus-node-exporter-lua restart
echo "node exporter: http://10.0.0.1:$PORT/metrics"
