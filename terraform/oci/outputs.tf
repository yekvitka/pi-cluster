output "availability_domains" {
  description = "Availability domains in the home region"
  value       = data.oci_identity_availability_domains.ads.availability_domains[*].name
}

output "offsite_public_ip" {
  description = "WireGuard endpoint for the home gateway (OCI_ENDPOINT of wireguard-oci.sh)"
  value       = oci_core_instance.offsite.public_ip
}

output "offsite_tunnel_ip" {
  description = "VM address inside the WireGuard tunnel: SSH ubuntu@10.99.0.2"
  value       = "10.99.0.2"
}
