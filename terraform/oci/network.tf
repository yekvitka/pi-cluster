resource "oci_identity_compartment" "homelab" {
  compartment_id = var.tenancy_ocid
  name           = "homelab"
  description    = "pi-cluster homelab: offsite backups and outside monitoring"
  enable_delete  = true
}

resource "oci_core_vcn" "homelab" {
  compartment_id = oci_identity_compartment.homelab.id
  display_name   = "homelab"
  # No overlap with the cluster LAN (10.0.0.0/24), home network (192.168.50.0/24),
  # k3s pods/services (10.42/10.43) or the WireGuard tunnel (10.99.0.0/24)
  cidr_blocks = ["10.20.0.0/16"]
  dns_label   = "homelab"
}

resource "oci_core_internet_gateway" "homelab" {
  compartment_id = oci_identity_compartment.homelab.id
  vcn_id         = oci_core_vcn.homelab.id
  display_name   = "homelab"
}

resource "oci_core_route_table" "public" {
  compartment_id = oci_identity_compartment.homelab.id
  vcn_id         = oci_core_vcn.homelab.id
  display_name   = "public"
  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.homelab.id
  }
}

# The VCN default security list opens SSH to the internet: keep it empty
resource "oci_core_default_security_list" "default" {
  manage_default_resource_id = oci_core_vcn.homelab.default_security_list_id
  display_name               = "default (empty)"
}

resource "oci_core_security_list" "offsite" {
  compartment_id = oci_identity_compartment.homelab.id
  vcn_id         = oci_core_vcn.homelab.id
  display_name   = "offsite"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  # WireGuard only: the home gateway has a dynamic IP and connects out to the VM.
  # WireGuard does not answer unauthenticated packets. SSH goes through the tunnel
  ingress_security_rules {
    description = "WireGuard from the home gateway"
    source      = "0.0.0.0/0"
    protocol    = "17"
    udp_options {
      min = var.wg_listen_port
      max = var.wg_listen_port
    }
  }

  ingress_security_rules {
    description = "Path MTU discovery"
    source      = "0.0.0.0/0"
    protocol    = "1"
    icmp_options {
      type = 3
      code = 4
    }
  }
}

resource "oci_core_subnet" "public" {
  compartment_id    = oci_identity_compartment.homelab.id
  vcn_id            = oci_core_vcn.homelab.id
  display_name      = "public"
  cidr_block        = "10.20.1.0/24"
  dns_label         = "public"
  route_table_id    = oci_core_route_table.public.id
  security_list_ids = [oci_core_security_list.offsite.id]
}
