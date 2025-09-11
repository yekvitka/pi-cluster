#!/bin/bash
set -e

# Variables
KUBECONFIG="/home/pimaster/.kube/config"
KUBECTL="kubectl --kubeconfig=$KUBECONFIG"
HELM="helm --kubeconfig=$KUBECONFIG"
MONITORING_NAMESPACE="monitoring"
GRAFANA_HOSTNAME="grafana.yekvitka.local"
LOKI_HOSTNAME="loki.yekvitka.local"
TEMPO_HOSTNAME="tempo.yekvitka.local"
ADMIN_USER="admin"
ADMIN_PASSWORD="s1cret0"  # Using the password from vault.yml

echo "=== Installing Monitoring Stack (Prometheus, Grafana, Loki, Tempo) ==="

# Add Helm repositories
echo "Adding Helm repositories..."
$HELM repo add prometheus-community https://prometheus-community.github.io/helm-charts
$HELM repo add grafana https://grafana.github.io/helm-charts
$HELM repo update

# Create monitoring namespace
echo "Creating $MONITORING_NAMESPACE namespace..."
$KUBECTL create namespace $MONITORING_NAMESPACE --dry-run=client -o yaml | $KUBECTL apply -f -

# Install kube-prometheus-stack (includes Prometheus and Grafana)
echo "Installing kube-prometheus-stack..."
$HELM upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace $MONITORING_NAMESPACE \
  --set grafana.enabled=true \
  --set grafana.adminPassword=$ADMIN_PASSWORD \
  --set grafana.adminUser=$ADMIN_USER \
  --set grafana.ingress.enabled=true \
  --set grafana.ingress.hostname=$GRAFANA_HOSTNAME \
  --set grafana.ingress.ingressClassName=nginx \
  --set grafana.ingress.annotations."cert-manager\.io/cluster-issuer"=selfsigned-issuer \
  --set grafana.ingress.tls[0].hosts[0]=$GRAFANA_HOSTNAME \
  --set grafana.ingress.tls[0].secretName=grafana-tls

# Install Loki
echo "Installing Loki..."
$HELM upgrade --install loki grafana/loki-stack \
  --namespace $MONITORING_NAMESPACE \
  --set grafana.enabled=false \
  --set loki.persistence.enabled=true \
  --set loki.persistence.size=10Gi

# Create Loki Ingress
echo "Creating Loki Ingress..."
cat <<EOF | $KUBECTL apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: loki-ingress
  namespace: $MONITORING_NAMESPACE
  annotations:
    cert-manager.io/cluster-issuer: selfsigned-issuer
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - $LOKI_HOSTNAME
    secretName: loki-tls
  rules:
  - host: $LOKI_HOSTNAME
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: loki
            port:
              number: 3100
EOF

# Install Tempo
echo "Installing Tempo..."
$HELM upgrade --install tempo grafana/tempo \
  --namespace $MONITORING_NAMESPACE \
  --set tempo.persistence.enabled=true \
  --set tempo.persistence.size=10Gi

# Create Tempo Ingress
echo "Creating Tempo Ingress..."
cat <<EOF | $KUBECTL apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tempo-ingress
  namespace: $MONITORING_NAMESPACE
  annotations:
    cert-manager.io/cluster-issuer: selfsigned-issuer
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - $TEMPO_HOSTNAME
    secretName: tempo-tls
  rules:
  - host: $TEMPO_HOSTNAME
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: tempo
            port:
              number: 3100
EOF

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

echo "Waiting for deployments to be ready..."
sleep 30

echo "Monitoring stack installation complete!"
echo "Access Grafana at: https://$GRAFANA_HOSTNAME"
echo "Access Loki at: https://$LOKI_HOSTNAME"
echo "Access Tempo at: https://$TEMPO_HOSTNAME"
echo "Login credentials: $ADMIN_USER / $ADMIN_PASSWORD"
