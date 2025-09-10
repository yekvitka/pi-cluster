#!/bin/bash
# Script to clean up Kubernetes cluster
# Removes non-essential services to free up resources

set -e
echo "==============================================="
echo "      PI CLUSTER CLEANUP SCRIPT"
echo "==============================================="
echo "This script will:
1. Remove non-essential services
2. Clean up unused resources
3. Prepare the system for fresh deployment"
echo "==============================================="

# Confirm before proceeding
read -p "This will remove non-essential services from your cluster. Continue? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Operation cancelled."
  exit 0
fi

# Set path to ansible directory
ANSIBLE_DIR="/home/pimaster/pi-cluster/ansible"
cd $ANSIBLE_DIR

# Function to run kubectl commands via ansible on node2
run_kubectl() {
  ansible node2 -m shell -a "kubectl $*"
}

# Function to delete a namespace safely
delete_namespace() {
  local namespace=$1
  if run_kubectl get namespace $namespace &>/dev/null; then
    echo "Deleting namespace $namespace..."
    run_kubectl delete --all deployments --namespace=$namespace
    run_kubectl delete --all statefulsets --namespace=$namespace
    run_kubectl delete --all daemonsets --namespace=$namespace
    run_kubectl delete --all jobs --namespace=$namespace
    run_kubectl delete --all cronjobs --namespace=$namespace
    run_kubectl delete --all pods --namespace=$namespace
    run_kubectl delete namespace $namespace
  else
    echo "Namespace $namespace doesn't exist, skipping..."
  fi
}

# Function to check if a namespace is a system namespace
is_system_namespace() {
  local namespace=$1
  local system_namespaces=(
    "kube-system" 
    "kube-public" 
    "kube-node-lease" 
    "default" 
    "cattle-system" 
    "cert-manager" 
    "cattle-fleet-system"
    "cattle-fleet-local-system"
    "fleet-default"
    "fleet-local"
    "cattle-global-data"
    "cattle-global-nt"
    "cattle-impersonation-system"
    "cattle-provisioning-capi-system"
    "cattle-ui-plugin-system"
    "local"
    "p-d2v7p"
    "p-wt845"
    "user-kskpq"
    "cluster-fleet-local-local-1a3d67d0a899"
  )
  for sys_ns in "${system_namespaces[@]}"; do
    if [[ "$namespace" == "$sys_ns" ]]; then
      return 0
    fi
  done
  return 1
}

# Function to clean up Docker images
clean_docker_images() {
  echo "Cleaning up Docker images on all nodes..."
  ansible k3s_cluster -m shell -a "docker system prune -af" || true
}

# Function to clean up etcd on node2 (assuming it's a control node)
clean_etcd() {
  echo "Running etcd cleanup on control node..."
  ansible node2 -m shell -a "
    ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
    --cert=/var/lib/rancher/k3s/server/tls/etcd/server-client.crt \
    --key=/var/lib/rancher/k3s/server/tls/etcd/server-client.key \
    compact \$(ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
    --cert=/var/lib/rancher/k3s/server/tls/etcd/server-client.crt \
    --key=/var/lib/rancher/k3s/server/tls/etcd/server-client.key \
    endpoint status -w json | grep -o '\"revision\":[0-9]*' | grep -o '[0-9]*')
    
    ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
    --cert=/var/lib/rancher/k3s/server/tls/etcd/server-client.crt \
    --key=/var/lib/rancher/k3s/server/tls/etcd/server-client.key defrag
  " || true
}

# List all namespaces
echo "Getting list of all namespaces..."
namespaces=$(ansible node2 -m shell -a "kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'" | grep -v "CHANGED" | grep -v ">>")

# Cleanup specific non-system namespaces that we plan to redeploy
echo "Starting cleanup of specific non-essential namespaces..."

# List of namespaces we explicitly want to clean
namespaces_to_clean=("longhorn-system" "monitoring" "observability" "flux-system" "velero")

for namespace in "${namespaces_to_clean[@]}"; do
  # Check if this namespace exists
  if kubectl get namespace $namespace &>/dev/null; then
    echo "Cleaning up namespace: $namespace"
    delete_namespace "$namespace"
  else
    echo "Namespace $namespace doesn't exist, skipping..."
  fi
done

# Clean up persistent volumes that are released
echo "Cleaning up released persistent volumes..."
ansible node2 -m shell -a "kubectl get pv | grep Released | awk '{print \$1}'" | grep -v "CHANGED" | grep -v ">>" | \
while read pv; do
  if [ ! -z "$pv" ]; then
    echo "Deleting PV: $pv"
    ansible node2 -m shell -a "kubectl delete pv $pv" || true
  fi
done

# Clean up failed/evicted pods in all namespaces
echo "Cleaning up failed/evicted pods..."
ansible node2 -m shell -a "kubectl get pods --all-namespaces | grep -E 'Evicted|Failed'" | grep -v "CHANGED" | grep -v ">>" | \
while read line; do
  if [ ! -z "$line" ]; then
    ns=$(echo $line | awk '{print $1}')
    pod=$(echo $line | awk '{print $2}')
    echo "Deleting $pod in namespace $ns"
    ansible node2 -m shell -a "kubectl delete pod -n $ns $pod" || true
  fi
done

# Run garbage collection in Kubernetes
echo "Running garbage collection..."
ansible k3s_cluster -m shell -a "systemctl restart k3s || systemctl restart k3s-agent" || true

# Restart K3s on all nodes
echo "Restarting K3s on all nodes..."
ansible-playbook -i /home/pimaster/pi-cluster/ansible/inventory.yml /home/pimaster/pi-cluster/ansible/k3s_stop.yml
sleep 10
ansible-playbook -i /home/pimaster/pi-cluster/ansible/inventory.yml /home/pimaster/pi-cluster/ansible/k3s_start.yml

# Wait for K3s to be up
echo "Waiting for K3s to start..."
sleep 30

echo "==============================================="
echo "Cleanup completed successfully!"
echo "You can now redeploy your services in a controlled manner."
echo "==============================================="
