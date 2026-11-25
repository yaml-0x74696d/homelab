# pbs

- Proxmox Backup client: dumps the databases first, then pushes the apps folder as an archive
- Only data: the VMs are rebuilt from OpenTofu + Ansible and the configs live in git. Only the volumes and databases can't be replaced
- Uses the file-level `proxmox-backup-client`, not vzdump VM images

## Runs on

- pod_vms (`playbooks/deploy-pbs.yml`)
- Target: PBS as a host package on pve-3, datastore `homelab` on a 100 GB thin LV (`/mnt/pbs`)
- pve-3 must be on while the backup runs

## How it works

- Adds the `pbs-client` apt repo (deb822, Proxmox release key) and installs `proxmox-backup-client` and `sqlite3`
- `/etc/pbs.env` (mode `0600`) holds the repository, the token secret and the server fingerprint
- Checks that each Podman postgres job names a Podman app (`app`), whose svc user it dumps as
- Installs `/usr/local/sbin/pbs-backup`, `pbs-backup.service` and a `.timer`
- Each run:
  1. Takes a lock
  2. Creates a fresh staging folder
  3. Dumps every database in `pbs_jobs`
  4. Pushes to PBS
  5. Wipes the staging folder
  6. Pushes a heartbeat to Gatus (after `backup ok`)
- The push sends these archives under the backup ID `<host>`:
  - `dumps.pxar`: the staging folder with the dumps
  - `podman-apps.pxar`: `podman_apps_root`, without the live database files, because the dumps replace them

## Dump types

| Type | How |
|---|---|
| `postgres` | `pg_dump --clean --if-exists` inside the container, user and database from the container's own env: `podman exec` as `svc-<app>` through `runuser` with its `XDG_RUNTIME_DIR` |
| `sqlite` | Online `.backup`, which is safe while the app is writing (unlike `cp`). A missing file is skipped, not an error |

- Every dump is checked to be non-empty, or the run fails

## Per host (`host_vars/`)

| Host | Databases | Left out |
|---|---|---|
| pod-1 | Authentik (Postgres), Gitea, Vaultwarden (SQLite) | nothing |
| pod-2 | Grafana, Gatus, Actual Budget (SQLite) | Prometheus TSDB (bulky, old metrics aren't worth keeping) |
| pod-3 | Nextcloud, Immich, Paperless (Postgres), Jellyfin, Linkding, Memos (SQLite) | Jellyfin cache and transcodes |

- The bulk data on the CIFS pool (photos, media, documents, files) isn't in here

## Safety

- `flock` on `/run/pbs-backup.lock`, so two runs never overlap
- `umask 077` and a staging folder with mode `0700`, because the dumps hold vault and SSO secrets
- The staging folder must be under `/var/backups/`, or the script refuses before it runs `rm -rf`
- An `EXIT` trap wipes the staging folder even when the run fails
- An `ERR` trap sends "backup failed" with the failing line to ntfy
- The heartbeat is a `POST` to Gatus' backend port on pod-2, the token comes from `/etc/pbs.env`, not from the command line. A failed push is only logged, the backup stays ok. Gatus alerts when it stays away longer than `heartbeat_daily`
- `TimeoutStartSec` (`pbs_timeout`) stops a stuck push (e.g. pve-3 only half up), so it can't hold the lock forever
- The token `backup@pbs!client` has the `DatastoreBackup` role on `/datastore/homelab` only. It can add backups and restore the groups it owns. The three hosts share it, so each can restore all three. It can't delete or prune

## Settings

| Variable | Default | What |
|---|---|---|
| `pbs_on_calendar` | `pbs_backup_time` (`*-*-* 20:00:00`) | When the backup runs (systemd OnCalendar), set in `schedules.yml` |
| `pbs_randomized_delay` | `pbs_backup_delay` (`20m`) | Random delay, so the three hosts don't start at once |
| `pbs_jobs` | `[]` | Databases to dump: `{name, type: postgres\|sqlite, container?, path?, data_dir?, app?}`, set in `host_vars`. sqlite `path` is under `podman_apps_root`, postgres needs `app` and runs `podman exec` as `svc-<app>` |
| `pbs_exclude` | `[]` | Extra excludes for `podman-apps.pxar`, set in `host_vars` |
| `pbs_datastore` | `homelab` | Datastore on the PBS server |
| `pbs_token_id` | `backup@pbs!client` | API token |
| `pbs_repository` | token@pve-3:port:datastore | Built from the values above |
| `pbs_id` | the hostname | Backup group, one per host |
| `pbs_timeout` | `1h` | Max run time |
| `pbs_token_secret`, `pbs_fingerprint` | vault | Token secret and server fingerprint |
| `pbs_ntfy_url`, `pbs_ntfy_token` | `ntfy_url`, `ntfy_token` | Where failure alerts go, empty = off |
| `pbs_heartbeat_url`, `pbs_heartbeat_timeout` | `gatus_push_url`, `gatus_push_timeout` | Gatus' backend port on pod-2, seconds per push |
| `pbs_heartbeat_path` | `gatus_push_path` | Push path, `{key}` is replaced by `pbs_heartbeat_key` |
| `pbs_heartbeat_key` | `<gatus_push_group>_backup-<host>` | Key of the host's external endpoint in Gatus |
| `pbs_heartbeat_token` | `gatus_push_token` (vault) | Push token, empty = no heartbeat in the script |
| `pbs_staging_dir`, `ntfy_timeout` | group_vars | Shared with other roles |
| `podman_apps_root`, `podman_svc_prefix` | group_vars | Shared with `roles/podman_app` |

## Server side (by hand, not in this role)

- Pruning and garbage collection are set in the PBS UI: GC daily, keep 7 daily / 4 weekly / 3 monthly
- With privilege separation, the user and the token both need the ACL. The token only gets what both have

## Notes

- The release key is downloaded from `enterprise.proxmox.com`, because the CDN serves a certificate for the wrong host (it's the same key)
- The client talks to pve-3's IP with the fingerprint directly. Traefik only sits in front of the web UI

## Related

- [ADR 0013: PBS file-level backups, VMs are cattle](../../../docs/adr/0013-pbs-file-level-backups.md)
- [ADR 0005: prevent_destroy on stateful VMs](../../../docs/adr/0005-prevent-destroy-on-stateful-vms.md)
- `aide` excludes the staging folder, `login_notify` / `aide` use the same ntfy target
