# aide

- Builds a file integrity database and checks it daily with a timer
- Sends an ntfy alert with counts only
- Uses Debian's rule set, plus excludes per inventory group for files that change all the time

## Runs on

- docker_hosts, proxmox, lxc_containers (`playbooks/aide.yml`)
- The NetBird box does the same as a Nix module: `nixos/netbird/aide.nix` + `nixos/aide-accept.sh`

## How it works

1. Installs `aide`, adds `/etc/aide/aide.conf.d/99_homelab_excludes` and `30_homelab_rsyslog` and runs `--config-check`
2. Checks the local database against the recorded hash (`tasks/verify.yml`) before anything else
3. First run only: `aide --init` hashes the whole system (async)
4. Handlers then move `aide.db.new` to `aide.db` and record its SHA256 on the controller
5. `meta: flush_handlers` runs right after, so the baseline is active before the timer exists
6. Installs `/usr/local/sbin/aide-check` with `aide-check.service` and `.timer`
7. Masks Debian's `dailyaidecheck.timer`. Ours runs at midday and pushes to ntfy instead of sending a mail at night

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
- Yes: the new database is swapped in, and its SHA256 is written to `ansible/aide/<host>.sha256` on the controller
- Anything else: the old baseline stays the reference
- If it's not your change, don't accept. Find out what happened first

## Security

- The SHA256 of the accepted database lives on the controller, not on the host
- `aide.yml` and every accept check that the local database matches the recorded hash, so an attacker with root can't quietly swap it
- A mismatch stops the run. Treat it as an incident and compare with the last PBS snapshot
- The check script is mode `0700`, because it holds the ntfy token
- The `<host>.sha256` files are specific to each host, so they're gitignored in this repo. The live repo commits them

## Settings

| Variable | Default | What |
|---|---|---|
| `aide_check_time` / `aide_check_delay` | `*-*-* 12:00:00`, up to 30 min | When the check runs (group_vars `hosts.yml`, shared with NixOS) |
| `aide_excludes_by_group` | see below | Excludes per inventory group, rendered as `!<path>(/\|$)` |
| `aide_run_timeout` / `aide_run_poll` | 3600 s / 30 s | Limits for `--init` and `--update` |
| `aide_check_nice` / `aide_check_io_class` | 19 / idle | Priority of the check |
| `aide_report_lines` | 150 | Diff lines shown on accept |
| `aide_checksum_dir` | `ansible/aide` | Where the hashes are stored on the controller |
| `ntfy_url`, `ntfy_token`, `ntfy_timeout` | group_vars | Shared ntfy settings. With an empty URL the check still runs, but nothing is pushed |

## Excluded paths

- All hosts: `/run` (tmpfs, rebuilt on every boot and daemon-reload), ansible's temp dirs (`/root/.ansible*`, `~admin/.ansible`), `/var/lib/rsyslog` (read position, queue) and `/var/log/remote` (the log LXC's received logs)
- docker_hosts: `/var/lib/docker`, `/var/lib/containerd`, `apps_root` and `/opt/stacks` (live apps until the podman migration), the CIFS mount root, the PBS staging folder
- proxmox: `/etc/pve` (pmxcfs), `/var/lib/pve-cluster`, rrdcached, `/var/lib/vz`, and on pve-3 the pool, its disks and the PBS datastore
- lxc_containers: the pool bind mount

## Notes

- `30_homelab_rsyslog` tells Debian's rsyslog rule our file names (`messages`, `secure`, `maillog`, `cron`, `boot.log`), so growing and rotated logs aren't reported (`aide_rsyslog_logfiles`)
- Accept after every update (`aide-accept.yml`), or tomorrow's push repeats the same changes
- The excludes need care (Docker, logs), or the alerts get noisy
- Build the baseline after the host is hardened, not before

## Related

- [ADR 0009: AIDE with manual accept](../../../docs/adr/0009-aide-with-manual-accept.md)
- `nixos/netbird/aide.nix` (NetBird box)
