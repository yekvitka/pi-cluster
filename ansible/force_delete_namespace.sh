#!/bin/bash

# Define namespace
NAMESPACE=longhorn-system

# Getting all resources with finalizers in the namespace
kubectl get engineimages.longhorn.io -n $NAMESPACE -o json | jq '.items[] | .metadata.name' | xargs -I{} kubectl patch engineimages.longhorn.io {} -n $NAMESPACE --type=json -p='[{"op": "remove", "path": "/metadata/finalizers"}]' --dry-run=false || true
kubectl get nodes.longhorn.io -n $NAMESPACE -o json | jq '.items[] | .metadata.name' | xargs -I{} kubectl patch nodes.longhorn.io {} -n $NAMESPACE --type=json -p='[{"op": "remove", "path": "/metadata/finalizers"}]' --dry-run=false || true

# Force delete the namespace
kubectl get namespace $NAMESPACE -o json > temp.json
cat temp.json | jq '.spec.finalizers = []' > modified.json
kubectl replace --raw "/api/v1/namespaces/$NAMESPACE/finalize" -f modified.json

# Clean up
rm temp.json modified.json
