# aide

- Builds a file integrity database and checks it daily with a timer
- Sends an ntfy alert with counts only
- Uses Debian's rule set, plus excludes per inventory group for files that change all the time

## Runs on

- pod_vms, podman_hosts, proxmox, lxc_containers (`playbooks/aide.yml`)
- Only the hosts `roles/reach` found up in its first play. Hosts in `reach_optional_hosts` (the part-time nodes and their guests) may be off, the run still exits 0. Any other host that's down fails it
- The NixOS VMs (netbird, edge) do the same as a Nix module: `nixos/base/aide.nix` + `nixos/aide-accept.sh <host>`

## How it works

1. Installs `aide`, adds `/etc/aide/aide.conf.d/98_homelab_excludes` (before Debian's `99_aide_root` catch-all, the first matching rule wins) and runs `--config-check`
2. Checks the local database against the recorded hash (`tasks/verify.yml`) before anything else
3. Installs `/usr/local/sbin/aide-check` with `aide-check.service` and `.timer`
4. Masks Debian's `dailyaidecheck.timer`. Ours runs at midday and pushes to ntfy instead of sending a mail at night
5. First run only, last: `aide --init` hashes the whole system (async), so the baseline already contains the files above
6. Handlers then move `aide.db.new` to `aide.db` and record its SHA256 on the controller (`meta: flush_handlers`, right away)

## Daily check

- Runs `aide --check` and writes the full output to the journal (`journalctl -u aide-check`)
- Exit bits 1/2/4 mean added/removed/changed files. Then ntfy gets "changes on <host>" with the counts and the accept command
- Exit 14 and up means AIDE itself failed. Then ntfy gets "AIDE failed"
- Only the counts leave the host, the changed paths stay local (ntfy.sh is a public relay)
- Runs with low priority (`Nice=19`, idle I/O class)
- `Persistent=true` catches up on a missed run after downtime
- The service needs `dailyaidecheck-buildcache.service`, Debian's LVM rule cache, the same as Debian's own check

## Accepting changes

- Run `ansible-playbook playbooks/aide-accept.yml -l <host>` (one host at a time, `serial: 1`)
- It checks the hash, runs `aide --update`, shows the first `aide_report_lines` lines of the diff and asks you to type "yes"
- In Semaphore there's no prompt: the survey var `aide_accept=yes` accepts in the same run, the diff stays in the task log
- Yes: the new database is swapped in, and its SHA256 is written to `aide_checksum_dir/<host>.sha256` on the controller
- Anything else: the old baseline stays the reference
- If it's not your change, don't accept. Find out what happened first
- `playbooks/update.yml` accepts on its own, but only if the check right before the upgrade was clean (`roles/update`)
- `playbooks/aide-auto-accept.yml` (Semaphore, daily) accepts what package upgrades explain, see `roles/aide_auto_accept`. The rest waits for you
- All three use `tasks/accept.yml` for the swap

## Security

- The SHA256 of the accepted database lives on the controller, not on the host
- `aide.yml` and every accept check that the local database matches the recorded hash, so an attacker with root can't quietly swap it
- A mismatch (or a missing `<host>.sha256`) pushes "AIDE db mismatch on <host>" to ntfy, then stops the run. Treat it as an incident and compare with the last PBS snapshot
- The push comes from `tasks/verify.yml`, so `aide.yml`, `aide-accept.yml` and `update.yml` all send it. In `update.yml` the run-stopped alert follows
- The check script is mode `0700`, because it holds the ntfy token
- The `<host>.sha256` files are specific to each host, so they're gitignored and live in the offsite-synced private folder

## Hashes and sync

- ctl-1 holds the reference, `/srv/apps/semaphore/aide/<host>.sha256`. Semaphore's accept runs write there
- The controller's `ansible/aide/` and ctl-1's dir are kept the same by Syncthing, both ways. An accept on either side reaches the other within seconds
- Not synced: Syncthing's GUI (`127.0.0.1:8384` on ctl-0) shows the folder's state. A `.sync-conflict-…` file means both sides changed the same hash, keep the one that matches the host's db
- On ctl-1 the dir has ACLs for `admin_user` (Syncthing) and Semaphore's container user, a copy by hand needs no `sudo`
- Renaming a host: rename `<host>.sha256` on both sides, then accept on that host
- "database hash mismatch": the database changed outside an accept, or a copy is stale. Compare both copies first, then look at the host before accepting

## Accepting many hosts

- `aide-accept.yml` asks one host at a time (`serial: 1`). Each host writes its own `<host>.sha256`, so one run per host in parallel works: `aide-accept.yml -l <host>` in separate terminals

## Excluded paths

- All hosts: `/run` (tmpfs), ansible's temp dirs and payloads, `.cache` in the admin's and root's home, `aide.db.new`, `/var/log` (every line is on the log LXC already, see [ADR 0022](../../../docs/adr/0022-central-logging-relp.md)), `/var/lib/rsyslog`, apt's caches and lists, PackageKit's db, node-exporter's textfiles
- pod_vms: root and rootless podman storage, `/dev/shm`, the svc users' ansible payloads, `podman_apps_root` (`/srv/apps`, app data), the CIFS mount root, the PBS staging folder, cloud-init state (`/var/lib/cloud`, `/var/tmp/cloud-init`), `/dev/disk/by-uuid` (the cloud-init ISO gets a dated UUID)
- podman_hosts: root and rootless podman storage, `/dev/shm`, the svc users' ansible payloads, `podman_apps_root`, and on ctl-1 the Semaphore checkout (`semaphore_repo_dir`, kept current by `playbooks/repo-pull.yml`) and its `private_dir` copy (`semaphore_private_dir`, synced by `roles/ctl_base`), Syncthing's index db
- proxmox: `/etc/pve` (pmxcfs), `/var/lib/pve-cluster`, rrdcached, `/var/lib/vz`, state pve rebuilds itself (`/var/lib/lxc`, `/var/cache/lxc`, lxcfs, corosync, `/var/lib/proxmox-backup`, `/var/lib/pve-firewall`, replication state, smartmontools, `/etc/issue`, `76pveproxy` from `datacenter.cfg`), all of `/dev`, and on pve-3 the pool, its disks and the PBS datastore
- lxc_containers: `/dev/.lxc` (procfs), the pool bind mount, `/var/lib/mosquitto` (broker persistence)

## Settings

<!-- settings:start -->
| Variable | Default | What |
|---|---|---|
| `aide_check_time` | - | systemd OnCalendar of the check, `*-*-* 12:00:00` (group_vars schedules.yml, shared with nixos) |
| `aide_check_delay` | - | Random delay on top of it, up to `30min` (schedules.yml) |
| `aide_check_nice` | `19` | Nice of the check |
| `aide_check_io_class` | `idle` | IOSchedulingClass of the check |
| `aide_run_timeout` | `3600` | Seconds --init and --update may take |
| `aide_run_poll` | `30` | Seconds between async polls of --init and --update |
| `aide_checksum_dir` | see `defaults/main.yml` | Controller dir with the accepted db hashes, one \<host>.sha256 each. Default `$AIDE_CHECKSUM_DIR`, else `ansible/aide`. Semaphore sets the env var to its rw volume on ctl-1, the reference copy. On ctl-0 `ansible/aide` is a gitignored symlink into the offsite-synced private folder, pulled from ctl-1 (roles/ctl_base) |
| `aide_excludes_common` | see `defaults/main.yml` | Excludes on every host |
| `aide_excludes_by_group` | see `defaults/main.yml` | Excludes per inventory group, group name -> list of paths, rendered as `!<path>(/\|$)` |
| `aide_login_homes` | `['/home/{{ admin_user }}', /root]` | Homes with history files on the VarFile rule (see Notes), default the admin home and /root |
| `aide_history_files` | `\\.(bash_history\|lesshst\|viminfo\|python_history\|wget-hsts)` | Regex of the history file names in those homes |
| `aide_var_files` | see `defaults/main.yml` | Files rewritten by design: only owner, mode and type watched (VarFile) |
| `aide_content_files` | see `defaults/main.yml` | Rewritten with the same content: owner, mode and checksum watched, times not (ContentFile) |
| `aide_var_dirs` | see `defaults/main.yml` | Dirs whose files get replaced: owner and mode watched, times not (VarDir). Added and removed files still show |
| `aide_report_lines` | `150` | diff lines shown by aide-accept.yml on accept |
<!-- settings:end -->

Also from group_vars: `ntfy_url`, `ntfy_token`, `ntfy_timeout`, the shared ntfy settings. With an empty URL the check still runs, but nothing is pushed.

## Notes

- Login homes (`aide_login_homes`): shell/tool history files only keep owner, mode and type watched (`VarFile`), the home dir its owner and mode (`VarDir`). `.ssh` and the rc files keep the full rule
- Accept after every update (`aide-accept.yml`), or tomorrow's push repeats the same changes
- The excludes need care (container storage, logs), or the alerts get noisy
- Build the baseline after the host is hardened, not before

## Related

- [ADR 0009: AIDE with manual accept](../../../docs/adr/0009-aide-with-manual-accept.md)
- `nixos/base/aide.nix` (NixOS VMs)
