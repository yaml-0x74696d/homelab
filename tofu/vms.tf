# debian cloud image, one copy per node (local is not shared)
resource "proxmox_download_file" "debian" {
  for_each     = local.vm_nodes
  content_type = "import"
  datastore_id = var.image_datastore
  node_name    = each.value
  url          = var.debian_image_url
  file_name    = basename(var.debian_image_url)
  overwrite    = false
}

resource "proxmox_virtual_environment_vm" "docker" {
  for_each = local.docker_vms

  name      = each.key
  node_name = each.value.node
  vm_id     = each.value.vmid
  on_boot   = true
  started   = true

  # stateful: docker volumes (dbs) live on the vm disk — never let tofu recreate these
  lifecycle {
    prevent_destroy = true
  }

  # qemu-guest-agent comes from vm-preparation; flip to true and re-apply after
  agent { enabled = false }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
    floating  = each.value.balloon # < dedicated enables autoballooning
  }

  operating_system {
    type = "l26"
  }

  scsi_hardware = "virtio-scsi-single"

  disk {
    datastore_id = var.vm_datastore
    import_from  = proxmox_download_file.debian[each.value.node].id
    interface    = "scsi0"
    size         = each.value.disk
    iothread     = true
    discard      = "on" # guest trims return freed blocks to the thin pool
    ssd          = true # non-rotational hint so trim actually fires
  }

  initialization {
    datastore_id = var.vm_datastore
    ip_config {
      ipv4 {
        address = "${each.value.ip}/${local.lan_prefix}"
        gateway = local.net.gateway_ip
      }
    }
    dns {
      servers = [local.net.gateway_ip]
    }
    user_account {
      username = local.net.admin_user
      password = var.vm_password
      keys     = local.ssh_keys
    }
  }

  network_device {
    bridge      = local.net.lan_bridge
    mac_address = each.value.mac0
    firewall    = true
  }

  # second leg on the isolated iot bridge (docker-1 only)
  dynamic "network_device" {
    for_each = each.value.mac1 != null ? [1] : []
    content {
      bridge      = local.net.iot_bridge
      mac_address = each.value.mac1
      firewall    = true
    }
  }
}

# netbird control plane — wan-facing dmz box. this only builds the VM shell on the debian
# cloud image for bootstrap; nixos-anywhere then wipes it and installs the flake in ../nixos.
resource "proxmox_virtual_environment_vm" "netbird" {
  name      = "netbird"
  node_name = local.vms.netbird.node
  vm_id     = local.vms.netbird.vmid
  on_boot   = true
  started   = true

  # stateful once nixos lands: the mgmt sqlite db lives on this disk
  lifecycle {
    prevent_destroy = true
  }

  # debian bootstrap has no agent; flip to true after nixos-anywhere (nixos enables it)
  agent { enabled = false }

  cpu {
    cores = local.vms.netbird.cores
    type  = "host"
  }

  memory {
    dedicated = local.vms.netbird.memory
    floating  = local.vms.netbird.balloon
  }

  operating_system {
    type = "l26"
  }

  scsi_hardware = "virtio-scsi-single"

  disk {
    datastore_id = var.vm_datastore
    import_from  = proxmox_download_file.debian[local.vms.netbird.node].id
    interface    = "scsi0"
    size         = local.vms.netbird.disk
    iothread     = true
    discard      = "on"
    ssd          = true
  }

  # bootstrap only: cloud-init gets us a reachable login for nixos-anywhere.
  # nixos then sets the static ip itself (see nixos/netbird/configuration.nix).
  initialization {
    datastore_id = var.vm_datastore
    ip_config {
      ipv4 {
        address = "${local.vms.netbird.ip}/${local.lan_prefix}"
        gateway = local.net.gateway_ip
      }
    }
    dns {
      # pihole first so it resolves the git host for the flake, gateway as fallback
      servers = [local.net.dns_ip, local.net.gateway_ip]
    }
    user_account {
      username = local.net.admin_user
      password = var.vm_password
      keys     = local.ssh_keys
    }
  }

  network_device {
    bridge      = local.net.lan_bridge
    mac_address = local.vms.netbird.mac0
    firewall    = true
  }
}
