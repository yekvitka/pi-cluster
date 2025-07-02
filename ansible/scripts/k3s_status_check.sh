#!/bin/bash
# K3s Status Check Script
# This script helps diagnose issues during K3s installation

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Check if user is root or sudo
if [[ $EUID -ne 0 ]]; then
   echo -e "${YELLOW}This script should be run as root or with sudo for full functionality${NC}"
fi

echo -e "${GREEN}===== K3s Installation Status Check =====${NC}"
echo

echo -e "${GREEN}Checking K3s Service Status:${NC}"
systemctl status k3s.service | grep -E "Active:|●"
systemctl status k3s-agent.service | grep -E "Active:|●" || echo -e "${YELLOW}No k3s-agent service found (normal on master nodes)${NC}"
echo

echo -e "${GREEN}Checking K3s Logs (last 10 lines):${NC}"
journalctl -u k3s.service --no-pager -n 10
echo

echo -e "${GREEN}Checking Listening Ports:${NC}"
netstat -tuln | grep -E '6443|10250'
echo

echo -e "${GREEN}Checking Network Configuration:${NC}"
ip a | grep -E 'inet '
echo

echo -e "${GREEN}Checking etcd Status (on master nodes):${NC}"
K3S_ETCD_HTTP_ENDPOINT="127.0.0.1:2381"
ETCDCTL="k3s etcd-snapshot"

# Try to execute etcdctl commands if available
if command -v $ETCDCTL &> /dev/null; then
    $ETCDCTL list-etcd-endpoints
    echo
    $ETCDCTL etcd-health
else
    echo -e "${YELLOW}etcdctl command not found. This is expected on worker nodes.${NC}"
fi
echo

echo -e "${GREEN}Checking Node Status:${NC}"
k3s kubectl get nodes || echo -e "${RED}Cannot get node status. K3s may not be fully initialized yet.${NC}"
echo

echo -e "${GREEN}Checking Pod Status:${NC}"
k3s kubectl get pods -A || echo -e "${RED}Cannot get pod status. K3s may not be fully initialized yet.${NC}"
echo

echo -e "${GREEN}===== Filesystem Status =====${NC}"
df -h | grep -E '/$|/var/lib/rancher'
echo

echo -e "${GREEN}===== Memory Usage =====${NC}"
free -m
echo

echo -e "${GREEN}===== CPU Load =====${NC}"
uptime
echo

echo -e "${GREEN}Check complete!${NC}"
