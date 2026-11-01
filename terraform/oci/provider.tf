# Oracle Cloud (Always Free): offsite backup copy and outside monitoring.
# API key in ~/.secrets/oci (not in Git), OCIDs in terraform.tfvars (gitignored)
provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}
