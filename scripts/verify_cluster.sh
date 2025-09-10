#!/bin/bash
# Script to verify that all services are running correctly
# This performs health checks on all components

set -e
echo "==============================================="
echo "      PI CLUSTER VERIFICATION SCRIPT"
echo "==============================================="

# Function for kubectl commands
run_kubectl() {
  ansible node2 -m shell -a "kubectl $*"
}

# Check K3s status
echo "Checking K3s status..."
run_kubectl get nodes -o wide
echo "-----------------------------------------------"

# Check the status of key system components
echo "Checking key system components..."
run_kubectl get pods -n kube-system | grep -E "coredns|metrics-server|traefik"
echo "-----------------------------------------------"

# Check Longhorn status
echo "Checking Longhorn status..."
run_kubectl get pods -n longhorn-system
echo "Longhorn volume status:"
run_kubectl get volumes -n longhorn-system 2>/dev/null || echo "No Longhorn volumes found"
echo "-----------------------------------------------"

# Check monitoring stack
echo "Checking monitoring stack..."
run_kubectl get pods -n monitoring
echo "-----------------------------------------------"

# Check Prometheus and Grafana status
echo "Checking Prometheus and Grafana..."
run_kubectl get svc -n monitoring | grep -E "prometheus|grafana"
echo "-----------------------------------------------"

# Check observability stack
echo "Checking observability stack..."
run_kubectl get pods -n observability
echo "-----------------------------------------------"

# Check FluxCD status
echo "Checking FluxCD status..."
run_kubectl get pods -n flux-system
echo "-----------------------------------------------"

# Check Velero backup status
echo "Checking Velero backup status..."
if ansible node2 -m shell -a "kubectl get namespace velero" &> /dev/null; then
    run_kubectl get pods -n velero
    echo "Recent backups:"
    run_kubectl get backups -n velero 2>/dev/null || echo "No backups found"
else
    echo "Velero namespace not found"
fi
echo "-----------------------------------------------"

# Check resource usage
echo "Checking cluster resource usage..."
echo "Node resource usage:"
run_kubectl top nodes 2>/dev/null || echo "Metrics not available yet"
echo "-----------------------------------------------"

# Check persistent volumes
echo "Checking persistent volumes..."
run_kubectl get pv
echo "-----------------------------------------------"

# Final summary
echo "==============================================="
echo "PI CLUSTER VERIFICATION COMPLETE"
echo "==============================================="
echo "Check the output above for any errors or issues."
echo "If all components are running, your cluster is healthy!"
