# login_notify

- Sends an ntfy alert on every SSH and Proxmox web login
- A small watcher daemon reads the journal. PAM isn't touched, so it can't lock anyone out

## Runs on

- proxmox (`playbooks/deploy-login-notify.yml`)
- The Docker VMs aren't covered, `hosts: all` in the playbook would add them

## How it works

- Installs `/usr/local/sbin/login-notify` (mode `0750`) and `login-notify.service`
- The script runs `journalctl -f -n0`, so it only follows new journal lines, nothing from before it started
- It looks for two kinds of lines:

  | Journal line | Alert |
  |---|---|
  | `Accepted … for …` (sshd) | `ssh — <line>` |
  | `pvedaemon[…] successful auth` | `pve web ui — <line>` |

- The alert is sent with curl to `ntfy_url`, with a bearer token if `ntfy_token` is set
- The script uses `set -uo pipefail` without `-e`, so a failed curl or a journal hiccup doesn't kill the watcher
- The service has `Restart=always` and `NoNewPrivileges=yes`
- A handler restarts the service when the script or the unit changes

## Alert path

- Outbound only: host → ntfy.sh → phone app. Nothing has to be reachable from the internet
- A self-hosted ntfy would stay LAN-only, and instant push on the iPhone needs a public server
- The `pbs` and `aide` roles send to the same `ntfy_url` / `ntfy_token`

## Settings

| Variable | Default | What |
|---|---|---|
| `login_notify_restart_sec` | 10 | Seconds before systemd restarts the watcher |
| `ntfy_url`, `ntfy_token`, `ntfy_timeout` | group_vars | Shared ntfy settings. With an empty URL the daemon runs but stays quiet |

- The match patterns are in `templates/login-notify.sh.j2`

## Notes

- The PVE web match depends on pvedaemon logging `successful auth`. Check it with `journalctl -u pvedaemon | grep -i 'successful auth'`
- The push carries the full journal line (user, source IP), unlike AIDE, which only sends counts

## Related

- [ADR 0019: ntfy.sh as the single alert channel](../../../docs/adr/0019-ntfy-single-alert-channel.md)
- `aide`, `pbs` roles (same ntfy target)
