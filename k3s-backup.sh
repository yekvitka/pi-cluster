#!/bin/bash
set -e

echo "=== K3s Cluster Backup Script ==="
echo "$(date): Starting backup process"

# Create backup directory
BACKUP_DIR="/tmp/k3s-backups-$(date +%Y%m%d-%H%M%S)"
mkdir -p $BACKUP_DIR
echo "Created backup directory: $BACKUP_DIR"

# Check if we're running on a master node with etcd
if [ -d "/var/lib/rancher/k3s/server/db/etcd" ]; then
  echo "Detected etcd database, backing up..."
  
  # Backup etcd database
  ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
    --cert=/var/lib/rancher/k3s/server/tls/etcd/server-client.crt \
    --key=/var/lib/rancher/k3s/server/tls/etcd/server-client.key \
    snapshot save $BACKUP_DIR/etcd-backup.db
  
  echo "etcd backup saved to $BACKUP_DIR/etcd-backup.db"
else
  echo "Not running on a master node with etcd, skipping etcd backup"
fi

# Copy k3s config
if [ -f "/etc/rancher/k3s/k3s.yaml" ]; then
  cp /etc/rancher/k3s/k3s.yaml $BACKUP_DIR/k3s.yaml
  echo "Copied k3s config to $BACKUP_DIR/k3s.yaml"
fi

# Backup k3s manifests
if [ -d "/var/lib/rancher/k3s/server/manifests" ]; then
  mkdir -p $BACKUP_DIR/manifests
  cp -r /var/lib/rancher/k3s/server/manifests/* $BACKUP_DIR/manifests/
  echo "Copied k3s manifests to $BACKUP_DIR/manifests/"
fi

# Get cluster resources using kubectl
if command -v kubectl &> /dev/null; then
  echo "Backing up Kubernetes resources..."
  
  # Namespace list
  kubectl get namespaces -o yaml > $BACKUP_DIR/namespaces.yaml
  
  # For each namespace, get resources
  for ns in $(kubectl get namespaces -o name | cut -d/ -f2); do
    mkdir -p $BACKUP_DIR/resources/$ns
    
    # Get deployments
    kubectl get deployments -n $ns -o yaml > $BACKUP_DIR/resources/$ns/deployments.yaml
    
    # Get services
    kubectl get services -n $ns -o yaml > $BACKUP_DIR/resources/$ns/services.yaml
    
    # Get configmaps
    kubectl get configmaps -n $ns -o yaml > $BACKUP_DIR/resources/$ns/configmaps.yaml
    
    # Get secrets
    kubectl get secrets -n $ns -o yaml > $BACKUP_DIR/resources/$ns/secrets.yaml
    
    # Get persistent volume claims
    kubectl get pvc -n $ns -o yaml > $BACKUP_DIR/resources/$ns/pvcs.yaml
    
    echo "Backed up resources for namespace: $ns"
  done
  
  # Get nodes
  kubectl get nodes -o yaml > $BACKUP_DIR/nodes.yaml
  
  # Get persistent volumes
  kubectl get pv -o yaml > $BACKUP_DIR/pvs.yaml
  
  echo "Kubernetes resources backup completed"
fi

# Create tar archive
BACKUP_ARCHIVE="/tmp/k3s-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
tar -czf $BACKUP_ARCHIVE -C $(dirname $BACKUP_DIR) $(basename $BACKUP_DIR)
echo "Created backup archive: $BACKUP_ARCHIVE"

# Configure MinIO client
echo "Configuring MinIO client..."
mc alias set minio https://192.168.50.201:9091 minioadmin minioadmin --insecure

# Create bucket if it doesn't exist
echo "Checking for k3s-backup bucket..."
mc ls minio --insecure | grep -q k3s-backup || mc mb minio/k3s-backup --insecure

# Upload to MinIO
echo "Uploading backup to MinIO..."
BACKUP_DATE=$(date +%Y-%m-%d)
mc cp $BACKUP_ARCHIVE minio/k3s-backup/$BACKUP_DATE/ --insecure

# Cleanup
echo "Cleaning up temporary files..."
rm -rf $BACKUP_DIR
rm $BACKUP_ARCHIVE

echo "=== Backup completed successfully ==="
echo "Backup stored in MinIO: k3s-backup/$BACKUP_DATE/$(basename $BACKUP_ARCHIVE)"
