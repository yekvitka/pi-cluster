#!/bin/bash

# Script to verify the status of all services in the cluster
# Author: GitHub Copilot

# Set color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Pi-Cluster Services Status Check ===${NC}"
echo

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed or not in PATH${NC}"
    echo "This script needs to be run on a machine with kubectl configured for the cluster"
    exit 1
fi

# Function to check service status
check_service() {
    local namespace=$1
    local service=$2
    local type=$3
    local name=$4

    echo -e "${YELLOW}Checking $name ($namespace)...${NC}"
    
    if [ "$type" = "deployment" ]; then
        STATUS=$(kubectl -n $namespace get deployment $service -o jsonpath='{.status.availableReplicas}' 2>/dev/null)
        DESIRED=$(kubectl -n $namespace get deployment $service -o jsonpath='{.status.replicas}' 2>/dev/null)
        
        if [ "$STATUS" = "" ]; then
            echo -e "  ${RED}Not found${NC}"
            return 1
        elif [ "$STATUS" = "$DESIRED" ] && [ "$STATUS" != "0" ]; then
            echo -e "  ${GREEN}Running ($STATUS/$DESIRED replicas)${NC}"
            return 0
        else
            echo -e "  ${RED}Partial ($STATUS/$DESIRED replicas)${NC}"
            return 2
        fi
    elif [ "$type" = "statefulset" ]; then
        STATUS=$(kubectl -n $namespace get statefulset $service -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
        DESIRED=$(kubectl -n $namespace get statefulset $service -o jsonpath='{.status.replicas}' 2>/dev/null)
        
        if [ "$STATUS" = "" ]; then
            echo -e "  ${RED}Not found${NC}"
            return 1
        elif [ "$STATUS" = "$DESIRED" ] && [ "$STATUS" != "0" ]; then
            echo -e "  ${GREEN}Running ($STATUS/$DESIRED replicas)${NC}"
            return 0
        else
            echo -e "  ${RED}Partial ($STATUS/$DESIRED replicas)${NC}"
            return 2
        fi
    elif [ "$type" = "daemonset" ]; then
        READY=$(kubectl -n $namespace get daemonset $service -o jsonpath='{.status.numberReady}' 2>/dev/null)
        DESIRED=$(kubectl -n $namespace get daemonset $service -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null)
        
        if [ "$READY" = "" ]; then
            echo -e "  ${RED}Not found${NC}"
            return 1
        elif [ "$READY" = "$DESIRED" ] && [ "$READY" != "0" ]; then
            echo -e "  ${GREEN}Running ($READY/$DESIRED nodes)${NC}"
            return 0
        else
            echo -e "  ${RED}Partial ($READY/$DESIRED nodes)${NC}"
            return 2
        fi
    elif [ "$type" = "pod" ]; then
        STATUS=$(kubectl -n $namespace get pods --selector=app=$service -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
        
        if [ "$STATUS" = "" ]; then
            echo -e "  ${RED}Not found${NC}"
            return 1
        elif [ "$STATUS" = "Running" ]; then
            echo -e "  ${GREEN}Running${NC}"
            return 0
        else
            echo -e "  ${RED}Status: $STATUS${NC}"
            return 2
        fi
    elif [ "$type" = "namespace" ]; then
        STATUS=$(kubectl get namespace $namespace -o jsonpath='{.status.phase}' 2>/dev/null)
        
        if [ "$STATUS" = "" ]; then
            echo -e "  ${RED}Namespace not found${NC}"
            return 1
        elif [ "$STATUS" = "Active" ]; then
            echo -e "  ${GREEN}Namespace Active${NC}"
            return 0
        else
            echo -e "  ${RED}Namespace Status: $STATUS${NC}"
            return 2
        fi
    fi
}

echo -e "${YELLOW}=== Core Services ===${NC}"
check_service "kube-system" "coredns" "deployment" "CoreDNS"
check_service "kube-system" "local-path-provisioner" "deployment" "Local Path Provisioner"
check_service "kube-system" "traefik" "deployment" "Traefik"
check_service "kube-system" "metrics-server" "deployment" "Metrics Server"

echo -e "\n${YELLOW}=== Storage Services ===${NC}"
check_service "longhorn-system" "longhorn-ui" "deployment" "Longhorn UI"
check_service "longhorn-system" "longhorn-manager" "daemonset" "Longhorn Manager"
check_service "longhorn-system" "longhorn-driver-deployer" "deployment" "Longhorn CSI Driver"

echo -e "\n${YELLOW}=== Management Services ===${NC}"
check_service "cattle-system" "rancher" "deployment" "Rancher"
check_service "fleet-system" "fleet-controller" "deployment" "Fleet Controller"

echo -e "\n${YELLOW}=== Monitoring & Observability ===${NC}"
check_service "observability" "prometheus-server" "deployment" "Prometheus"
check_service "observability" "grafana" "deployment" "Grafana"
check_service "observability" "loki" "statefulset" "Loki"
check_service "observability" "tempo" "deployment" "Tempo"
check_service "observability" "promtail" "daemonset" "Promtail"

echo -e "\n${YELLOW}=== GitOps & CI/CD ===${NC}"
check_service "flux-system" "source-controller" "deployment" "Flux Source Controller"
check_service "flux-system" "kustomize-controller" "deployment" "Flux Kustomize Controller"
check_service "flux-system" "helm-controller" "deployment" "Flux Helm Controller"
check_service "flux-system" "notification-controller" "deployment" "Flux Notification Controller"

echo -e "\n${YELLOW}=== External Services ===${NC}"
echo -e "${YELLOW}Checking MinIO on node1...${NC}"
if nc -z node1 9000 2>/dev/null; then
    echo -e "  ${GREEN}MinIO is accessible on port 9000${NC}"
else
    echo -e "  ${RED}MinIO is not accessible on port 9000${NC}"
fi

echo -e "${YELLOW}Checking Vault on node1...${NC}"
if nc -z node1 8200 2>/dev/null; then
    echo -e "  ${GREEN}Vault is accessible on port 8200${NC}"
else
    echo -e "  ${RED}Vault is not accessible on port 8200${NC}"
fi

echo -e "${YELLOW}Checking HAProxy on node1...${NC}"
if nc -z node1 6443 2>/dev/null; then
    echo -e "  ${GREEN}HAProxy is accessible on port 6443${NC}"
else
    echo -e "  ${RED}HAProxy is not accessible on port 6443${NC}"
fi

echo -e "\n${YELLOW}=== Cluster Health ===${NC}"
NODES_READY=$(kubectl get nodes --no-headers | grep -v NotReady | wc -l)
NODES_TOTAL=$(kubectl get nodes --no-headers | wc -l)

if [ "$NODES_READY" = "$NODES_TOTAL" ]; then
    echo -e "Nodes: ${GREEN}$NODES_READY/$NODES_TOTAL Ready${NC}"
else
    echo -e "Nodes: ${RED}$NODES_READY/$NODES_TOTAL Ready${NC}"
fi

PODS_RUNNING=$(kubectl get pods --all-namespaces --no-headers | grep -v "Completed\|Evicted\|Failed" | grep Running | wc -l)
PODS_TOTAL=$(kubectl get pods --all-namespaces --no-headers | grep -v "Completed\|Evicted\|Failed" | wc -l)

if [ "$PODS_RUNNING" = "$PODS_TOTAL" ]; then
    echo -e "Pods: ${GREEN}$PODS_RUNNING/$PODS_TOTAL Running${NC}"
else
    echo -e "Pods: ${RED}$PODS_RUNNING/$PODS_TOTAL Running${NC}"
fi

echo
echo -e "${YELLOW}=== End of Status Check ===${NC}"
