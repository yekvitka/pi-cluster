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

variable "availability_domain_index" {
  description = "Availability domain for the VM (0-2). Change it if the A1 shape is out of capacity"
  type        = number
  default     = 0
}

variable "ssh_public_key_path" {
  description = "SSH public key for the ubuntu user (SSH only through the WireGuard tunnel)"
  type        = string
}

variable "wg_private_key_path" {
  description = "WireGuard private key of the VM, outside the repo (~/.secrets/wireguard/oci-vm.key)"
  type        = string
}

variable "gateway_wg_public_key" {
  description = "WireGuard public key of the home OpenWrt gateway (metal/openwrt/script/wireguard-oci.sh prints it)"
  type        = string
}

variable "wg_listen_port" {
  description = "WireGuard UDP port on the VM"
  type        = number
  default     = 51820
}

variable "wg_mtu" {
  description = "Tunnel MTU: home uplink path MTU 1460 minus 80 bytes of WireGuard overhead (worst case, IPv6)"
  type        = number
  default     = 1380
}
