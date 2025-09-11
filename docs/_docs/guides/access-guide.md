# K3s Cluster Services Access Guide

## Domain Configuration
All services are configured with the domain `yekvitka.local` and can be accessed through the following URLs:

- **Rancher**: https://rancher.yekvitka.local
- **Grafana**: https://grafana.yekvitka.local
- **Loki**: https://loki.yekvitka.local
- **Tempo**: https://tempo.yekvitka.local
- **S3**: https://s3.yekvitka.local
- **Vault**: https://vault.yekvitka.local

## Access Credentials

### Rancher
- URL: https://rancher.yekvitka.local
- Username: admin
- Password: admin (default)

To get the bootstrap password:
```bash
kubectl get secret --namespace cattle-system bootstrap-secret -o go-template='{{.data.bootstrapPassword|base64decode}}{{ "\n" }}'
```

### Grafana
- URL: https://grafana.yekvitka.local
- Username: admin
- Password: s1cret0

To get the Grafana password:
```bash
kubectl get secret --namespace monitoring kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 -d
```

## DNS Configuration
The local /etc/hosts file on your Mac has been configured with the following entries:
```
10.0.0.13   rancher.yekvitka.local
10.0.0.13   grafana.yekvitka.local
10.0.0.13   loki.yekvitka.local
10.0.0.13   tempo.yekvitka.local
10.0.0.11   s3.yekvitka.local
10.0.0.11   vault.yekvitka.local
```

## Troubleshooting Access
1. If you receive a certificate warning, this is expected as we're using self-signed certificates. You can safely proceed.
2. If you get a "page not found" error:
   - Check that the ingress controller is running: `kubectl get pods -n ingress-nginx`
   - Verify the ingress configurations: `kubectl get ingress --all-namespaces`
   - Check DNS resolution: `nslookup rancher.yekvitka.local`
   - Ensure the services are running: `kubectl get pods -n cattle-system` and `kubectl get pods -n monitoring`

## SSL Certificate Management
All services are secured with TLS certificates managed by cert-manager. The certificates are self-signed and automatically provisioned through the `selfsigned-issuer` ClusterIssuer.

## Support Services
- **CoreDNS**: Handles internal DNS resolution for services
- **Nginx Ingress**: Provides external access to services
- **Cert-Manager**: Manages TLS certificates

If you need to reconfigure any services, the configurations are stored in `/home/pimaster/pi-cluster/ansible/dns/ingress/`.
