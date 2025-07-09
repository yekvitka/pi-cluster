#!/bin/bash
set -e

# Variables
RANCHER_HOSTNAME="rancher.picluster.local"
RANCHER_NAMESPACE="cattle-system"
RANCHER_VERSION="2.11.3"
CERT_MANAGER_VERSION="v1.14.3"
KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
KUBECTL="kubectl --kubeconfig=$KUBECONFIG"
HELM="helm --kubeconfig=$KUBECONFIG"

echo "=== Installing Rancher on k3s cluster ==="
echo "Using Kubernetes config: $KUBECONFIG"

# Check kubectl access
echo "Verifying cluster access..."
$KUBECTL get nodes

# Add Helm repositories
echo "Adding Helm repositories..."
$HELM repo add jetstack https://charts.jetstack.io
$HELM repo add rancher-stable https://releases.rancher.com/server-charts/stable
$HELM repo update

# Install cert-manager
echo "Creating cert-manager namespace..."
$KUBECTL create namespace cert-manager --dry-run=client -o yaml | $KUBECTL apply -f -

echo "Installing cert-manager $CERT_MANAGER_VERSION..."
$HELM upgrade --install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version $CERT_MANAGER_VERSION \
  --set installCRDs=true

echo "Waiting for cert-manager to be ready..."
sleep 30
$KUBECTL -n cert-manager wait --for=condition=ready pod --selector=app.kubernetes.io/instance=cert-manager --timeout=120s

# Install Rancher
echo "Creating $RANCHER_NAMESPACE namespace..."
$KUBECTL create namespace $RANCHER_NAMESPACE --dry-run=client -o yaml | $KUBECTL apply -f -

echo "Installing Rancher $RANCHER_VERSION..."
$HELM upgrade --install rancher rancher-stable/rancher \
  --namespace $RANCHER_NAMESPACE \
  --version $RANCHER_VERSION \
  --set hostname=$RANCHER_HOSTNAME \
  --set bootstrapPassword=admin \
  --set replicas=1 \
  --set global.cattle.psp.enabled=false

echo "Waiting for Rancher to be ready (this may take a few minutes)..."
sleep 30
$KUBECTL -n $RANCHER_NAMESPACE wait --for=condition=ready pod --selector=app=rancher --timeout=300s

echo "=== Rancher installation complete ==="
echo "You can access Rancher at https://$RANCHER_HOSTNAME"
echo "The initial admin password is 'admin'"
