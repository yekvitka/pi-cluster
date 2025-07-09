# Rancher Installation Guide

This guide explains how to install Rancher on your k3s cluster.

## Prerequisites

- A working k3s cluster
- Helm installed on the control node
- kubectl configured to access the cluster

## Installation Steps

1. Configure DNS resolution for Rancher:

```bash
ansible-playbook configure_rancher_dns.yml
```

This playbook adds the Rancher hostname (`rancher.picluster.local`) to the `/etc/hosts` file on all cluster nodes, pointing to the k3s API VIP (master node).

2. Install Rancher:

```bash
ansible-playbook install_rancher_script.yml
```

This playbook:
- Copies the installation script to the first master node
- Executes the script which:
  - Installs cert-manager (required by Rancher)
  - Installs Rancher 2.11.3
  - Configures Rancher with a bootstrap password

## Accessing Rancher

Once installation is complete, you can access Rancher at:

- URL: https://rancher.picluster.local
- Initial password: `admin`

If you're accessing from a machine that doesn't have DNS resolution for "rancher.picluster.local", add an entry to your hosts file:
```
192.168.50.201 rancher.picluster.local
```

To get the bootstrap password if needed:
```bash
ssh node2 "kubectl get secret --namespace cattle-system bootstrap-secret -o go-template='{{.data.bootstrapPassword|base64decode}}'"
```

## Files

- `configure_rancher_dns.yml`: Playbook to set up DNS entries
- `install_rancher_script.yml`: Main playbook to install Rancher
- `files/install_rancher.sh`: Shell script that performs the actual installation

## Customization

To modify the Rancher installation:

1. Edit `files/install_rancher.sh` to change version or configuration options
2. Update the `rancher_hostname` in `vars/picluster.yml` if needed
