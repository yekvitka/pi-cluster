output "availability_domains" {
  description = "Availability domains in the home region"
  value       = data.oci_identity_availability_domains.ads.availability_domains[*].name
}
