# A bare Ubuntu server on ConoHa VPS with aitrium installed: the kind of machine
# .github/workflows/host.yml checks on, where porta's Landlock, seccomp and user namespaces
# meet a real kernel with no container around them.
#
# The conohavps provider is the Aid-On fork (https://github.com/Aid-On/terraform-provider-conohavps),
# which is not on the Registry: build it and point dev_overrides at it (its README, "セットアップ").
terraform {
  required_version = ">= 1.5"
  required_providers {
    conohavps = { source = "gmo-internet/conohavps" }
  }
}

# Credentials from CONOHAVPS_TENANT_ID, CONOHAVPS_USER_ID and CONOHAVPS_PASSWORD.
provider "conohavps" {}

data "conohavps_flavor" "plan" { name = var.flavor }
data "conohavps_image" "ubuntu" { name = var.image }

resource "conohavps_keypair" "admin" {
  name       = "${var.name}-admin"
  public_key = file(pathexpand(var.ssh_public_key))
}

resource "conohavps_volume" "boot" {
  name        = "${var.name}-boot"
  size        = 100 # the plan's own boot storage; 200 or 500 is billed as boot storage added
  volume_type = "c3j1-ds02-boot"
  image_ref   = data.conohavps_image.ubuntu.id
}

resource "conohavps_instance" "host" {
  instance_name_tag = var.name
  flavor_id         = data.conohavps_flavor.plan.id
  block_device      = [{ uuid = conohavps_volume.boot.id }]
  key_name          = conohavps_keypair.admin.name
  # Left out, a server gets only "default", which lets in nothing from outside, SSH included.
  security_group = [{ name = "IPv4v6-SSH" }]
  power_state    = "ACTIVE"
  user_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
    ssh_public_key  = trimspace(file(pathexpand(var.ssh_public_key)))
    aitrium_version = var.aitrium_version
    swap_gb         = var.swap_gb
  }))
}

locals {
  # The global address: addresses also lists additional IPs (add-) and local networks (local-).
  ipv4 = [for net, addrs in conohavps_instance.host.addresses : [for a in addrs : a.addr if a.version == 4][0] if startswith(net, "ext-")][0]
}
