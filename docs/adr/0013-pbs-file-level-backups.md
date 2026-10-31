# 13. PBS file-level backups, VMs are cattle

Status: Accepted

## Context

- docker-1/2/3 can be rebuilt from OpenTofu + Ansible, and the app configs live in git
- The only state that can't be replaced: the app data volumes and the databases (plus the vault)
- There's no room for full VM images:
  - The PBS datastore is a 100 GB thin LV on pve-3's SSD
  - The thin pool has 337 GB, and 188 GB are already given out: 88 GB of guest disks + the 100 GB datastore

- Alternatives:
  - PVE vzdump VM images (why not: don't fit in the datastore)
  - Borg/Restic to the pool (why not: backups on the same disks as the data)
  - Keep no backups (why not: databases can't be rebuilt)
- Why: built into Proxmox, deduplication, web UI

## Decision

The setup:
- `proxmox-backup-client` on every Docker VM (`roles/pbs`, `deploy-pbs.yml`), not vzdump
- PBS runs as a host package on pve-3, with the datastore `homelab` at `/mnt/pbs`
- The client logs in with the token `backup@pbs!client`, which has the `DatastoreBackup` role on `/datastore/homelab` only
- Retention is set in the PBS UI: garbage collection daily, keep 7 daily / 4 weekly / 3 monthly

When and how it runs:
- A timer starts it every evening at 20:00 (`pbs_on_calendar`)
- A random delay of up to 20 minutes keeps the hosts apart (`pbs_randomized_delay`)
- Each run: dump the databases, push, then wipe the staging folder
- It pushes two archives:
  - `dumps.pxar`: the database dumps (Postgres `pg_dump --clean --if-exists`, SQLite online `.backup`, `influx backup`)
  - `apps.pxar`: everything in `apps_root`, except the live database files, caches and query logs

What each host backs up (`pbs_jobs` and `pbs_exclude` in `host_vars/docker-{1,2,3}.yml`):

| Host | Databases |
|---|---|
| docker-1 | Authentik (Postgres), Gitea, Vaultwarden, Home Assistant recorder (SQLite) |
| docker-2 | Grafana, Gatus, Homelable (SQLite), InfluxDB |
| docker-3 | Nextcloud, Immich, Paperless (Postgres), Jellyfin + library (SQLite) |

- Enforced by: the timer runs on its own, and a failed run or an empty dump sends an ntfy alert (`ERR` trap)

## Consequences

- Easier: small, deduplicated backups that restore straight into a rebuilt VM
- Easier: a new app with plain config files needs no backup change, `apps_root` is backed up by default

- Harder: a new app with a database needs a `pbs_jobs` entry. Without it, the live database file only lands in `apps.pxar` as a plain copy, which isn't crash-consistent
- Harder: a rebuild is `tofu apply` + Ansible + restore, more steps than restoring a VM image

- Accepted: bulk media on the CIFS pool (photos, media, documents, Nextcloud files) is not backed up
- Accepted: the Prometheus TSDB is skipped. It's bulky, and losing old metrics is fine
- Accepted: the token can write but not prune or delete. Pruning and garbage collection are set by hand on the server

- Related: [0001](0001-tofu-and-cloud-init-for-vms.md) (rebuild from code), [0004](0004-mergerfs-instead-of-zfs.md) (pool not backed up), [0005](0005-prevent-destroy-on-stateful-vms.md) (recovery path), [0019](0019-ntfy-single-alert-channel.md) (alerts)
