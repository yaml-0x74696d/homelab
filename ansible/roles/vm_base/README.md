# vm_base

- Hardening and base packages every Debian VM gets, whatever runs on it
- The firewall and the container runtime are not part of it: `vm-preparation.yml` adds ufw, `roles/podman_base` adds Podman

## Runs on

- `pod_vms`, in `playbooks/vm-preparation.yml`. Not the PVE nodes or the NetBird VM
- ctl-1 (bare metal) in `playbooks/ctl-preparation.yml`, without guest agent and cockpit
- The LXCs get `roles/lxc_base`, which reuses `tasks/unattended_upgrades.yml`

## How it works

1. Installs `vm_base_packages` (guest agent, cockpit, auditd, fail2ban, AppArmor, unattended-upgrades, needrestart, ...), and node_exporter without its recommends (they pull ipmitool + openipmi)
2. unattended-upgrades: security origins only, no automatic reboot
3. sysctl from `vm_base_sysctl` (syncookies, no redirects, rp_filter, no IPv6, ...)
4. Login banner in `/etc/issue` + `/etc/issue.net`
5. sshd: no root login, no passwords, no X11, `MaxAuthTries` + keepalive from group_vars
6. auditd watches shadow, passwd, sudoers and sshd_config
7. Timezone, hostname = inventory name (also `127.0.1.1` in `/etc/hosts`), then enables `vm_base_services`

## Settings

| Variable | Default | What |
|---|---|---|
| `vm_base_packages` | see defaults | Package set |
| `vm_base_sysctl` | see defaults | Kernel settings, name → value |
| `vm_base_services` | auditd, fail2ban, apparmor, node_exporter | Enabled and started |
| `vm_base_guest_agent` | true | Installs qemu-guest-agent. Off on bare metal (ctl-1) |
| `vm_base_cockpit` | true | Installs cockpit and starts its socket. Off on ctl-1 |
| `login_banner_text`, `ssh_*`, `timezone` | group_vars | Shared with the other hosts |
