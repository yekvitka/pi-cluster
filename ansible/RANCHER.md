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

- URL: https://rancher.picluster.local/dashboard/
- Initial password: `admin`

### Interactive Access Script

For easy access with troubleshooting options, use the provided interactive script:

```bash
/home/pimaster/pi-cluster/scripts/access_rancher.sh
```

This script provides:
1. Connection testing and diagnostics
2. Multiple access methods (HTTPS, HTTP, direct IP)
3. Browser compatibility tips
4. Log checking and pod management

For non-interactive usage:
```bash
# Run basic tests only
/home/pimaster/pi-cluster/scripts/access_rancher.sh --help

# Run tests and attempt to open browser automatically
/home/pimaster/pi-cluster/scripts/access_rancher.sh --auto
```

### Troubleshooting White Screen Issues

If you see a white screen when accessing Rancher:

1. **Try different URLs**:
   - HTTPS with hostname: https://rancher.picluster.local/dashboard/
   - HTTP with hostname: http://rancher.picluster.local/dashboard/
   - HTTPS with direct IP: https://10.0.0.13/dashboard/
   - HTTP with direct IP: http://10.0.0.13/dashboard/

2. **Browser Solutions**:
   - Use Firefox or Chrome (recommended)
   - Try Incognito/Private browsing mode
   - Clear browser cache and cookies
   - Check that JavaScript is enabled
   - Check browser console (F12) for errors

3. **Backend Solutions**:
   - Restart Rancher pods: `kubectl -n cattle-system rollout restart deployment rancher`
   - Check Rancher logs: `kubectl -n cattle-system logs deployment/rancher`

### Manual Host Setup

If you're accessing from a machine that doesn't have DNS resolution for "rancher.picluster.local", add an entry to your hosts file:
```
10.0.0.13 rancher.picluster.local
```

To get the bootstrap password if needed:
```bash
ssh node2 "kubectl get secret --namespace cattle-system bootstrap-secret -o go-template='{{.data.bootstrapPassword|base64decode}}'"
```

## Accessing from macOS

When accessing Rancher from a Mac, follow these special instructions:

```bash
# Run the script with the --mac option to see Mac-specific instructions
/home/pimaster/pi-cluster/scripts/access_rancher.sh --mac
```

**Key Points for Mac Access**:
- Direct IP access (`https://10.0.0.13/dashboard/`) **will not work** due to hostname-based ingress rules
- You **must** add an entry to your Mac's `/etc/hosts` file
- Detailed instructions are available in `/home/pimaster/pi-cluster/docs/mac_rancher_access.md`

## Files

- `configure_rancher_dns.yml`: Playbook to set up DNS entries
- `install_rancher_script.yml`: Main playbook to install Rancher
- `files/install_rancher.sh`: Shell script that performs the actual installation
- `/home/pimaster/pi-cluster/scripts/access_rancher.sh`: Helper script for accessing Rancher
- `/home/pimaster/pi-cluster/docs/mac_rancher_access.md`: macOS access guide

## Customization

To modify the Rancher installation:

1. Edit `files/install_rancher.sh` to change version or configuration options
2. Update the `rancher_hostname` in `vars/picluster.yml` if needed
