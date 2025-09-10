# Pi Cluster Scripts

This directory contains various utility scripts for the Pi Cluster.

## Available Scripts

- `access_rancher.sh`: Helps access the Rancher UI by setting up hosts entries and testing connection
- `enhanced_fix_api_auth.sh`: Enhanced script to fix API authentication issues
- `fix_api_auth.sh`: Script to fix API authentication issues
- `fix_cilium.sh`: Script to fix Cilium issues
- `fix_coredns.sh`: Script to fix CoreDNS issues
- `fix_node_taints.sh`: Script to fix node taints
- `post_install.sh`: Post-installation setup script
- `setup_k3s_env.sh`: Script to set up k3s environment variables
- `setup_kubectl.sh`: Script to set up kubectl configuration
- `troubleshoot_cluster.sh`: Script to troubleshoot cluster issues
- `verify_cluster.sh`: Script to verify cluster health

## Usage

Most scripts can be run directly:

```bash
./script_name.sh
```

For the Rancher access script specifically:

```bash
./access_rancher.sh
```

This will:
1. Add rancher.picluster.local to your /etc/hosts file if needed
2. Test the connection to the Rancher UI
3. Provide instructions for accessing the UI in your browser
