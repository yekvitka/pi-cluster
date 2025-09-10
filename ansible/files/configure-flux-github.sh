#!/bin/bash
# Script to configure FluxCD with GitHub repository

# Variables
GITHUB_USER="yekvitka"
GITHUB_EMAIL="kvitka.jr@gmail.com"
GITHUB_REPO="pi-cluster"
NAMESPACE="flux-system"

# Generate SSH key for Flux
ssh-keygen -t ed25519 -N '' -f /tmp/flux-key -C "flux@picluster"

# Extract the public key
FLUX_PUBLIC_KEY=$(cat /tmp/flux-key.pub)

echo "Please add this SSH key to your GitHub repository deploy keys:"
echo "===================================================================="
echo "$FLUX_PUBLIC_KEY"
echo "===================================================================="
echo "After adding the key to GitHub, press Enter to continue..."
read -p "Press Enter to continue"

# Create Kubernetes secret with the private key
kubectl -n $NAMESPACE create secret generic flux-ssh --from-file=identity=/tmp/flux-key

# Deploy Flux with GitHub configuration
kubectl -n $NAMESPACE create configmap flux-git-config \
  --from-literal=GIT_AUTHOR_NAME=$GITHUB_USER \
  --from-literal=GIT_AUTHOR_EMAIL=$GITHUB_EMAIL \
  --from-literal=GIT_URL=git@github.com:$GITHUB_USER/$GITHUB_REPO.git

# Patch the Flux deployment to use the SSH key and Git configuration
kubectl -n $NAMESPACE patch deployment flux --patch "
spec:
  template:
    spec:
      volumes:
      - name: ssh-key
        secret:
          secretName: flux-ssh
      - name: git-config
        configMap:
          name: flux-git-config
      containers:
      - name: flux
        volumeMounts:
        - name: ssh-key
          mountPath: /etc/fluxd/ssh
          readOnly: true
        - name: git-config
          mountPath: /etc/fluxd/git
          readOnly: true
        env:
        - name: GIT_AUTHOR_NAME
          valueFrom:
            configMapKeyRef:
              name: flux-git-config
              key: GIT_AUTHOR_NAME
        - name: GIT_AUTHOR_EMAIL
          valueFrom:
            configMapKeyRef:
              name: flux-git-config
              key: GIT_AUTHOR_EMAIL
        - name: GIT_URL
          valueFrom:
            configMapKeyRef:
              name: flux-git-config
              key: GIT_URL
        args:
        - --git-url=\$(GIT_URL)
        - --git-branch=master
        - --git-path=kubernetes
        - --git-user=\$(GIT_AUTHOR_NAME)
        - --git-email=\$(GIT_AUTHOR_EMAIL)
        - --sync-garbage-collection
        - --ssh-keygen-dir=/etc/fluxd/ssh
"

# Cleanup the temporary key files
rm /tmp/flux-key /tmp/flux-key.pub

echo "FluxCD has been configured to use your GitHub repository"
echo "Please ensure your repository has a 'kubernetes' directory for Flux to sync"
