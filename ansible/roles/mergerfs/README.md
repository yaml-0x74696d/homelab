# mergerfs

- Mounts the data disks, joins them into one pool and bind-mounts it into the storage CT
- About 11 TB from four plain ext4 disks of mixed size (3 + 3 + 3 + 2 TB)

## Runs on

- pve-3, in the first play of `deploy-storage.yml`. The second play runs `samba` in the storage CT
- pve-3 must be on, because it holds the pool and the PBS datastore

## How it works

1. Installs `mergerfs` and `fuse3`, and sets `user_allow_other` in `/etc/fuse.conf`
2. Mounts each disk by UUID (`storage_disks` in group_vars `storage.yml`) with `defaults,noatime`
3. Checks every disk with `mountpoint -q` before the pool goes up, so the pool never joins empty folders
4. Mounts the pool at `storage_pool_host` (`/mnt/storage/pool`), with the disk paths as branches
5. The pool's fstab line gets an `x-systemd.requires=<disk>` for each disk, so at boot the pool waits for the disks
6. The pool root belongs to the CT's mapped root user (`100000`)
7. Creates one folder per Samba share, setgid `2770`. The group is the mapped root + `samba_gid_base` + the share's position in the list

## Pool options

- `category.create=mfs`: new files go to the disk with the most free space
- `minfreespace=20G`: a disk with less than 20 GB free gets no new files
- Also: `cache.files=partial`, `dropcacheonclose=true`, `use_ino`, `allow_other`

## Settings

| Variable | Default | What |
|---|---|---|
| `mergerfs_options` | see Pool options | The full option string for the pool |
| `mergerfs_disk_opts` | `defaults,noatime` | Mount options for each disk |
| `mergerfs_require_disks` | `true` | Adds `x-systemd.requires` for each disk |
| `mergerfs_ct_root_uid` | `100000` | The unprivileged CT's root user, as seen from the host |
| `storage_disks`, `storage_pool_host`, `samba_shares`, `samba_gid_base` | group_vars | Shared with the other storage roles |

## Notes

- No parity, a dead disk loses its files ([ADR 0004](../../../docs/adr/0004-mergerfs-instead-of-zfs.md))
- Configs and databases are backed up by PBS. Bulk media on the pool isn't, on purpose (it can be ripped or synced again)
- The share folders are created here, as the real root user, because the unprivileged CT can't chgrp on the FUSE mount
- Order on the first run: `--limit pve-3`, then `tofu apply` (CT 300), then `--limit storage`
- The disk UUIDs are placeholders (`CHANGE_ME-…`) in this repo

## Related

- [ADR 0004: mergerfs instead of ZFS](../../../docs/adr/0004-mergerfs-instead-of-zfs.md)
- `samba` role (shares the pool), `docker_app` (CIFS mounts on the Docker VMs)
- The PBS datastore is a separate thin LV on the SSD, not on this pool
