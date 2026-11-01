locals {
  # same facts ansible uses: ips, vmids, admin user, ssh key, pool paths. one source.
  net     = yamldecode(file("${path.module}/../ansible/group_vars/all/network.yml"))
  ports   = yamldecode(file("${path.module}/../ansible/group_vars/all/ports.yml"))
  hosts   = yamldecode(file("${path.module}/../ansible/group_vars/all/hosts.yml"))
  storage = yamldecode(file("${path.module}/../ansible/group_vars/all/storage.yml"))

  # per-lab values (domain, macs, disks), see private.yml.example next to it
  priv = yamldecode(file("${path.module}/../ansible/group_vars/all/private/private.yml"))
  macs = local.priv.macs

  pve_endpoint = var.pve_endpoint != "" ? var.pve_endpoint : "https://${local.net.pve1_ip}:${local.ports.pve_ui_port}/"
  lan_prefix   = split("/", local.net.lan_cidr)[1]
  ssh_keys     = [trimspace(file(pathexpand(local.hosts.admin_ssh_pubkey_file)))]

  # vm specs. macs come from private.yml: they pin dhcp leases, nixos matches netbird's nic by it.
  # balloon = min floor; guest runs at `memory`, host reclaims toward `balloon` only under pressure.
  # floors sit >= real usage: guests have no swap, so squeezing below working set OOMs a container.
  vms = {
    "docker-1" = { vmid = local.net.vmids.docker1, node = "pve-1", cores = 4, memory = 4096, balloon = 3072, disk = 32, ip = local.net.docker1_ip, mac0 = local.macs["docker-1"].lan }
    "docker-2" = { vmid = local.net.vmids.docker2, node = "pve-2", cores = 4, memory = 4096, balloon = 2048, disk = 32, ip = local.net.docker2_ip, mac0 = local.macs["docker-2"].lan }
    "docker-3" = { vmid = local.net.vmids.docker3, node = "pve-3", cores = 4, memory = 12288, balloon = 8192, disk = 32, ip = local.net.docker3_ip, mac0 = local.macs["docker-3"].lan }
    "netbird"  = { vmid = local.net.vmids.netbird, node = "pve-2", cores = 2, memory = 2048, balloon = 1024, disk = 20, ip = local.net.netbird_ip, mac0 = local.macs.netbird.lan }
    # haos: no balloon floor, ha keeps its state in ram and the esphome add-on compiles there
    "haos" = { vmid = local.net.vmids.haos, node = "pve-3", cores = 2, memory = 3072, balloon = 0, disk = 32, ip = local.net.haos_ip, mac0 = local.macs.haos.lan }
  }
  docker_vms = { for k, v in local.vms : k => v if startswith(k, "docker-") }

  lxcs = {
    "storage" = { vmid = local.net.vmids.storage, node = "pve-3", cores = 2, memory = 1024, swap = 512, disk = 24, ip = local.net.storage_ip, mac = local.macs.storage.lan }
    "log"     = { vmid = local.net.vmids.log, node = "pve-3", cores = 1, memory = 512, swap = 256, disk = 32, ip = local.net.log_ip, mac = local.macs.log.lan }
    "iot"     = { vmid = local.net.vmids.iot, node = local.net.iot_node, cores = 1, memory = 512, swap = 256, disk = 8, ip = local.net.iot_lan_ip, mac = local.macs.iot.lan }
  }

  vm_nodes = toset([for v in local.vms : v.node])
}
