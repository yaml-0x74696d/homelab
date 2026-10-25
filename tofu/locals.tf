locals {
  # same facts ansible uses: ips, vmids, admin user, ssh key, pool paths. one source.
  net     = yamldecode(file("${path.module}/../ansible/group_vars/all/network.yml"))
  ports   = yamldecode(file("${path.module}/../ansible/group_vars/all/ports.yml"))
  hosts   = yamldecode(file("${path.module}/../ansible/group_vars/all/hosts.yml"))
  storage = yamldecode(file("${path.module}/../ansible/group_vars/all/storage.yml"))

  pve_endpoint = var.pve_endpoint != "" ? var.pve_endpoint : "https://${local.net.pve1_ip}:${local.ports.pve_ui_port}/"
  lan_prefix   = split("/", local.net.lan_cidr)[1]
  ssh_keys     = [trimspace(file(pathexpand(local.hosts.admin_ssh_pubkey_file)))]

  # vm specs. sample macs (BC:24:11 = proxmox prefix, then the vmid): set your own,
  # they pin dhcp leases and nixos matches netbird's nic by it.
  # balloon = min floor; guest runs at `memory`, host reclaims toward `balloon` only under pressure.
  # floors sit >= real usage: guests have no swap, so squeezing below working set OOMs a container.
  vms = {
    "docker-1" = { vmid = local.net.vmids.docker1, node = "pve-1", cores = 4, memory = 4096, balloon = 3072, disk = 32, ip = local.net.docker1_ip, mac0 = "BC:24:11:00:02:01", mac1 = "BC:24:11:00:12:01" }
    "docker-2" = { vmid = local.net.vmids.docker2, node = "pve-2", cores = 4, memory = 4096, balloon = 2048, disk = 32, ip = local.net.docker2_ip, mac0 = "BC:24:11:00:02:02", mac1 = null }
    "docker-3" = { vmid = local.net.vmids.docker3, node = "pve-3", cores = 4, memory = 12288, balloon = 8192, disk = 32, ip = local.net.docker3_ip, mac0 = "BC:24:11:00:02:03", mac1 = null }
    "netbird"  = { vmid = local.net.vmids.netbird, node = "pve-2", cores = 2, memory = 2048, balloon = 1024, disk = 20, ip = local.net.netbird_ip, mac0 = local.net.netbird_mac, mac1 = null }
  }
  docker_vms = { for k, v in local.vms : k => v if k != "netbird" }

  lxcs = {
    "storage" = { vmid = local.net.vmids.storage, node = "pve-3", cores = 2, memory = 2048, swap = 512, disk = 24, ip = local.net.storage_ip, mac = "BC:24:11:00:03:00" }
  }

  vm_nodes = toset([for v in local.vms : v.node])
}
