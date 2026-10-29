# 22. Central logging with rsyslog over RELP

Status: Accepted

## Context

- Every guest kept its logs in its own journal only. A dead or compromised host takes its history with it
- Looking into a problem across hosts meant SSH into each one
- The DMZ box is the one most likely to be attacked, and an attacker there can wipe local logs
- I want complete logs, good enough for an audit trail (who logged in when), not only for troubleshooting

- Alternatives:
  - Persistent journal per host, no central copy (why not: logs die with the host)
  - journald's own `systemd-journal-remote` (why not: few tools read it, no per-host text files, weak queueing)
  - Loki + Promtail/Alloy (why not: one more stack to run and update, query language instead of `grep`)
  - rsyslog over plain TCP (why not: messages in flight are lost when the connection drops)
  - rsyslog over TLS (why not: no real gain on the LAN, the server sorts by source ip anyway; needs a CA and cert rotation)
- Why: rsyslog is in every distro, writes plain text, and RELP only drops a message from the client queue once the server has saved it

## Decision

On every guest (`roles/journald`, `roles/rsyslog`, `playbooks/base.yml`):
- journald keeps the journal in RAM only (`Storage=volatile`, `RuntimeMaxUse` 100M) with rate limits
- rsyslog reads it with `imjournal` and writes local files: `/var/log/messages`, `secure`, `cron`, `maillog`, `boot.log`, rotated weekly, 4 kept
- The first start of rsyslog begins at the end of the journal (`IgnorePreviousMessages`), not at its oldest entry
- Everything is forwarded with `omrelp` to the log LXC, through a disk-assisted queue (`resumeRetryCount=-1`, `saveOnShutdown`), so messages wait while the server is down and survive a reboot

The log LXC (CT 301, `.151`, pve-3):
- pve-3 is always on, and the LXC is separate from the app VMs, so a dead VM's last logs survive
- Takes RELP on `log_relp_port` (20514) and writes `/var/log/remote/<host>/<program>.log`
- The host name comes from the sender's ip through a lookup table built from the inventory, not from what the message claims
- Keeps 90 days, daily rotation, compressed
- The PVE firewall (`log.fw`) lets RELP in only from the known hosts

Not included:
- The PVE nodes keep their persistent, capped journal (`playbooks/journald.yml`)
- The NixOS VMs join later

- Enforced by: `rsyslogd -N1` before every restart, the source allowlist in `pve_firewall_log_sources`

## Consequences

- Easier: one place to `grep` across all hosts, history outlives the host it came from
- Easier: plain text files, readable without any tool

- Harder: `journalctl -b -1` shows nothing after a reboot, the history is in `/var/log/messages` or on the log LXC
- Harder: one more guest to keep running and backed up

- Accepted: logs cross the LAN in plain text
- Accepted: the log LXC is a single copy, a disk loss there loses the central history (the hosts still keep 4 weeks locally)

- Related: [0007](0007-group-vars-single-source-of-truth.md) (ports, ips), [0019](0019-ntfy-single-alert-channel.md) (alerts stay on ntfy, logs are for looking back)
