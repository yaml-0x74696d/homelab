# journald

- The journal lives in RAM only (`Storage=volatile`). The history on disk is rsyslog's files (roles/rsyslog)
- Rate limits so one noisy service can't flood the logs

## Runs on

- All guests and ctl-1 (`pod_vms`, `podman_hosts`, `lxc_containers`), in `playbooks/base.yml`
- Not the pve nodes: they keep a persistent journal with a size cap (`playbooks/journald.yml`)

## How it works

1. Writes `/etc/systemd/journald.conf.d/10-journald.conf`
2. Removes the disk size cap (`10-size.conf`, used by `journald.yml` on the pve nodes) and, when volatile, `/var/log/journal`
3. Restarts journald when something changed

## Settings

Set in `group_vars/all/base.yml`, shared with `nixos/base`.

<!-- settings:start -->
| Variable | Default | What |
|---|---|---|
| `journald_storage` | - | `volatile` (default), `persistent` keeps the journal on disk |
| `journald_runtime_max_use` | - | RAM cap for the journal, default 100M |
| `journald_rate_limit_interval` | - | Window for the rate limit, default 30s |
| `journald_rate_limit_burst` | - | Messages per service and window before drops, default 10000 |
<!-- settings:end -->

## Notes

- `journalctl -b -1` (previous boot) has nothing. Use `/var/log/messages` or the log LXC
- `ForwardToSyslog=no`: rsyslog reads the journal directly (imjournal)

## Related

- [ADR 0022: central logging with rsyslog over RELP](../../../docs/adr/0022-central-logging-relp.md)
- `rsyslog` role (the files on disk)
