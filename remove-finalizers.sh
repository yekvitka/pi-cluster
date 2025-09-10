#!/bin/bash

# Patch the engineimage to remove the finalizer
kubectl patch engineimages.longhorn.io ei-b4bcf0a5 -n longhorn-system --type=json -p '[{"op": "remove", "path": "/metadata/finalizers"}]'

# Now try to force delete the namespace again
kubectl get namespace longhorn-system -o json | jq '.spec.finalizers = []' | kubectl replace --raw "/api/v1/namespaces/longhorn-system/finalize" -f -
