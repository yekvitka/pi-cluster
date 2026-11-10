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

# Control host in Oracle Cloud (docs/control-host.md): optional

variable "pimaster_enabled" {
  description = "Create the control host VM (pimaster). The offsite VM works without it"
  type        = bool
  default     = false
}

variable "pimaster_availability_domain_index" {
  description = "Availability domain for pimaster (0-2). Change it if the A1 shape is out of capacity"
  type        = number
  default     = 0
}

variable "pimaster_ssh_authorized_keys" {
  description = "SSH public keys of the pimaster user: your laptop, and the current control host for the first copy"
  type        = list(string)
  default     = []
}

variable "pimaster_wg_private_key_path" {
  description = "WireGuard private key of pimaster, outside the repo (~/.secrets/wireguard/pimaster-oci.key)"
  type        = string
  default     = null
}

variable "pimaster_wg_public_key_path" {
  description = "WireGuard public key of pimaster (~/.secrets/wireguard/pimaster-oci.pub): its peer on the offsite VM"
  type        = string
  default     = null
}

variable "wg_public_key_path" {
  description = "WireGuard public key of the offsite VM (~/.secrets/wireguard/oci-vm.pub): its peer on pimaster"
  type        = string
  default     = null
}

variable "wg_clients" {
  description = "Remote access clients of pimaster, addresses in 10.99.0.16/28: name => address and WireGuard public key"
  type = map(object({
    address    = string
    public_key = string
  }))
  default = {}
}

variable "dns_domain" {
  description = "Homelab DNS domain (dns_domain in Ansible): pimaster resolves it through the gateway"
  type        = string
  default     = null
}
