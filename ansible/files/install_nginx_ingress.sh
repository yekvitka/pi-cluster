#!/bin/bash
set -e

# Variables
KUBECONFIG="/home/pimaster/.kube/config"
KUBECTL="kubectl --kubeconfig=$KUBECONFIG"
HELM="helm --kubeconfig=$KUBECONFIG"

# Add Nginx Ingress repository
echo "Adding Nginx Ingress repository..."
$HELM repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
$HELM repo update

# Create namespace for Nginx Ingress
echo "Creating ingress-nginx namespace..."
$KUBECTL create namespace ingress-nginx --dry-run=client -o yaml | $KUBECTL apply -f -

# Install Nginx Ingress Controller
echo "Installing Nginx Ingress Controller..."
$HELM upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --set controller.replicaCount=2 \
  --set controller.nodeSelector."kubernetes\.io/os"=linux \
  --set defaultBackend.nodeSelector."kubernetes\.io/os"=linux \
  --set controller.admissionWebhooks.patch.nodeSelector."kubernetes\.io/os"=linux \
  --set controller.service.type=LoadBalancer

# Wait for Nginx Ingress to be ready
echo "Waiting for Nginx Ingress Controller to be ready..."
$KUBECTL -n ingress-nginx wait --for=condition=available --timeout=120s deployment/ingress-nginx-controller

echo "Nginx Ingress Controller has been installed successfully!"
