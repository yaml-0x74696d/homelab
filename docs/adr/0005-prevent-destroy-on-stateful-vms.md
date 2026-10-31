# 5. prevent_destroy on stateful VMs

Status: Accepted

## Context

- The Docker volumes (Postgres, SQLite, Redis) live on the VM disks
- NetBird's management database (SQLite) lives on its VM disk once NixOS is installed
- Some attribute changes make the provider replace a VM instead of updating it

- Alternatives:
  - Keep the state on the pool (why not: databases on CIFS are a bad idea, and Immich doesn't support network shares for its database)
  - No guard, just read every plan carefully (why not: one wrong apply wipes the databases)

## Decision

- The Docker VMs and the NetBird VM have `lifecycle { prevent_destroy = true }` (`tofu/vms.tf`)
- The storage LXC has no guard, because its data is on the host pool, not on the CT disk
- The log LXC has no guard either, its logs are on its own CT disk
- Disk and hardware settings (discard, ssd, ballooning) are chosen so they can change in place, without a rebuild
- Enforced by: `prevent_destroy` itself, OpenTofu refuses any plan that would destroy a guarded VM

## Consequences

- Easier: a change that would force a replace fails at plan time instead of wiping data

- Harder: a planned rebuild means removing the guard by hand and restoring from PBS

- Accepted: one extra rule on top: never apply a plan that shows destroy/recreate on a VM or a disk

- The way back after a loss is PBS: the daily database dumps and archives (`roles/pbs`)

- Related: [0001](0001-tofu-and-cloud-init-for-vms.md) (OpenTofu), [0004](0004-mergerfs-instead-of-zfs.md) (pool vs local disks)
