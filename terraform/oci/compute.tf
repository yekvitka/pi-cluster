data "oci_core_images" "ubuntu" {
  compartment_id           = var.tenancy_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

locals {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[var.availability_domain_index].name
}

# Always Free: Ampere A1 (arm64, like the Pis), 1 of 4 OCPUs and 6 of 24 GB
resource "oci_core_instance" "offsite" {
  compartment_id      = oci_identity_compartment.homelab.id
  availability_domain = local.availability_domain
  display_name        = "offsite"
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = 1
    memory_in_gbs = 6
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu.images[0].id
    boot_volume_size_in_gbs = 50
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = true
    hostname_label   = "offsite"
  }

  metadata = {
    ssh_authorized_keys = trimspace(file(var.ssh_public_key_path))
    user_data = base64encode(templatefile("${path.module}/cloud-init.yaml.tftpl", {
      wg_private_key        = trimspace(file(var.wg_private_key_path))
      gateway_wg_public_key = var.gateway_wg_public_key
      wg_listen_port        = var.wg_listen_port
      wg_mtu                = var.wg_mtu
    }))
  }

  lifecycle {
    # A newer image or edited first-boot config must not recreate the VM:
    # cloud-init only runs at first boot, later changes go through Ansible
    ignore_changes = [source_details[0].source_id, metadata["user_data"]]
  }
}

# Backup data, separate from the OS. 50 GB boot + 150 GB = the 200 GB Always Free block storage
resource "oci_core_volume" "backups" {
  compartment_id      = oci_identity_compartment.homelab.id
  availability_domain = local.availability_domain
  display_name        = "offsite-backups"
  size_in_gbs         = 150
}

resource "oci_core_volume_attachment" "backups" {
  attachment_type = "paravirtualized"
  instance_id     = oci_core_instance.offsite.id
  volume_id       = oci_core_volume.backups.id
}
