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

  # template and first user only count at creation: a new template is for new cts, existing ones update
  # through apt; the api never returns keys/password, so an imported ct would otherwise always be replaced
  lifecycle {
    ignore_changes = [operating_system[0].template_file_id, initialization[0].user_account]
  }
}

# central rsyslog (relp), on pve-3 because it's always on
resource "proxmox_virtual_environment_container" "log" {
  node_name     = local.lxcs.log.node
  vm_id         = local.lxcs.log.vmid
  unprivileged  = true
  start_on_boot = true

  cpu {
    cores = local.lxcs.log.cores
  }

  memory {
    dedicated = local.lxcs.log.memory
    swap      = local.lxcs.log.swap
  }

  # systemd 257 (debian 13) needs it for its sandboxing
  features {
    nesting = true
  }

  operating_system {
    type             = "debian"
    template_file_id = var.lxc_template
  }

  disk {
    datastore_id = var.vm_datastore
    size         = local.lxcs.log.disk
  }

  # firewall bit on: roles/pve_firewall filters inbound (log.fw)
  network_interface {
    name        = "eth0"
    bridge      = local.net.lan_bridge
    mac_address = local.lxcs.log.mac
    firewall    = true
  }

  initialization {
    hostname = "log"
    ip_config {
      ipv4 {
        address = "${local.lxcs.log.ip}/${local.lan_prefix}"
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

  # template and first user only count at creation: a new template is for new cts, existing ones update
  # through apt; the api never returns keys/password, so an imported ct would otherwise always be replaced
  lifecycle {
    ignore_changes = [operating_system[0].template_file_id, initialization[0].user_account]
  }
}

# iot gateway: mqtt broker, the only guest on the iot bridge. lan leg for the consumers (ha, prometheus)
resource "proxmox_virtual_environment_container" "iot" {
  node_name     = local.lxcs.iot.node
  vm_id         = local.lxcs.iot.vmid
  unprivileged  = true
  start_on_boot = true

  cpu {
    cores = local.lxcs.iot.cores
  }

  memory {
    dedicated = local.lxcs.iot.memory
    swap      = local.lxcs.iot.swap
  }

  # systemd 257 (debian 13) needs it for its sandboxing
  features {
    nesting = true
  }

  operating_system {
    type             = "debian"
    template_file_id = var.lxc_template
  }

  disk {
    datastore_id = var.vm_datastore
    size         = local.lxcs.iot.disk
  }

  # firewall bit on: roles/pve_firewall filters the lan leg (iot.fw), ufw inside does the same.
  # the iot leg is the wifi card itself, raw lxc.net lines from deploy-iot.yml (the api can't set them)
  network_interface {
    name        = "eth0"
    bridge      = local.net.lan_bridge
    mac_address = local.lxcs.iot.mac
    firewall    = true
  }

  initialization {
    hostname = "iot"
    ip_config {
      ipv4 {
        address = "${local.lxcs.iot.ip}/${local.lan_prefix}"
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

  # template and first user only count at creation: a new template is for new cts, existing ones update
  # through apt; the api never returns keys/password, so an imported ct would otherwise always be replaced
  lifecycle {
    ignore_changes = [operating_system[0].template_file_id, initialization[0].user_account]
  }
}
