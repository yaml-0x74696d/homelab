# aide_auto_accept

- Accepts a host's AIDE changes by itself, but only when installed packages explain every one of them and each verifies clean
- Anything else is left for `aide-accept.yml`, the run output says why
- Doesn't upgrade anything: unattended-upgrades and `update.yml` do that ([ADR 0042](../../../docs/adr/0042-aide-auto-accept-after-package-upgrades.md))

## Runs on

- pod_vms, podman_hosts, proxmox, lxc_containers (`playbooks/aide-auto-accept.yml`), one host at a time, only the hosts `roles/reach` found up
- Semaphore, daily after the check, by hand from the controller. `-l <host>` works
- Debian (dpkg) and EL (rpm), picked by what is on the host. The NixOS VMs are out of scope (`nixos/aide-accept.sh`). The rest of this repo is Debian only today ([bootstrap.md](../../../docs/bootstrap.md#guests-on-el10-what-changes)), the rpm side is untested

## How it works

1. Checks the AIDE database against the recorded hash (`roles/aide`, `tasks/verify.yml`), a mismatch stops that host like everywhere else
2. Pauses the `aide-check` timer and waits if a check is running, like `roles/update`. The timer starts again at the end, also after a failure
3. `aide --update`, one scan: report and new database. Exit 0 = nothing changed, done
4. `files/aide-auto-accept-check` runs on the host (`python3 -c`, nothing is left behind) with the report on stdin and `--since` = the accept time from the controller. It answers with json: accept yes or no, the reasons, the packages
5. Yes: `roles/aide`'s `tasks/accept.yml` swaps the database in and writes the new hash and accept time on the controller, the same as `aide-accept.yml`
6. No: nothing is touched, the new database is dropped on the next scan
7. Anything that fails in steps 2 to 5 is recorded as `error` for that host, the run goes on with the others. The last play prints every host that waited or failed with its reasons, pushes counts to ntfy, then fails the run if a host had an error. A day without changes sends nothing

## The rules

The checker takes the paths from the Added, Removed and Changed sections of the report. If they don't add up to the summary counts, or there are more than `aide_auto_accept_max_paths`, it refuses. Every path then has to pass:

1. Changed entries: the report's detailed section is read. Only content and times may differ (checksums, size, block count, mtime, ctime, atime, inode). A change of perm, uid, gid, link target, link count, ACL, xattr or SELinux label refuses the host, also on a directory. A changed path without a detail block refuses too
2. Owned by a package: `dpkg-query -S` / `rpm -qf` (a path through a merged-`/usr` link is retried with its dir resolved). A file in `/var/lib/dpkg/info/<pkg>[:arch].<ext>` belongs to `<pkg>`
3. That package was upgraded since the last accept, or installed since then from a configured repo. Debian: `apt-cache policy` lists the installed version with an origin other than `/var/lib/dpkg/status`. EL can't tell an install from an upgrade, so there every package needs a repo (`dnf repoquery --installed`, not `@commandline`)
4. That package verifies clean: `dpkg --verify <pkg>` / `rpm -V <pkg>`. A package with no md5sums can't be verified, so it fails. A changed conffile counts as not clean, also one we template ourselves
5. A removed file a package still owns is checked like any other path: the package is verified and the missing file fails it. A removed file nobody owns blocks the accept, unless `aide_auto_accept_removed` lets its dir's upgraded owner explain it
6. A changed directory needs an upgraded owner (and rule 1), its entries are in the report on their own. dpkg's own dirs under `/var/lib/dpkg` only need a package upgraded since the last accept

At least one package has to be verified, else there is nothing the accept rests on. Without a recorded accept time (`<host>.accepted`, written by every accept) the host is refused: accept it once by hand.

Where "upgraded since" comes from:
- Debian: `/var/log/dpkg.log*`, rotated files included. dpkg writes it for every unpack, so it also catches `dpkg -i` and unattended-upgrades, which apt's `history.log` misses or splits over files. dpkg has no install time of its own, file mtimes under `/var/lib/dpkg/info` are touched too easily
- EL: `INSTALLTIME` in the rpm database. It is a field of the package itself, no log to rotate away, and `dnf history` only knows what dnf did
- Time zero: the accept time on the controller, not the mtime of `aide.db` on the host (root can set that)

## Settings

| Variable | Default | What |
|---|---|---|
| `aide_auto_accept_max_paths` | `500` | More changed paths than this always wait for a person |
| `aide_auto_accept_removed` | `false` | A removed file nobody owns blocks the accept. `true`: an upgraded owner of its dir can explain it |
| `aide_auto_accept_ignore` | `[]` | Regexes of paths that need no owner, matched against the whole path. Empty means every path needs one. Add one only when you know what writes it and why it is harmless |
| `aide_auto_accept_wait_retries` / `aide_auto_accept_wait_delay` | `60` / `30` | How long to wait for a running daily AIDE check (tries, seconds) |
| `aide_auto_accept_reason_lines` | `50` | Reasons printed per host |
| `aide_auto_accept_hosts` | lxc_containers + pod_vms + podman_hosts + proxmox | Hosts the summary covers |
| `aide_auto_accept_ntfy_title` | `homelab aide` | ntfy title |
| `aide_auto_accept_ntfy_headers` | Title + Bearer `ntfy_token` if set | Headers for the push |
| `aide_run_timeout` / `aide_run_poll`, `aide_checksum_dir` | `roles/aide` | Limits for the scan, where the hashes live |
| `ntfy_url`, `ntfy_token`, `ntfy_timeout` | group_vars | Shared ntfy settings, an empty URL sends nothing |

## Notes

- Expect many hosts to wait at first: files a package script generates (initramfs, `modules.dep`, `.pyc`, ca-certificates links) have no owner, and a package whose conffile we changed never verifies clean. The reasons show which. Those hosts get `aide-accept.yml`. Don't ignore a generated path just to make the run green, it is also where something unwanted would hide
- `update.yml` accepts after its own upgrades without this. This run is for what unattended-upgrades changed
- No Gatus heartbeat: `gatus_semaphore_templates` needs the template's id, which only exists after the template is made by hand. Add `{ name: aide-auto-accept, id: <id>, heartbeat: "{{ heartbeat_daily }}" }` there and a `gatus_push` play to get one
- Paths and reasons stay in the run log. ntfy only gets counts (ntfy.sh is a public relay)
- A package installed by hand from a local `.deb` has no repo origin: it waits for `aide-accept.yml`
- Don't schedule it while `update.yml` runs (Saturday 14:00, about two hours): both scan and swap the same database

## Related

- [ADR 0042: AIDE auto-accept after package upgrades](../../../docs/adr/0042-aide-auto-accept-after-package-upgrades.md), [ADR 0009](../../../docs/adr/0009-aide-with-manual-accept.md)
- `roles/aide` (`verify.yml`, `accept.yml`), `playbooks/aide-accept.yml` (manual)
