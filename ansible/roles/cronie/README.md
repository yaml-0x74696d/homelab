# cronie

- cronie as the cron daemon
- For host jobs only. Podman auto-update runs on systemd user timers, not cron

## Runs on

- All guests (`docker_hosts`, `lxc_containers`), in `playbooks/base.yml`. Not the pve nodes

## How it works

1. Installs `cronie`
2. Enables `cronie.service`

## Notes

- Jobs live in `/etc/crontab`, `/etc/cron.d/` and user crontabs
- The service is `cronie.service`
- Cron output goes to `/var/log/cron` (roles/rsyslog)
