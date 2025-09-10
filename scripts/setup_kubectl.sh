#!/bin/bash

# Create .kube directory if it doesn't exist
mkdir -p ~/.kube

# Get the kubeconfig from a master node
scp node2:/etc/rancher/k3s/k3s.yaml ~/.kube/config

# Replace the localhost IP with the actual cluster IP
sed -i 's/127.0.0.1/10.0.0.12/g' ~/.kube/config

# Set correct permissions
chmod 600 ~/.kube/config

# Test the connection
kubectl get nodes

echo "Kubectl setup completed!"
