variable "tenancy_ocid" {
  description = "Tenancy OCID (also the root compartment)"
  type        = string
}

variable "user_ocid" {
  description = "API user OCID"
  type        = string
}

variable "fingerprint" {
  description = "API key fingerprint"
  type        = string
}

variable "private_key_path" {
  description = "API private key (PEM), outside the repo"
  type        = string
}

variable "region" {
  description = "Home region: the Always Free Arm (A1) shapes exist only there"
  type        = string
}
