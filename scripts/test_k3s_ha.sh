#!/bin/bash
# K3s HA Cluster Reset and Installation Test Script

echo "Step 1: Uninstalling existing K3s setup..."
ansible-playbook -i ansible/inventory.yml ansible/k3s_reset.yml

echo "Step 2: Installing K3s in HA mode..."
ansible-playbook -i ansible/inventory.yml ansible/k3s_install.yml

echo "Step 3: Verifying the cluster..."
ansible-playbook -i ansible/inventory.yml ansible/verify_cluster.yml

echo "Step 4: Checking both master nodes..."
# Replace node1 and node2 with your actual master node names
ssh node1 "systemctl status k3s"
ssh node2 "systemctl status k3s"

echo "Step 5: Checking K3s configuration on masters..."
ssh node1 "cat /etc/rancher/k3s/k3s.yaml | grep server"
ssh node2 "cat /etc/rancher/k3s/k3s.yaml | grep server"

echo "Step 6: Running kubectl to verify nodes..."
kubectl get nodes -o wide

echo "Testing completed!"
