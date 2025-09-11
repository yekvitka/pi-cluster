#!/bin/bash
set -e

# Variables
RANCHER_HOSTNAME="rancher.yekvitka.local"
RANCHER_NAMESPACE="cattle-system"
RANCHER_VERSION="2.11.3"
CERT_MANAGER_VERSION="v1.14.3"

echo "=== Installing Rancher on k3s cluster ==="

# Check kubectl access
echo "Verifying cluster access..."
kubectl get nodes

# Add Helm repositories
echo "Adding Helm repositories..."
helm repo add jetstack https://charts.jetstack.io
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm repo update

# Install cert-manager
echo "Creating cert-manager namespace..."
kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -

echo "Installing cert-manager $CERT_MANAGER_VERSION..."
helm upgrade --install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version $CERT_MANAGER_VERSION \
  --set installCRDs=true

echo "Waiting for cert-manager to be ready..."
sleep 30
kubectl -n cert-manager wait --for=condition=ready pod --selector=app.kubernetes.io/instance=cert-manager --timeout=120s

# Install Rancher
echo "Creating $RANCHER_NAMESPACE namespace..."
kubectl create namespace $RANCHER_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

echo "Installing Rancher $RANCHER_VERSION..."
helm upgrade --install rancher rancher-stable/rancher \
  --namespace $RANCHER_NAMESPACE \
  --version $RANCHER_VERSION \
  --set hostname=$RANCHER_HOSTNAME \
  --set bootstrapPassword=admin \
  --set replicas=1 \
  --set global.cattle.psp.enabled=false \
  --set ingress.tls.source=secret

echo "Waiting for Rancher to be ready (this may take a few minutes)..."
sleep 60

echo "=== Rancher installation complete ==="
echo "You can access Rancher at https://$RANCHER_HOSTNAME"
echo "The initial admin password is 'admin'"
