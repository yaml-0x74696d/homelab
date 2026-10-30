# update

- OS updates for the apt hosts, one host at a time
- Restarts services still running old libraries, never reboots
- Re-baselines AIDE after the upgrade, if nothing had changed before it
- Ends with one summary in the terminal and on ntfy

## Runs on

- `playbooks/update.yml`: lxc_containers, then docker_hosts, then proxmox
- Not the NetBird VM (NixOS, `system.autoUpgrade` + `nixos/update.sh`)

## How it works

1. pve nodes only: `pvecm status` must say `Quorate: Yes`
2. Pauses the `aide-check` timer and waits if a check is running. The timer starts again at the end, also after a failure
3. Checks the AIDE database against the recorded hash (`roles/aide`, `tasks/verify.yml`), then runs `aide --check`
4. Installs `needrestart` if it's missing
5. `apt dist-upgrade` with autoremove. pve needs dist-upgrade, plain upgrade holds back kernel, qemu and zfs
6. `needrestart -r a` restarts the services on old libraries, then a second run lists what's left. pve nodes: quorum is checked again after the restarts
7. Looks for `*.dpkg-dist`, `*.dpkg-new` and `*.ucf-dist` in `/etc`
8. AIDE: if the check in step 3 was clean and packages changed, `aide --update` and the new database is accepted (`roles/aide`, `tasks/accept.yml`)
9. Records the result per host. The last play prints it and pushes it to ntfy

## Settings

| Variable | Default | What |
|---|---|---|
| `update_cache_valid_time` | 3600 | Seconds before the apt cache is refreshed |
| `update_conffile_dirs` | `[/etc]` | Where to look for new package configs |
| `update_conffile_patterns` | dpkg-dist, dpkg-new, ucf-dist | What counts as one |
| `update_check_kernel` | `true` | needrestart's kernel check. `false` on the LXCs, they run the node's kernel |
| `update_check_quorum` | `false` | `true` in the pve play |
| `update_quorum_retries`, `update_quorum_delay` | 6, 10 | Tries and seconds for the quorum check after the restarts |
| `update_summary_hosts` | lxc_containers + docker_hosts + proxmox | Hosts the summary covers, in play order |
| `update_aide_wait_retries`, `update_aide_wait_delay` | 60, 30 | How long to wait for a running daily AIDE check (tries, seconds) |
| `update_ntfy_title` | homelab updates | ntfy title |
| `update_ntfy_headers` | Title + Bearer `ntfy_token` if set | Headers for every ntfy push |

## Reading the summary

- `REBOOT due`: new kernel or microcode, or `/run/reboot-required`. pve nodes: shut that node's guests down first
- `stale`: services needrestart doesn't restart on its own (dbus, logind, ...). Reboot or restart by hand
- `new conffiles`: we kept our config (`force-confold`), the package's version sits next to it. Merge by hand, then delete it
- `aide review, was dirty before`: something changed before the upgrade. Not accepted, run `aide-accept.yml` and look first

## Notes

- Two full AIDE scans per host: a full run takes about 2 hours, most of it on the pve nodes (up to 25 min per scan)
- A failed host stops the run and pushes an alert plus the summary of the hosts done so far. The hosts after it aren't touched
- ntfy only gets counts. Service names and paths stay in the terminal (ntfy.sh is a public relay)
- `needrestart -r a` on the docker hosts restarts `docker.service`, and with it every container. The docker-ce upgrade does that anyway
