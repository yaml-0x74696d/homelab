# 9. AIDE with manual accept

Status: Accepted

## Context

- I wanted to know when files on a server change outside of a deploy
- Every server is in scope: docker-1/2/3, pve-1/2/3, the storage LXC and the NetBird box
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
- NetBird box: `nixos/netbird/aide.nix`

When it runs:
- Daily at 12:00, plus a random delay of up to 30 minutes (`aide_check_time` / `aide_check_delay`, shared with Nix)
- With low priority (`nice 19`) and the idle I/O class, so it doesn't slow the host down
- Debian's own `dailyaidecheck.timer` is masked and replaced by `aide-check.timer`

What it skips (`aide_excludes_by_group`, per inventory group):
- Docker hosts: Docker data, the app folders and the CIFS mounts
- Proxmox hosts: `/etc/pve`, the pool and the PBS datastore
- Storage LXC: the pool bind mount
- NetBird box: only watches what an upgrade never touches (`/etc` content, SSH keys, `/var/lib/secrets`). autoUpgrade rewrites the system links every day, and Nix checks its store paths anyway

Alerts and accepting:
- The ntfy alert only has counts, the changed paths stay in the host's journal (`journalctl -u aide-check`)
- Changes are accepted by hand: `aide-accept.yml` (Debian) or `nixos/aide-accept.sh` (NetBird) shows the diff, asks, then activates the new database
- The SHA256 of every accepted database is stored on the controller (`ansible/aide/<host>.sha256`)

- Enforced by: every run and every accept first compares the host's database with the stored hash. A mismatch stops the playbook

## Consequences

- Easier: an attacker with root can't quietly swap the database. A mismatch stops the playbook, and then it's an incident: compare with PBS, check auditd, don't accept

- Harder: every apt upgrade or deploy that touches watched files means one accept run per host
- Harder: the excludes need tuning, or the alerts get noisy. The first check right after the baseline should be clean

- Accepted: `--init` hashes the whole system and takes minutes per host, so it runs async with `aide_run_timeout`
- Accepted: the baseline hashes are specific to each host, so they're kept in the private repo and gitignored here

- Related: `roles/aide`, [0008](0008-nixos-for-the-dmz-box.md)
