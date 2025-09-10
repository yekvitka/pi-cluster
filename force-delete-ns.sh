#!/bin/bash

NAMESPACE=longhorn-system
kubectl get namespace $NAMESPACE -o json | jq '.spec.finalizers = []' | kubectl replace --raw "/api/v1/namespaces/$NAMESPACE/finalize" -f -
