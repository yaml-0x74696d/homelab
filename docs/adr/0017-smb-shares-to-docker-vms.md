# 17. SMB from the storage LXC to the Docker VMs

Status: Accepted

## Context

- The bulk data (media, Nextcloud files, documents, photos) lives on the mergerfs pool on pve-3 ([0004](0004-mergerfs-instead-of-zfs.md))
- The apps run on the Docker VMs, mostly docker-3
- The pool already had Samba shares and scoped users for the LAN (Time Machine, ISO images, admin access)
- Databases must not live on a network share ([0005](0005-prevent-destroy-on-stateful-vms.md))

- Alternatives:
  - NFS (why not: CIFS via the Samba CT reuses the running shares + scoped users). It's still the fallback for the photos share if Immich misbehaves on CIFS
  - Bind mounts (why not: only work for guests on pve-3 itself)
  - iSCSI (why not: a block device, only one consumer per LUN)
  - A storage VM with the disk controller passed through (why not: pve-3 has a single controller, shared by the host disk and the data disks)

## Decision

The server (`roles/samba`):
- Samba runs in the unprivileged storage CT 300 (`.150`)
- The pool is bind-mounted into it at `storage_root` (`/srv/storage`)
- One share per consumer, each with its own scoped service user (`samba_shares` in `group_vars/all/storage.yml`):

  | Share | Used by |
  |---|---|
  | `nextcloud` | Nextcloud |
  | `documents` | Paperless |
  | `photos` | Immich |
  | `backups` | backup |
  | `iso` | PVE |
  | `media` | Jellyfin and LAN clients |
  | `homelab`, `timemachine` | Admin only |

- UIDs and GIDs are pinned: `samba_admin_uid`, `samba_svc_uid_base + index`, `samba_gid_base + index`
- Security settings: `server min protocol = SMB3`, `smb encrypt = desired`, `map to guest = never`
- ufw only allows 445/139 from the LAN

The clients (`docker_app_cifs` in `roles/docker_app`):
- Credentials in `/etc/cifs/<share>.creds` (mode `0600`)
- An fstab `cifs` entry with `vers=3.1.1` and `mfsymlinks,nofail,_netdev`
- `uid`/`gid` on the mount are set to the container's user
- Mounted under `cifs_mount_root` (`/srv/<share>`, Nextcloud's extra shares as `/srv/nc-<share>`), while the databases stay on the VM disk
- Extra options per app:
  - Nextcloud uses `nobrl` (no SMB byte-range locks)
  - Nextcloud only sees the photos read-only (`ro`), because Immich owns that library

- Enforced by: the Samba role first checks that `storage_root` really is a mount point, and `testparm -s` validates `smb.conf` before it's written

## Consequences

- Easier: one way to share everything. LAN clients, Time Machine and the Docker VMs all use the same shares and users
- Easier: each app only sees its own share, with its own credentials

- Harder: the UID/GID on the mount must match the user inside the container (Nextcloud 33, Paperless 1000), or writes fail
- Harder: `samba_shares` can only be added to at the end, because the position in the list sets the GID

- Accepted: Immich doesn't officially support its library on CIFS (atomic moves, permissions). Its database stays local, and NFS is the fallback (open issue)
- Accepted: because of `nofail`, a host still boots when the storage CT is down. But then an app can start on an empty mount point (the Podman plan adds a `findmnt` start gate for that, [0021](0021-podman-quadlets.md))

- Related: [0002](0002-generic-docker-app-role.md) (`docker_app_cifs`), [0004](0004-mergerfs-instead-of-zfs.md) (pool), [0005](0005-prevent-destroy-on-stateful-vms.md) (DBs stay local), [0021](0021-podman-quadlets.md) (mount gate)
