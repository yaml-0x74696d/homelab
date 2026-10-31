# vm_base

- Hardening and base packages every Debian VM gets, whatever runs on it
- The firewall and the container runtime are not part of it: `vm-preparation.yml` adds ufw + Docker on the Docker VMs, `roles/podman_base` adds Podman next to Docker

## Runs on

- `docker_hosts`, in `playbooks/vm-preparation.yml`. Not the LXCs, the PVE nodes or the NetBird VM

## How it works

1. Installs `vm_base_packages` (guest agent, cockpit, auditd, fail2ban, AppArmor, unattended-upgrades, needrestart, node_exporter, ...)
2. unattended-upgrades: security origins only, no automatic reboot
3. sysctl from `vm_base_sysctl` (syncookies, no redirects, rp_filter, no IPv6, ...)
4. Login banner in `/etc/issue` + `/etc/issue.net`
5. sshd: no root login, no passwords, no X11, `MaxAuthTries` + keepalive from group_vars
6. auditd watches shadow, passwd, sudoers and sshd_config
7. Timezone, then enables `vm_base_services`

## Settings

| Variable | Default | What |
|---|---|---|
| `vm_base_packages` | see defaults | Package set |
| `vm_base_sysctl` | see defaults | Kernel settings, name → value |
| `vm_base_services` | cockpit, auditd, fail2ban, apparmor, node_exporter | Enabled and started |
| `login_banner_text`, `ssh_*`, `timezone` | group_vars | Shared with the other hosts |
