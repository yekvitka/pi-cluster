#!/bin/bash
# Script to optimize Kubernetes resource usage on Pi Cluster
# This script applies memory and CPU limits to system components

echo "==== Optimizing Kubernetes Resource Usage ===="

# Function for kubectl commands
run_kubectl() {
  ansible node2 -m shell -a "kubectl $*"
}

# Function to set resource limits on a deployment
set_deployment_resources() {
  local namespace=$1
  local deployment=$2
  local cpu_req=$3
  local mem_req=$4
  local cpu_limit=$5
  local mem_limit=$6

  echo "Setting resources for $namespace/$deployment"
  
  ansible node2 -m shell -a "kubectl -n $namespace patch deployment $deployment -p '{
    \"spec\": {
      \"template\": {
        \"spec\": {
          \"containers\": [
            {
              \"name\": \"$deployment\",
              \"resources\": {
                \"requests\": {
                  \"cpu\": \"$cpu_req\",
                  \"memory\": \"$mem_req\"
                },
                \"limits\": {
                  \"cpu\": \"$cpu_limit\",
                  \"memory\": \"$mem_limit\"
                }
              }
            }
          ]
        }
      }
    }
  }'"
}

# Enable kubelet system-reserved and kube-reserved
echo "Setting kubelet reservations on all nodes..."

nodes=$(ansible node2 -m shell -a "kubectl get nodes -o jsonpath='{.items[*].metadata.name}'" | grep -v CHANGED | grep -v ">>" | tr -d '\r')
for node in $nodes; do
  # Note: On Pi systems, these values are more reasonable than defaults
  # System-reserved: Reserve resources for the OS
  # Kube-reserved: Reserve resources for Kubernetes components
  ansible node2 -m shell -a "kubectl annotate node $node --overwrite \
    kubelet.kubernetes.io/system-reserved='cpu=200m,memory=500Mi,ephemeral-storage=1Gi' \
    kubelet.kubernetes.io/kube-reserved='cpu=200m,memory=500Mi,ephemeral-storage=1Gi'"
done

# Optimize CoreDNS
echo "Optimizing CoreDNS..."
ansible node2 -m shell -a "kubectl -n kube-system patch deployment coredns -p '{
  \"spec\": {
    \"template\": {
      \"spec\": {
        \"containers\": [
          {
            \"name\": \"coredns\",
            \"resources\": {
              \"requests\": {
                \"cpu\": \"100m\",
                \"memory\": \"70Mi\"
              },
              \"limits\": {
                \"cpu\": \"200m\",
                \"memory\": \"170Mi\"
              }
            }
          }
        ]
      }
    }
  }
}'"

# Optimize Traefik
echo "Optimizing Traefik..."
ansible node2 -m shell -a "kubectl -n kube-system patch deployment traefik -p '{
  \"spec\": {
    \"template\": {
      \"spec\": {
        \"containers\": [
          {
            \"name\": \"traefik\",
            \"resources\": {
              \"requests\": {
                \"cpu\": \"100m\",
                \"memory\": \"100Mi\"
              },
              \"limits\": {
                \"cpu\": \"200m\",
                \"memory\": \"200Mi\"
              }
            }
          }
        ]
      }
    }
  }
}'"

# Optimize Metrics Server
echo "Optimizing Metrics Server..."
ansible node2 -m shell -a "kubectl -n kube-system patch deployment metrics-server -p '{
  \"spec\": {
    \"template\": {
      \"spec\": {
        \"containers\": [
          {
            \"name\": \"metrics-server\",
            \"resources\": {
              \"requests\": {
                \"cpu\": \"50m\",
                \"memory\": \"100Mi\"
              },
              \"limits\": {
                \"cpu\": \"100m\",
                \"memory\": \"200Mi\"
              }
            }
          }
        ]
      }
    }
  }
}'"

# Optimize FluxCD
echo "Optimizing FluxCD components..."
ansible node2 -m shell -a "kubectl -n flux-system patch deployment flux -p '{
  \"spec\": {
    \"template\": {
      \"spec\": {
        \"containers\": [
          {
            \"name\": \"flux\",
            \"resources\": {
              \"requests\": {
                \"cpu\": \"50m\",
                \"memory\": \"128Mi\"
              },
              \"limits\": {
                \"cpu\": \"200m\",
                \"memory\": \"512Mi\"
              }
            }
          }
        ]
      }
    }
  }
}'" || true

ansible node2 -m shell -a "kubectl -n flux-system patch deployment flux-memcached -p '{
  \"spec\": {
    \"template\": {
      \"spec\": {
        \"containers\": [
          {
            \"name\": \"memcached\",
            \"resources\": {
              \"requests\": {
                \"cpu\": \"50m\",
                \"memory\": \"64Mi\"
              },
              \"limits\": {
                \"cpu\": \"100m\",
                \"memory\": \"128Mi\"
              }
            }
          }
        ]
      }
    }
  }
}'" || true

# Optimize Longhorn
echo "Optimizing Longhorn components..."
ansible node2 -m shell -a "kubectl -n longhorn-system patch deployment longhorn-ui -p '{
  \"spec\": {
    \"template\": {
      \"spec\": {
        \"containers\": [
          {
            \"name\": \"longhorn-ui\",
            \"resources\": {
              \"requests\": {
                \"cpu\": \"100m\",
                \"memory\": \"128Mi\"
              },
              \"limits\": {
                \"cpu\": \"200m\",
                \"memory\": \"256Mi\"
              }
            }
          }
        ]
      }
    }
  }
}'" || true

echo "==== Resource optimization completed ===="
echo "Run 'kubectl top nodes' to check resource usage"
