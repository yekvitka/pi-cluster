#!/bin/bash
set -e

KUBECONFIG="/home/pimaster/.kube/config"
KUBECTL="kubectl --kubeconfig=$KUBECONFIG"
HELM="helm --kubeconfig=$KUBECONFIG"
CERT_MANAGER_VERSION="v1.14.3"

# Add Helm repositories
echo "Adding cert-manager repository..."
$HELM repo add jetstack https://charts.jetstack.io
$HELM repo update

# Create namespace for cert-manager
echo "Creating cert-manager namespace..."
$KUBECTL create namespace cert-manager --dry-run=client -o yaml | $KUBECTL apply -f -

# Install cert-manager
echo "Installing cert-manager $CERT_MANAGER_VERSION..."
$HELM upgrade --install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version $CERT_MANAGER_VERSION \
  --set installCRDs=true

# Wait for cert-manager to be ready
echo "Waiting for cert-manager to be ready..."
sleep 30
$KUBECTL -n cert-manager wait --for=condition=ready pod --selector=app.kubernetes.io/instance=cert-manager --timeout=120s

# Create self-signed certificate issuer
echo "Creating self-signed certificate issuer..."
cat <<EOF | $KUBECTL apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
EOF

echo "Cert-manager installation complete!"
