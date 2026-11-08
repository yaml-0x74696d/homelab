# rsyslog

- Log files on every guest (`/var/log/messages`, `secure`, `cron`, `maillog`, `boot.log`)
- Everything is also sent to the log LXC (CT 301) over RELP. A message only leaves the queue once the server has saved it
- On the log LXC (`rsyslog_mode: server`, set in `host_vars/log.yml`) it also receives and writes one directory per host

## Runs on

- All guests (`docker_hosts`, `lxc_containers`), in `playbooks/base.yml`. Not the pve nodes
- The NetBird VM gets the same from `nixos/base/logging.nix`, edge follows

## How it works

1. Installs `rsyslog` and `rsyslog-relp`
2. Renders `/etc/rsyslog.conf`: reads the journal with `imjournal` (state file, rate limit; the first start begins at the end of the journal, not its oldest entry) and writes those files. `imuxsock` is loaded without the system socket, only for extra sockets packages add (postfix's chroot on the LXCs)
3. Renders `/etc/logrotate.d/rsyslog` for those files
4. Client: `/etc/rsyslog.d/90-forward.conf` sends everything with `omrelp`. A disk-assisted queue holds messages while the log LXC is down and survives a reboot
5. Server: `10-server.conf` takes RELP on `log_relp_port` and writes `<rsyslog_remote_dir>/<host>/<program>.log`. The host name comes from the sender's IP through a lookup table built from the inventory (`hosts.json`), not from what the message claims. Unknown IPs go to `unknown/`
6. Checks the whole config with `rsyslogd -N1` before the restart

## Settings

| Variable | Default | What |
|---|---|---|
| `rsyslog_mode` | `client` | `server` on the log LXC |
| `rsyslog_server`, `rsyslog_relp_port` | `log_ip`, `log_relp_port` | Where clients send to |
| `rsyslog_journal_rate_interval` / `_burst` | 600 / 20000 | imjournal rate limit |
| `rsyslog_queue_max_disk` | `1g` | Disk cap for the client queue (`group_vars/all/base.yml`) |
| `rsyslog_resume_interval` | 30 | Seconds between reconnects (`group_vars/all/base.yml`) |
| `rsyslog_local_rotate` | 4 | Weeks of local files on each host (`group_vars/all/base.yml`) |
| `rsyslog_remote_dir` | `/var/log/remote` | Where the server writes |
| `rsyslog_remote_retention` | 90 | Days kept on the server |
| `rsyslog_server_queue_size` | 50000 | Server queue, in messages |
| `rsyslog_server_hosts` | inventory IPs + `netbird_ip` | Sender IP → host directory on the server |

## Notes

- Plain text on the LAN, no TLS. The log LXC only accepts RELP from known hosts (roles/pve_firewall, `log.fw`)
- fail2ban reads the journal (`backend = systemd`), so it doesn't care about the file layout
