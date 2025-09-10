#!/bin/bash
# Script to restart all key services in the Pi cluster
# This ensures services start in the correct dependency order

set -e
echo "========= Pi Cluster Service Restart Script ========="
echo "This script will restart all essential services in the cluster"
echo "-------------------------------------------------------"

# Function to check if K3s is running
check_k3s() {
  echo "Checking K3s status..."
  if ansible k3s_cluster -m shell -a "systemctl is-active k3s" > /dev/null 2>&1; then
    echo "✅ K3s is running"
    return 0
  else
    echo "❌ K3s is not running on all nodes"
    return 1
  fi
}

# Function to wait for pods in a namespace to be ready
wait_for_namespace_ready() {
  local namespace=$1
  local timeout=${2:-300}  # Default timeout of 5 minutes
  local start_time=$(date +%s)
  local end_time=$((start_time + timeout))
  
  echo "Waiting for pods in namespace '$namespace' to be ready (timeout: ${timeout}s)..."
  
  while true; do
    current_time=$(date +%s)
    if [ $current_time -gt $end_time ]; then
      echo "❌ Timeout waiting for pods in namespace '$namespace'"
      return 1
    fi
    
    # Get the count of pods not in Running or Completed state
    not_ready=$(ansible node2 -m shell -a "kubectl get pods -n $namespace -o jsonpath='{.items[?(@.status.phase!=\"Running\" && @.status.phase!=\"Succeeded\")].metadata.name}' | wc -w" | grep -v CHANGED | grep -v ">>")
    
    if [ "$not_ready" -eq "0" ]; then
      echo "✅ All pods in namespace '$namespace' are ready"
      return 0
    fi
    
    echo "Waiting for pods in namespace '$namespace' ($not_ready pods not ready)..."
    sleep 10
  done
}

# Step 1: Restart K3s on all nodes
restart_k3s() {
  echo "Step 1: Restarting K3s on all nodes..."
  ansible-playbook k3s_stop.yml
  sleep 10
  ansible-playbook k3s_start.yml
  sleep 20
  
  # Check K3s status
  if ! check_k3s; then
    echo "❌ Failed to restart K3s. Please check the cluster manually."
    exit 1
  fi
}

# Step 2: Restart core services
restart_core_services() {
  echo "Step 2: Restarting core services..."
  # Wait for kube-system to be ready
  wait_for_namespace_ready "kube-system" 300
  
  # Restart Vault if running
  if ansible node1 -m shell -a "systemctl is-active vault" > /dev/null 2>&1; then
    echo "Restarting Vault service..."
    ansible node1 -m systemd -a "name=vault state=restarted"
  fi
  
  # Restart HAProxy if running
  if ansible node1 -m shell -a "systemctl is-active haproxy" > /dev/null 2>&1; then
    echo "Restarting HAProxy service..."
    ansible node1 -m systemd -a "name=haproxy state=restarted"
  fi
  
  # Restart MinIO if running
  if ansible node1 -m shell -a "systemctl is-active minio" > /dev/null 2>&1; then
    echo "Restarting MinIO service..."
    ansible node1 -m systemd -a "name=minio state=restarted"
  fi
}

# Step 3: Restart Kubernetes components in order
restart_kubernetes_components() {
  echo "Step 3: Restarting Kubernetes components in order..."
  
  # Restart cert-manager pods
  if ansible node2 -m shell -a "kubectl get namespace cert-manager -o name" > /dev/null 2>&1; then
    echo "Restarting cert-manager..."
    ansible node2 -m shell -a "kubectl -n cert-manager rollout restart deployment"
    wait_for_namespace_ready "cert-manager" 180
  fi
  
  # Restart Longhorn components
  if ansible node2 -m shell -a "kubectl get namespace longhorn-system -o name" > /dev/null 2>&1; then
    echo "Restarting Longhorn components..."
    ansible node2 -m shell -a "kubectl -n longhorn-system rollout restart deployment"
    wait_for_namespace_ready "longhorn-system" 300
  fi
  
  # Restart monitoring stack
  if ansible node2 -m shell -a "kubectl get namespace monitoring -o name" > /dev/null 2>&1; then
    echo "Restarting monitoring stack..."
    ansible node2 -m shell -a "kubectl -n monitoring rollout restart deployment"
    wait_for_namespace_ready "monitoring" 300
  fi
  
  # Restart observability components
  if ansible node2 -m shell -a "kubectl get namespace observability -o name" > /dev/null 2>&1; then
    echo "Restarting observability components..."
    ansible node2 -m shell -a "kubectl -n observability rollout restart deployment statefulset"
    wait_for_namespace_ready "observability" 300
  fi
  
  # Restart FluxCD
  if ansible node2 -m shell -a "kubectl get namespace flux-system -o name" > /dev/null 2>&1; then
    echo "Restarting FluxCD..."
    ansible node2 -m shell -a "kubectl -n flux-system rollout restart deployment"
    wait_for_namespace_ready "flux-system" 180
  fi
  
  # Restart Rancher components
  if ansible node2 -m shell -a "kubectl get namespace cattle-system -o name" > /dev/null 2>&1; then
    echo "Restarting Rancher components..."
    ansible node2 -m shell -a "kubectl -n cattle-system rollout restart deployment"
    wait_for_namespace_ready "cattle-system" 300
  fi
}

# Run all steps
echo "Starting cluster restart sequence at $(date)"
restart_k3s
restart_core_services
restart_kubernetes_components

echo "========= All services restarted successfully ========="
echo "Cluster is now fully operational at $(date)"
echo "You can access the following services:"
echo "- Rancher: https://rancher.picluster.local"
echo "- Grafana: https://grafana.picluster.local"
echo "- Longhorn: https://longhorn.picluster.local"
echo "-------------------------------------------------------"
