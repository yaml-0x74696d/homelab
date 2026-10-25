resource "proxmox_virtual_environment_container" "storage" {
  node_name     = local.lxcs.storage.node
  vm_id         = local.lxcs.storage.vmid
  unprivileged  = true
  start_on_boot = true

  cpu {
    cores = local.lxcs.storage.cores
  }

  memory {
    dedicated = local.lxcs.storage.memory
    swap      = local.lxcs.storage.swap
  }

  features {
    nesting = true
  }

  operating_system {
    type             = "debian"
    template_file_id = var.lxc_template
  }

  disk {
    datastore_id = var.vm_datastore
    size         = local.lxcs.storage.disk
  }

  network_interface {
    name        = "eth0"
    bridge      = local.net.lan_bridge
    mac_address = local.lxcs.storage.mac
    firewall    = true
  }

  initialization {
    hostname = "storage"
    ip_config {
      ipv4 {
        address = "${local.lxcs.storage.ip}/${local.lan_prefix}"
        gateway = local.net.gateway_ip
      }
    }
    dns {
      servers = [local.net.gateway_ip]
    }
    user_account {
      keys     = local.ssh_keys
      password = var.vm_password
    }
  }

  # host mergerfs pool (roles/mergerfs); must exist before this mounts
  mount_point {
    volume = local.storage.storage_pool_host
    path   = local.storage.storage_root
  }
}
