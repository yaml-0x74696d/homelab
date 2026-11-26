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
2. `aide --update`, one scan: report and new database. Exit 0 = nothing changed, done
3. `files/aide-auto-accept-check` runs on the host (`python3 -c`, nothing is left behind) with the report on stdin and answers with json: accept yes or no, the reasons, the packages
4. Yes: `roles/aide`'s `tasks/accept.yml` swaps the database in and writes the new hash on the controller, the same as `aide-accept.yml`
5. No: nothing is touched, the new database is dropped on the next scan
6. The last play prints every host that waited with its reasons, and pushes counts to ntfy. A day without changes sends nothing

## The rules

The checker takes the paths from the Added, Removed and Changed sections of the report. If they don't add up to the summary counts, or there are more than `aide_auto_accept_max_paths`, it refuses. Every path then has to pass:

1. Owned by a package: `dpkg-query -S` / `rpm -qf` (a path through a merged-`/usr` link is retried with its dir resolved). A removed file has no owner, so its dir's owner has to explain it
2. That package was installed or upgraded since the baseline. Time zero is the mtime of `/var/lib/aide/aide.db`, which is when the last accepted scan finished
3. That package verifies clean: `dpkg --verify <pkg>` / `rpm -V <pkg>`. A package with no md5sums can't be verified, so it fails. A changed conffile counts as not clean, also one we template ourselves
4. A changed directory only needs an owner from rule 2: its entries are in the report on their own

At least one package has to be verified, else there is nothing the accept rests on.

Where the "upgraded since" comes from:
- Debian: `/var/log/dpkg.log*`, rotated files included. dpkg writes it for every unpack, so it also catches `dpkg -i` and unattended-upgrades, which apt's `history.log` misses or splits over files. dpkg has no install time of its own, file mtimes under `/var/lib/dpkg/info` are touched too easily
- EL: `INSTALLTIME` in the rpm database. It is a field of the package itself, no log to rotate away, and `dnf history` only knows what dnf did

## Settings

| Variable | Default | What |
|---|---|---|
| `aide_auto_accept_max_paths` | `500` | More changed paths than this always wait for a person |
| `aide_auto_accept_removed` | `true` | A removed path is explained by an upgraded owner of its dir. `false`: a removed path blocks the accept |
| `aide_auto_accept_ignore` | `[]` | Regexes of paths that need no owner (initramfs, `modules.dep`, dpkg's own db). Empty means every path needs one. Add one only after the run output showed it |
| `aide_auto_accept_reason_lines` | `50` | Reasons printed per host |
| `aide_auto_accept_hosts` | lxc_containers + pod_vms + podman_hosts + proxmox | Hosts the summary covers |
| `aide_auto_accept_ntfy_title` | `homelab aide` | ntfy title |
| `aide_auto_accept_ntfy_headers` | Title + Bearer `ntfy_token` if set | Headers for the push |
| `aide_run_timeout` / `aide_run_poll`, `aide_checksum_dir` | `roles/aide` | Limits for the scan, where the hashes live |
| `ntfy_url`, `ntfy_token`, `ntfy_timeout` | group_vars | Shared ntfy settings, an empty URL sends nothing |

## Notes

- Expect many hosts to wait at first: generated files (initramfs, `modules.dep`, ca-certificates links) have no owner, and a package whose conffile we changed never verifies clean. The reasons show which. The first is a candidate for `aide_auto_accept_ignore`, the second stays manual
- `update.yml` accepts after its own upgrades without this. This run is for what unattended-upgrades changed
- No Gatus heartbeat: `gatus_semaphore_templates` needs the template's id, which only exists after the template is made by hand. Add `{ name: aide-auto-accept, id: <id>, heartbeat: "{{ heartbeat_daily }}" }` there and a `gatus_push` play to get one
- Paths and reasons stay in the run log. ntfy only gets counts (ntfy.sh is a public relay)
- A package changed on purpose by hand isn't an upgrade: it waits for `aide-accept.yml`
- Don't schedule it while `update.yml` runs (Saturday 14:00, about two hours): both scan and swap the same database

## Related

- [ADR 0042: AIDE auto-accept after package upgrades](../../../docs/adr/0042-aide-auto-accept-after-package-upgrades.md), [ADR 0009](../../../docs/adr/0009-aide-with-manual-accept.md)
- `roles/aide` (`verify.yml`, `accept.yml`), `playbooks/aide-accept.yml` (manual)
