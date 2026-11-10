# Fitting the lab to new hardware

Where the hardware is written down, and what to change when a node is replaced, added or removed. The steps it points to are in [bootstrap.md](bootstrap.md).

## Where the hardware lives

| What | Where |
|---|---|
| Node names and IPs | `inventory.yml` (`proxmox`), `group_vars/all/network.yml` (`pveN_ip`) |
| Which guest runs on which node | `guest_nodes` in `network.yml`, read by OpenTofu and `roles/reach` |
| Nodes that are off now and then | `part_time_nodes` in `network.yml` (their guests may be down without failing a run) |
| Guest size: cores, RAM, balloon floor, disk | `vms` and `lxcs` in `tofu/locals.tf` |
| CPU type | `cpu { type = "host" }` in `tofu/vms.tf`: a guest needs the CPU level of the node it runs on ([ADR 0025](adr/0025-debian-guests-until-x86-64-v3.md)) |
| NIC MACs (they pin the DHCP leases) | `macs` in `private.yml` |
| Pool disks | `storage_disks` (UUIDs) in `private.yml`, `roles/mergerfs` |
| PBS datastore | a thin LV on pve-3's SSD, mounted at `/mnt/pbs` ([bootstrap step 1](bootstrap.md#1-proxmox-nodes)) |
| Thin pool Authentik's deploy watches | `authentik_pool_node` / `authentik_pool_lv` in `playbooks/deploy-authentik.yml` |
| IoT WiFi card | the node in `guest_nodes.iot`, passed into the IoT LXC ([ADR 0029](adr/0029-wifi-card-in-the-gateway.md)) |
| ctl-1 (ARM, outside the cluster) | `podman_hosts`, no PBS client, static network config on the Pi itself |

## Before any change

- A fresh PBS run on every pod VM: `ansible pod_vms -b -a 'systemctl start pbs-backup.service'`
- Check the RAM: the guests of a node have to fit its RAM at their balloon floor, with room for the host

## Replace a node (same name)

The new box takes over the old node's name, IP and guests.

1. Install Proxmox, give it the old name and IP, join the cluster ([bootstrap step 1](bootstrap.md#1-proxmox-nodes)). Remove the old node from the cluster first (`pvecm delnode <name>` on a remaining node)
2. If the CPU level differs (x86-64-v2 vs v3), every guest that will run on it has to match: `cpu = host` passes the node's CPU straight through
3. Storage that lived on the old box (the pool disks, the PBS datastore on pve-3): new UUIDs into `storage_disks`, the datastore LV again
4. Its guests: `tofu apply -target=...` per guest ([bootstrap step 2](bootstrap.md#2-guests-opentofu)), then base, apps and data restore (steps 3 to 7). The MACs in `private.yml` stay, so the DHCP leases do too
5. AIDE baselines for the node and its guests (step 8)

## Add a node

1. `pveN_ip` in `network.yml`, the host in `inventory.yml` (`proxmox`), Proxmox installed and joined
2. PVE firewall and login-notify: `deploy-pve-firewall.yml`, `deploy-login-notify.yml` (both run on their own, not from `site.yml`)
3. Monitoring: a Homepage tile in `apps/homepage/services.yaml.j2` (Servers) and a `pve-hosts` target in `apps/prometheus/config/prometheus.yml.j2`, both by hand. Gatus picks it up from the inventory
4. Move guests onto it, see below
5. A fourth node changes the quorum math: with 4 nodes, losing 2 stops the cluster. Use an odd count or a QDevice

## Move a guest to another node

1. Migrate it in Proxmox first: `qm migrate <vmid> <node>` (VM, offline unless shared storage), `pct migrate <vmid> <node> --restart` (LXC)
2. Set its node in `guest_nodes`
3. `tofu plan -target=...` for that guest has to show no replace. The guests have `prevent_destroy`, so a plan that wants to recreate one stops, fix the state, don't remove the guard ([ADR 0005](adr/0005-prevent-destroy-on-stateful-vms.md))
4. Moving the IoT LXC means moving the WiFi card with it: `iot_node` follows `guest_nodes.iot`

## Remove a node

1. Move its guests away (above), or retire them
2. Shut it down, `pvecm delnode <name>` on a remaining node
3. Remove it from `inventory.yml`, `network.yml` (`pveN_ip`, `part_time_nodes`), `infra_routes` in `apps.yml` (its UI route), and the Homepage node tile in `apps/homepage/services.yaml.j2` (Servers)
4. Gatus follows the inventory. Prometheus lists the nodes by hand (`pve-hosts` in `apps/prometheus/config/prometheus.yml.j2`). Edit, then `just deploy-app prometheus` and `just deploy-app gatus`

## Resize a guest

- RAM, balloon, cores: `tofu/locals.tf`, then a targeted apply. A RAM change needs a cold stop and start of the guest
- Disk: grow only. `disk` in `tofu/locals.tf`, a targeted apply, then grow the partition and file system inside ([troubleshooting](troubleshooting.md#podman-apps))
- `tofu/README.md` and the README's VM table list the sizes, keep them in step
