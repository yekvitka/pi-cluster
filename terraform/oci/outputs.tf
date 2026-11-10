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

output "offsite_private_ip" {
  description = "offsite VM address in the VCN: pimaster's WireGuard endpoint for it"
  value       = oci_core_instance.offsite.private_ip
}

output "pimaster_public_ip" {
  description = "WireGuard endpoint of the control host (PIMASTER_ENDPOINT of wireguard-oci.sh, Endpoint of the clients)"
  value       = one(oci_core_instance.pimaster[*].public_ip)
}

output "pimaster_tunnel_ip" {
  description = "Control host address inside the WireGuard tunnel: SSH pimaster@10.99.0.3"
  value       = var.pimaster_enabled ? "10.99.0.3" : null
}
