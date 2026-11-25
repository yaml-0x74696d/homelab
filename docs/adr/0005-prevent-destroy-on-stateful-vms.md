# 5. prevent_destroy on stateful VMs

Status: Accepted

## Context

- The app databases (Postgres, SQLite, Redis) live on the VM disks
- NetBird's management database (SQLite) lives on its VM disk once NixOS is installed
- Some attribute changes make the provider replace a VM instead of updating it

- Alternatives:
  - Keep the state on the pool (why not: databases on CIFS are a bad idea, and Immich doesn't support network shares for its database)
  - No guard, read every plan carefully (why not: one wrong apply wipes the databases)

## Decision

- The pod VMs, the NetBird VM, edge and the HAOS VM have `lifecycle { prevent_destroy = true }` (`tofu/vms.tf`)
- The storage, log and IoT LXCs have no guard (`tofu/lxc.tf`):
  - storage: its data is on the host pool, not on the CT disk ([0017](0017-smb-shares-to-docker-vms.md))
  - log: the central history is a single copy anyway, the hosts keep 4 weeks locally ([0022](0022-central-logging-relp.md))
  - IoT: config is in git and the broker state is disposable ([0028](0028-iot-gateway-lxc.md))
- Disk and hardware settings (discard, ssd, ballooning) are chosen so they can change in place, without a rebuild
- The way back after a loss is PBS: the daily database dumps and archives (`roles/pbs`)
- Enforced by: `prevent_destroy` itself, OpenTofu refuses any plan that would destroy a guarded VM

## Consequences

- Easier: a change that would force a replace fails at plan time instead of wiping data

- Harder: a planned rebuild means removing the guard by hand and restoring from PBS

- Accepted: one extra rule on top: never apply a plan that shows destroy/recreate on a VM or a disk

- Related: [0001](0001-tofu-and-cloud-init-for-vms.md) (OpenTofu), [0004](0004-mergerfs-instead-of-zfs.md) (pool vs local disks), [0017](0017-smb-shares-to-docker-vms.md) (storage LXC), [0022](0022-central-logging-relp.md) (log LXC), [0028](0028-iot-gateway-lxc.md) (IoT LXC), [0030](0030-haos-vm-on-pve-3.md) (HAOS), [0032](0032-edge-vm-traefik-adguard-on-nixos.md) (edge)
