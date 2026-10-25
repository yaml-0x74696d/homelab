# samba

- SMB shares and Time Machine on the pool, firewalled to the LAN with ufw
- Every share has its own group and its own scoped service user. The admin user is in every group

## Runs on

- The storage LXC (CT 300), in the second play of `deploy-storage.yml`, after `mergerfs` on pve-3
- The pool reaches the CT as a bind mount at `storage_root` (`/srv/storage`)

## How it works

1. Checks that `storage_root` is a mount point, and stops if it isn't (the pool or the CT mount is missing)
2. Creates one group per share, with GID `samba_gid_base` + the share's position in the list
3. Creates the admin user: UID `samba_admin_uid`, member of every share group, no login shell
4. Creates the service users: UID `samba_svc_uid_base` + position, their share as primary group, no login shell
5. Renders `smb.conf` and validates it with `testparm -s` before it's written
6. Sets the SMB passwords from the vault (`smb_passwords[<user>]`) through stdin, so they never show up in a shell or in `ps`. Only for users that `pdbedit -L` doesn't list yet
7. ufw: deny incoming, allow outgoing, and from the LAN only SSH (rate-limited), 445 and 139

## Shares (`samba_shares` in group_vars `storage.yml`)

| Share | Used by |
|---|---|
| backups | backup |
| iso | PVE |
| media | Jellyfin and LAN clients |
| nextcloud | Nextcloud |
| documents | Paperless |
| photos | Immich |
| homelab | Admin only |
| timemachine | Admin only |

- `valid users` and `write list` are the share's group, with `force group` on every share
- Files get mode `0660`, folders `2770` (setgid, group only)
- `map to guest = never`, `server min protocol = SMB3`, `smb encrypt = desired`
- `.DS_Store` files are blocked (vetoed)

## Time Machine

- A share with `time_machine: true` gets `vfs_fruit` and `streams_xattr`. The Apple settings are set globally
- `fruit:time machine max size` caps the backup so it can't fill the pool (`tm_size`, default 1 TB)

## Settings

| Variable | Default | What |
|---|---|---|
| `samba_rotate_passwords` | `false` | Set to `true` for one run to push the vault passwords to existing users |
| `samba_shares`, `samba_gid_base` | group_vars | Shared with `mergerfs`, which creates the share folders |
| `samba_admin_uid` | 3000 | UID of the admin user |
| `samba_svc_uid_base` | 3101 | First UID for the service users |
| `samba_min_protocol` | `SMB3` | Oldest SMB version allowed |
| `samba_max_log_size` | 1000 | KB per log file |
| `samba_tm_size_default` | `1T` | Time Machine cap when a share sets no `tm_size` |
| `samba_manage_ufw` | `true` | `false` leaves the firewall alone |
| `samba_lan` | `lan_cidr` | The network that may connect |

## Notes

- The UIDs are pinned, so a rebuilt CT keeps the same ownership
- New shares only go at the end of the list. The position sets the GID, so reordering changes ownership
- A password changed in the vault only reaches existing users with `-e samba_rotate_passwords=true` (for one run)
- The mounts on the Docker VMs (`docker_app_cifs`) map the files to the container's UID, not to these UIDs

## Related

- `mergerfs` role (the pool and the share folders), `docker_app` (the CIFS clients)
- [ADR 0004: mergerfs instead of ZFS](../../../docs/adr/0004-mergerfs-instead-of-zfs.md)
- [ADR 0017: SMB from the storage LXC to the Docker VMs](../../../docs/adr/0017-smb-shares-to-docker-vms.md)
