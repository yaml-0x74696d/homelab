# 42. AIDE accepts package upgrades by itself, after checking them

Status: Accepted

## Context

- The pod VMs, ctl-1 and the LXCs install security updates on their own (unattended-upgrades, [0024](0024-ansible-run-os-updates.md)). Every one of them makes the next AIDE check alert, and every alert needs an `aide-accept.yml` run by hand
- `update.yml` accepts after its own upgrades, but only for a run it started itself. It doesn't see what unattended-upgrades changed in between
- Accepting without looking makes the alert worth nothing, accepting everything by hand makes me stop reading them

- Alternatives:
  - Keep accepting by hand (why not: most alerts are a package upgrade, I accept them without reading the paths)
  - Updates only through `update.yml`, unattended-upgrades off (why not: security fixes then wait for Saturday, and the hosts only update while the runner and every node are up)
  - `aide_accept=yes` on a schedule (why not: it takes whatever changed, a planted file as well)
  - Accept only what the package database explains and verifies (chosen)
- Why: an upgrade changes files a package owns, a break-in mostly changes files no package knows about

## Decision

The setup:
- `playbooks/aide-auto-accept.yml` with `roles/aide_auto_accept`, a Semaphore template that runs daily at `aide_auto_accept_time`, after the check and clear of the Saturday update. The template is made by hand like the others ([0031](0031-semaphore-on-a-single-board-computer.md)). The NixOS VMs aren't covered
- Per host, one at a time: hash check, the daily check timer paused, one `aide --update`, then a checker on the host reads the report. A host that errors is recorded and the run goes on, then ends red
- The host is accepted only if every changed path is owned by a package (`dpkg -S`, `rpm -qf`), that package was upgraded since the last accept (`dpkg.log`, `INSTALLTIME` in rpm) or installed since then from a configured repo, and it verifies clean (`dpkg --verify`, `rpm -V`, a changed conffile is not clean)
- `dpkg --verify` only knows checksums, so the report's detailed section is read as well: only content and times may differ, a changed perm, owner, link, ACL or xattr refuses the host
- The time zero is the accept time the controller records next to the hash, not a file time on the host
- A removed file that a package still owns fails its verify. A removed file nobody owns blocks the accept. More than 500 paths, or a report that doesn't match its own counts, never passes
- One failed rule leaves the host as it is for `aide-accept.yml`. The run lists the reasons, ntfy gets counts
- The swap is the existing one: `roles/aide`'s `accept.yml`, same hash on the controller ([0009](0009-aide-with-manual-accept.md))

- Enforced by: `roles/aide_auto_accept` (the checker in `files/`) and the hash compare in `roles/aide` before every accept

## Consequences

- Easier: the alerts that are left are the ones nothing explains
- Easier: unattended-upgrades stays as it is, security fixes still land the same day

- Harder: hosts whose packages have conffiles we template (ssh, chrony, rsyslog) never verify clean, their upgrades stay a manual accept
- Harder: generated files (initramfs, `modules.dep`) have no owner and block the accept, those hosts stay a manual accept

- Accepted: the proof is the host's own package database and logs. Root on the host can fake `dpkg` and `rpm` output, or write a package into the database and log. That is the same trust as the rest of AIDE: root on the host can also change the files it checks, only the database hash is held outside
- Accepted: a package installed from a configured repo counts like an upgrade. A repo origin is what `apt-cache policy` says, so a malicious package in a repo we already trust passes as well
- Accepted: the first run on a host has no accept time and waits for one manual accept
- Accepted: the daily run scans every host once more, up to 25 minutes on a PVE node

- Related: [0009](0009-aide-with-manual-accept.md) (AIDE), [0024](0024-ansible-run-os-updates.md) (updates), [0031](0031-semaphore-on-a-single-board-computer.md) (schedules)
