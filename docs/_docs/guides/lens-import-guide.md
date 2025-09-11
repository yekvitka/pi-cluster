# Importing K3s Cluster into Lens (OpenLens)

This guide will help you import your K3s cluster configuration into Lens (OpenLens) for easy management and monitoring.

## Prerequisites

1. [Download and install Lens/OpenLens](https://github.com/MuhammedKalkan/OpenLens/releases) on your Mac if you haven't already
2. Ensure you have the most recent `working-lens-config.yaml` file with updated certificates
3. Verify network connectivity to your cluster's HAProxy VIP (10.0.0.11:6443)

## Verifying Your Config

Before importing to Lens, test the kubeconfig with kubectl to verify it works:
```bash
kubectl --kubeconfig=/path/to/working-lens-config.yaml get nodes
```

You should see all your nodes (node2, node3, node4, node5) listed as Ready.

## Importing Your Cluster

### Option 1: Using the kubeconfig file

1. Copy the `working-lens-config.yaml` file from the Pi Cluster to your Mac:
   ```bash
   scp pimaster:/home/pimaster/pi-cluster/working-lens-config.yaml ~/Desktop/
   ```

2. Open Lens/OpenLens on your Mac

3. Click on the "+" icon in the left sidebar or use the "File" menu and select "Add Cluster"

4. In the dialog that appears, click "Browse" and select the `working-lens-config.yaml` file you copied to your Desktop

5. Lens will automatically detect the cluster configuration and add it to your clusters list

6. Click on your newly added "yekvitka-k3s-cluster" in the left sidebar to connect and start managing your cluster

### Option 2: Using Lens Catalog (Alternative Method)

1. In Lens, click on the "Catalog" icon in the left sidebar (looks like a grid/squares)

2. Click the "+" button to add a new catalog entry

3. Select "Kubeconfig" as the source type

4. Either:
   - Browse and select your kubeconfig file
   - Or paste the contents of your `working-lens-config.yaml` file

5. Give your cluster a name (e.g., "Yekvitka K3s Cluster")

6. Click "Add" to save the catalog entry

7. Your cluster will now appear in the catalog from where you can connect to it

## Accessing Cluster Services from Lens

Once connected to your cluster through Lens, you can:

1. View and manage all Kubernetes resources
2. Access the built-in terminal to run kubectl commands
3. View logs and events
4. Monitor cluster performance
5. Access services through port-forwarding:
   - Right-click on a service (e.g., Grafana) and select "Forward"
   - Access through the provided local port

## Troubleshooting

If you encounter connection issues:

1. Ensure your Mac can reach the cluster at 10.0.0.11:6443
2. Verify that the certificate data in the config file is correct
3. Check your /etc/hosts file contains the entry for your cluster VIP
4. Try using port-forwarding to bypass any network restrictions:
   ```bash
   ssh -L 6443:10.0.0.11:6443 pimaster
   ```
   Then update the server in the kubeconfig to `https://localhost:6443`

5. Certificate issues:
   - If you see "x509: certificate signed by unknown authority" errors
   - Verify the certificate-authority-data in your kubeconfig matches the server's CA cert
   - Alternatively, you can temporarily disable certificate verification (insecure, for testing only):
     ```bash
     kubectl --kubeconfig=/path/to/working-lens-config.yaml --insecure-skip-tls-verify get nodes
     ```

6. Context issues:
   - If the wrong context is selected, explicitly use:
     ```bash
     kubectl --kubeconfig=/path/to/working-lens-config.yaml --context=yekvitka-k3s-cluster get nodes
     ```

## Accessing Cluster Services

After successfully connecting to your cluster with Lens, you can access:

1. Rancher: https://rancher.yekvitka.local (10.0.0.13 or 10.0.0.15)
2. Grafana: https://grafana.yekvitka.local (10.0.0.13)
3. Loki: https://loki.yekvitka.local (10.0.0.13)
4. Tempo: https://tempo.yekvitka.local (10.0.0.13)

Add these domain mappings to your Mac's /etc/hosts file:
```
# K3s cluster services
10.0.0.13 rancher.yekvitka.local grafana.yekvitka.local loki.yekvitka.local tempo.yekvitka.local
```

Or, you can use port-forwarding through Lens to access these services without DNS setup:
1. In Lens, navigate to "Network" > "Services"
2. Find the service you want to access (e.g., grafana-service in monitoring namespace)
3. Click the "Forward" button in the right panel
4. Lens will open a local port that forwards to the service

## Notes

- The kubeconfig is set to use the cluster's HAProxy VIP (10.0.0.11:6443)
- The connection is secured with TLS certificates
- The current config includes updated certificates for both the CA and client
- You may need to accept security warnings about self-signed certificates
- This config has been tested and verified to work with kubectl
