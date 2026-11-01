# debian cloud image, one copy per node (local is not shared)
resource "proxmox_download_file" "debian" {
  for_each     = local.vm_nodes
  content_type = "import"
  datastore_id = var.image_datastore
  node_name    = each.value
  url          = var.debian_image_url
  file_name    = basename(var.debian_image_url)
  overwrite    = false

  # pve doesn't keep the source url, so an imported file has none. the url only counts at the download
  lifecycle {
    ignore_changes = [url]
  }
}

resource "proxmox_virtual_environment_vm" "docker" {
  for_each = local.docker_vms

  name      = each.key
  node_name = each.value.node
  vm_id     = each.value.vmid
  on_boot   = true
  started   = true

  # changes that need a restart stay pending until a planned reboot, tofu never reboots on its own
  reboot_after_update = false

  # stateful: docker volumes (dbs) live on the vm disk — never let tofu recreate these
  lifecycle {
    prevent_destroy = true
    # the image only counts when the disk is created (and imported vms have none)
    ignore_changes = [disk[0].import_from]
  }

  # qemu-guest-agent comes from vm-preparation; flip to true and re-apply after
  agent { enabled = false }

  # serial0 socket: `qm terminal <vmid>` from the pve host when ssh/network is down
  serial_device { device = "socket" }

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
      username = local.priv.admin_user
      password = var.vm_password
      keys     = local.ssh_keys
    }
  }

  network_device {
    bridge      = local.net.lan_bridge
    mac_address = each.value.mac0
    firewall    = true
  }
}

# netbird control plane — wan-facing netbird vm. this only builds the VM shell on the debian
# cloud image for bootstrap; nixos-anywhere then wipes it and installs the flake in ../nixos.
resource "proxmox_virtual_environment_vm" "netbird" {
  name      = "netbird"
  node_name = local.vms.netbird.node
  vm_id     = local.vms.netbird.vmid
  on_boot   = true
  started   = true

  # changes that need a restart stay pending until a planned reboot, tofu never reboots on its own
  reboot_after_update = false

  # stateful once nixos lands: the mgmt sqlite db lives on this disk
  lifecycle {
    prevent_destroy = true
    # image and cloud-init only count for the debian bootstrap, nixos owns disk and network after that
    ignore_changes = [disk[0].import_from, initialization]
  }

  # debian bootstrap has no agent; flip to true after nixos-anywhere (nixos enables it)
  agent { enabled = false }

  # serial0 socket: `qm terminal <vmid>` from the pve host when ssh/network is down
  serial_device { device = "socket" }

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
      username = local.priv.admin_user
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

# home assistant os: an appliance, ha's own updates and config inside, no cloud-init, no ansible
resource "proxmox_virtual_environment_vm" "haos" {
  name      = "haos"
  node_name = local.vms.haos.node
  vm_id     = local.vms.haos.vmid
  on_boot   = true
  started   = true

  # changes that need a restart stay pending until a planned reboot, tofu never reboots on its own
  reboot_after_update = false

  # stateful: ha's config and history live on this disk
  lifecycle {
    prevent_destroy = true
    # the image only counts when the disk is created
    ignore_changes = [disk[0].import_from]
  }

  # haos ships the guest agent, pbs snapshots freeze the fs through it
  agent { enabled = true }

  # serial0 socket: `qm terminal <vmid>` from the pve host when ssh/network is down
  serial_device { device = "socket" }

  # haos only boots uefi
  bios    = "ovmf"
  machine = "q35"
  efi_disk {
    datastore_id      = var.vm_datastore
    type              = "4m"
    pre_enrolled_keys = false
  }

  cpu {
    cores = local.vms.haos.cores
    type  = "host"
  }

  memory {
    dedicated = local.vms.haos.memory
    floating  = local.vms.haos.balloon
  }

  operating_system {
    type = "l26"
  }

  scsi_hardware = "virtio-scsi-single"

  disk {
    datastore_id = var.vm_datastore
    import_from  = var.haos_image
    interface    = "scsi0"
    size         = local.vms.haos.disk
    iothread     = true
    discard      = "on"
    ssd          = true
  }

  # dhcp, the fritz!box pins haos_ip to this mac
  network_device {
    bridge      = local.net.lan_bridge
    mac_address = local.vms.haos.mac0
    firewall    = true
  }
}
