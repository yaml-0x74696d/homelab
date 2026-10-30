# 24. OS updates through one Ansible run

Status: Accepted

## Context

- The apt hosts are pve-1/2/3, docker-1/2/3 and the storage and log LXCs
- Only the docker VMs get unattended security updates (`vm-preparation.yml`), everything else waits for a manual run
- A kernel check via `uname -r` against `/boot` flags the LXCs every time, they have no kernel there
- Checking only the kernel misses services still running on an old libc or openssl
- With `force-confold` the package's new config lands as `*.dpkg-dist`, unnoticed
- Every upgrade makes the next AIDE check alert, on every host
- The pve nodes are a cluster. Updating one while another is down risks quorum

- Alternatives:
  - unattended-upgrades for all origins plus a reboot window (why not: no order across the pve nodes, no quorum check, pve upgrades nobody looked at)
  - A plain `apt dist-upgrade` playbook (why not: false reboot flags on the LXCs, kernel-only check, silent conffiles, one AIDE accept per host)
  - One Ansible run with checks and a summary (chosen)
- Why: one ordered run that stops at the first problem and tells me what's left to do, while pve reboots stay my decision

## Decision

The setup:
- `playbooks/update.yml` with `roles/update`, run by hand from the controller
- Three plays, one host at a time (`serial: 1`): `lxc_containers`, then `docker_hosts`, then `proxmox`. Guests first, so a bad package shows up before a node gets it
- Explicit groups, not `all`: the NetBird VM updates through Nix ([0008](0008-nixos-for-the-dmz-box.md))

How it runs per host:
1. pve nodes: `pvecm status` must say `Quorate: Yes` (`update_check_quorum`)
2. AIDE: pause the daily `aide-check` timer (started again at the end, also after a failure), verify the database hash, then `aide --check`
3. `apt dist-upgrade` with autoremove and `force-confdef,force-confold`. pve needs dist-upgrade, plain upgrade holds back kernel, qemu and zfs
4. `needrestart -r a` restarts every service still on old libraries. The LXCs skip its kernel check (`update_check_kernel`). pve nodes: quorum is checked again after the restarts
5. New `*.dpkg-dist`, `*.dpkg-new` and `*.ucf-dist` files in `/etc` are listed
6. AIDE: if step 2 was clean, `aide --update` and the new database is accepted (`roles/aide`, `tasks/accept.yml`). If not, it's left for `aide-accept.yml`
7. Never reboots. A new kernel or microcode, or `/run/reboot-required`, puts `REBOOT due` in the summary

How I hear about it:
- The last play prints one line per host: packages, restarts, reboot, stale services, new conffiles, AIDE state
- The same lines go to ntfy ([0019](0019-ntfy-single-alert-channel.md)), counts only. Service names and paths stay in the terminal
- A failed host stops the run and pushes an alert plus the summary so far, the hosts after it aren't touched

- Enforced by: the play order and the quorum checks in `playbooks/update.yml`

## Consequences

- Easier: one command updates every apt host and ends with a to-do list
- Easier: no false reboot flags, and stale services get restarted instead of running on until the next reboot
- Easier: an upgrade no longer means one AIDE accept per host

- Harder: still only runs when I run it
- Harder: `needrestart -r a` restarts `docker.service` on the docker VMs, and with it every container. The docker-ce upgrade did that already
- Harder: needrestart restarts pve services on the nodes too (pveproxy, pvedaemon, the HA services)

- Accepted: whatever changes on a host during the upgrade goes into the AIDE baseline without review. The clean check right before keeps that window short ([0009](0009-aide-with-manual-accept.md))
- Accepted: two full AIDE scans per host (check before, update after), so a full run takes about 2 hours, mostly on the pve nodes
- Accepted: kept configs drift from the package defaults until I merge the listed conffiles by hand

- Later: the podman hosts update their images with `podman auto-update` ([0021](0021-podman-quadlets.md)). This run only covers the OS

- Related: [0008](0008-nixos-for-the-dmz-box.md) (NixOS updates), [0009](0009-aide-with-manual-accept.md) (AIDE), [0019](0019-ntfy-single-alert-channel.md) (ntfy), [0021](0021-podman-quadlets.md) (image updates), [0025](0025-debian-guests-until-x86-64-v3.md) (Debian guests)
