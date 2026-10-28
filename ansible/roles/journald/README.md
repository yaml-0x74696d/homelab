# journald

- The journal lives in RAM only (`Storage=volatile`). The history on disk is rsyslog's files (roles/rsyslog)
- Rate limits so one noisy service can't flood the logs

## Runs on

- All guests (`docker_hosts`, `lxc_containers`), in `playbooks/base.yml`
- Not the pve nodes: they keep a persistent journal with a size cap (`playbooks/journald.yml`)

## How it works

1. Writes `/etc/systemd/journald.conf.d/10-journald.conf`
2. Makes sure there's no disk size cap (`10-size.conf`, used by `journald.yml` on the pve nodes)
3. Restarts journald when something changed

## Settings

| Variable | Default | What |
|---|---|---|
| `journald_storage` | `volatile` | `persistent` keeps the journal on disk |
| `journald_runtime_max_use` | `100M` | RAM cap for the journal |
| `journald_rate_limit_interval` | `30s` | Window for the rate limit |
| `journald_rate_limit_burst` | 10000 | Messages per service and window before drops |

## Notes

- `journalctl -b -1` (previous boot) has nothing. Use `/var/log/messages` or the log LXC
- `ForwardToSyslog=no`: rsyslog reads the journal directly (imjournal)
