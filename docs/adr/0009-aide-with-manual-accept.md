# 9. AIDE with manual accept

Status: Accepted

## Context

- I wanted to know when files on a server change outside of a deploy
- Every server is in scope: docker-1/2/3, pve-1/2/3, the storage and log LXCs and the NetBird VM
- Alerts go to ntfy.sh, a public service, so they must not leak paths

- Alternatives:
  - OSSEC/Wazuh (why not: too heavy, needs a server)
  - Tripwire (why not: open source version barely maintained)
  - osquery (why not: query tool, not a file integrity check)
  - Debian's own `dailyaidecheck` mail (why not: sends mail, no ntfy)
  - No integrity checks (why not: wouldn't notice a change)
- Why AIDE: small, in Debian and NixOS, no server needed

## Decision

Where it runs:
- Debian hosts: `roles/aide` through `playbooks/aide.yml`
- NetBird VM: `nixos/netbird/aide.nix`

When it runs:
- Daily at 12:00, plus a random delay of up to 30 minutes (`aide_check_time` / `aide_check_delay`, shared with Nix)
- With low priority (`nice 19`) and the idle I/O class, so it doesn't slow the host down
- Debian's own `dailyaidecheck.timer` is masked and replaced by `aide-check.timer`

What it skips (`aide_excludes_common` on every host, `aide_excludes_by_group` per inventory group):
- Every host: `/run`, `/var/log` (the central copy on the log LXC is the tamper protection, [0022](0022-central-logging-relp.md)), apt's caches and lists, node-exporter's textfiles, ansible's temp files
- Docker hosts: Docker data, the app folders, the CIFS mounts and cloud-init's per-boot state
- Proxmox hosts: `/etc/pve`, the pool, the PBS datastore, state that pve rebuilds itself (`/var/lib/lxc`, lxcfs, corosync, PBS job state, compiled firewall rules, `/etc/issue`) and all of `/dev`
- LXCs: `/dev/.lxc` (procfs), the storage LXC also the pool bind mount
- Login homes (`aide_login_homes`): history files only keep owner, mode and type watched
- Files rewritten by design (`aide_var_files`: systemd timer stamps, apt's daily stamps, DHCP leases): the same, owner, mode and type only
- `/etc/hosts` (`aide_content_files`): cloud-init rewrites it at boot, so content, owner and mode are watched, the times are not
- NetBird VM: only watches what an upgrade never touches (`/etc` content, SSH keys, `/var/lib/secrets`). autoUpgrade rewrites the system links every day, and Nix checks its store paths anyway

- Rule for new excludes: watch config and binaries, skip state a service rewrites on its own. The config behind each skipped path (`/etc/corosync`, `/etc/proxmox-backup`) stays watched

Alerts and accepting:
- The ntfy alert only has counts, the changed paths stay in the host's journal (`journalctl -u aide-check`)
- Changes are accepted by hand: `aide-accept.yml` (Debian) or `nixos/aide-accept.sh` (NetBird) shows the diff, asks, then activates the new database
- The SHA256 of every accepted database is stored on the controller (`ansible/aide/<host>.sha256`, a symlink into the Tresorit-synced private folder)

- Enforced by: every run and every accept first compares the host's database with the stored hash. A mismatch stops the playbook

## Consequences

- Easier: an attacker with root can't quietly swap the database. A mismatch stops the playbook, and then it's an incident: compare with PBS, check auditd, don't accept

- Harder: every apt upgrade or deploy that touches watched files means one accept run per host
- Harder: the excludes need tuning, or the alerts get noisy. The first check right after the baseline should be clean

- Accepted: `--init` hashes the whole system and takes minutes per host, so it runs async with `aide_run_timeout`
- Accepted: the baseline hashes are specific to each host, so they're gitignored here and synced offsite with the vault
- Accepted: `/dev` on the pve nodes is unwatched (VM disks, ISOs, USB and corosync IPC churn there daily), so a payload in `/dev/shm` or a planted device node goes unseen

- Related: `roles/aide`, [0008](0008-nixos-for-the-dmz-box.md)
