#!/bin/bash
# Creates the k3d dev cluster: k3s without flannel, kube-proxy, CoreDNS and
# the other add-ons, as in the real cluster. Its kubeconfig goes to
# dev/kubeconfig, never to the default one.

set -euo pipefail

WORK_DIR="$(dirname "$(readlink -f "$0")")"
K3D_DIR="$WORK_DIR/k3d-cluster"
KUBECONFIG_FILE="$WORK_DIR/kubeconfig"

# Pod and service networks, as in the real cluster
export CLUSTER_SUBNET="10.42.0.0/16"
export SERVICE_SUBNET="10.43.0.0/16"

# Docker network for the k3d nodes; the API listens on a loopback address
NETWORK_NAME="picluster"
NET_PREFIX="172.30"
export HOST_IP="127.$NET_PREFIX.1"

if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  echo "Using the existing network '$NETWORK_NAME'"
else
  echo "Creating the network '$NETWORK_NAME'"
  docker network create \
    --driver bridge \
    --subnet "$NET_PREFIX.0.0/16" \
    --gateway "$NET_PREFIX.0.1" \
    --ip-range "$NET_PREFIX.0.0/17" \
    "$NETWORK_NAME"
fi

# shellcheck disable=SC2016 # the variable names are for envsubst, not the shell
envsubst '${HOST_IP} ${CLUSTER_SUBNET} ${SERVICE_SUBNET}' \
  < "$K3D_DIR/k3d-cluster.yaml.tmpl" > "$K3D_DIR/k3d-cluster.yaml"

K3D_FIX_MOUNTS=1 K3D_FIX_DNS=0 k3d cluster create -c "$K3D_DIR/k3d-cluster.yaml"
k3d kubeconfig get "$NETWORK_NAME" > "$KUBECONFIG_FILE"
chmod 600 "$KUBECONFIG_FILE"

echo "Dev cluster created. Use it with: export KUBECONFIG=$KUBECONFIG_FILE"
