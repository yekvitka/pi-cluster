#!/bin/bash
# Script to redeploy services in a controlled manner
# This ensures proper dependency order and resource allocation

set -e
echo "==============================================="
echo "      PI CLUSTER SERVICE DEPLOYMENT"
echo "==============================================="
echo "This script will deploy:
1. Core system services
2. Storage (Longhorn)
3. Monitoring stack
4. Observability stack (Loki, Tempo)
5. GitOps components (FluxCD)"
echo "==============================================="

# Confirm before proceeding
read -p "Ready to deploy services? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Operation cancelled."
  exit 0
fi

# Function for kubectl commands
run_kubectl() {
  ansible node2 -m shell -a "kubectl $*"
}

# Function to wait for pods to be ready in a namespace
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
    
    # Check if all pods are ready using ansible
    local not_ready=$(ansible node2 -m shell -a "kubectl get pods -n $namespace -o jsonpath='{.items[?(@.status.phase!=\"Running\" && @.status.phase!=\"Succeeded\")].metadata.name}' | wc -w" | grep -v CHANGED | grep -v ">>")
    
    if [ "$not_ready" -eq "0" ]; then
      echo "✅ All pods in namespace '$namespace' are ready"
      return 0
    fi
    
    echo "Waiting for pods in namespace '$namespace' ($not_ready pods not ready)..."
    sleep 10
  done
}

# Apply resource quotas first to ensure controlled resource usage
echo "Applying resource quotas..."
run_kubectl apply -f /tmp/resource-quotas.yaml

# Step 1: Deploy Longhorn Storage
echo "Step 1: Deploying Longhorn Storage..."
run_kubectl create namespace longhorn-system || true
ansible node2 -m shell -a "helm repo add longhorn https://charts.longhorn.io" || true
ansible node2 -m shell -a "helm repo update"
ansible node2 -m shell -a "helm install longhorn longhorn/longhorn --namespace longhorn-system" || true

# Wait for Longhorn to be ready
wait_for_namespace_ready "longhorn-system" 600

# Step 2: Deploy monitoring stack
echo "Step 2: Deploying Monitoring Stack..."
run_kubectl create namespace monitoring || true
ansible node2 -m shell -a "helm repo add prometheus-community https://prometheus-community.github.io/helm-charts" || true
ansible node2 -m shell -a "helm repo update"
ansible node2 -m shell -a "helm install kube-prom-stack prometheus-community/kube-prometheus-stack --namespace monitoring" || true

# Wait for monitoring to be ready
wait_for_namespace_ready "monitoring" 300

# Step 3: Deploy Loki and Tempo for observability
echo "Step 3: Deploying Observability Stack..."
run_kubectl create namespace observability || true
ansible node2 -m shell -a "helm repo add grafana https://grafana.github.io/helm-charts" || true
ansible node2 -m shell -a "helm repo update"
ansible node2 -m shell -a "helm install loki grafana/loki-stack --namespace observability" || true
ansible node2 -m shell -a "helm install tempo grafana/tempo --namespace observability" || true

# Wait for observability to be ready
wait_for_namespace_ready "observability" 300

# Step 4: Deploy FluxCD for GitOps
echo "Step 4: Deploying FluxCD for GitOps..."
run_kubectl create namespace flux-system || true
ansible node2 -m shell -a "helm repo add fluxcd https://charts.fluxcd.io" || true
ansible node2 -m shell -a "helm repo update"
ansible node2 -m shell -a "helm install flux fluxcd/flux --namespace flux-system \
  --set git.url=git@github.com:yekvitka/pi-cluster.git \
  --set git.branch=master \
  --set git.path=kubernetes \
  --set git.user=\"yekvitka\" \
  --set git.email=\"kvitka.jr@gmail.com\"" || true

# Wait for FluxCD to be ready
wait_for_namespace_ready "flux-system" 300

# Step 5: Apply resource optimizations using ansible
echo "Step 5: Applying resource optimizations..."
bash /home/pimaster/pi-cluster/scripts/optimize_resources.sh

# Final verification
echo "==============================================="
echo "Verifying cluster status..."
ansible node2 -m shell -a "kubectl get nodes"
echo "-----------------------------------------------"
echo "Checking pod status across namespaces:"
for ns in kube-system longhorn-system monitoring observability flux-system; do
  echo "[$ns]:"
  ansible node2 -m shell -a "kubectl get pods -n $ns"
  echo "-----------------------------------------------"
done

echo "==============================================="
echo "Deployment completed successfully!"
echo "You may need to configure the FluxCD SSH key for GitHub."
echo "Get the key with:"
echo "kubectl -n flux-system logs deployment/flux | grep identity.pub"
echo "==============================================="
