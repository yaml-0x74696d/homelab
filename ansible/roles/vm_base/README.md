# vm_base

- Hardening and base packages every Debian VM gets, whatever runs on it
- The firewall and the container runtime are not part of it: `vm-preparation.yml` adds ufw, `roles/podman_base` adds Podman

## Runs on

- `pod_vms`, in `playbooks/vm-preparation.yml`. Not the PVE nodes or the NetBird VM
- ctl-1 (bare metal) in `playbooks/ctl-preparation.yml`, without guest agent and cockpit
- The LXCs get `roles/lxc_base`, which reuses `tasks/unattended_upgrades.yml`

## How it works

1. Installs `vm_base_packages` (auditd, fail2ban, AppArmor, unattended-upgrades, needrestart, ...), the guest agent and cockpit when on, and node_exporter without its recommends (they pull ipmitool + openipmi)
2. unattended-upgrades: security origins only, no automatic reboot. Stops if apt has no Debian-Security source
3. sysctl from `vm_base_sysctl` (syncookies, no redirects, rp_filter, no IPv6, ...), and the same keys removed from `/etc/sysctl.conf`
4. Login banner in `/etc/issue` + `/etc/issue.net`
5. sshd: no root login, no passwords, no X11, `MaxAuthTries` + keepalive from group_vars
6. auditd watches shadow, passwd, sudoers and sshd_config
7. Cockpit (`/etc/cockpit/cockpit.conf`): the browser origin `https://<host>.<domain>` and `X-Forwarded-Proto`, since it sits behind Traefik. A change stops `cockpit.service`, the socket starts it again with the new config
8. Timezone, hostname = inventory name (also `127.0.1.1` in `/etc/hosts`), then enables `vm_base_services`

## Settings

| Variable | Default | What |
|---|---|---|
| `vm_base_packages` | see defaults | Package set |
| `vm_base_sysctl` | see defaults | Kernel settings, name → value |
| `vm_base_rp_filter` | 1 | Reverse path filter, 2 (loose) on pod-2, the netbird routing peer |
| `vm_base_sysctl_file` | `/etc/sysctl.d/90-vm-base.conf` | Debian 13 reads only `/etc/sysctl.d` at boot |
| `vm_base_services` | auditd, fail2ban, apparmor, node_exporter | Enabled and started, plus `cockpit.socket` when `vm_base_cockpit` |
| `vm_base_guest_agent` | true | Installs qemu-guest-agent. Off on bare metal (ctl-1) |
| `vm_base_cockpit` | true | Installs cockpit and starts its socket. Off on ctl-1 |
| `vm_base_cockpit_origins` | `https://<host>.<domain>` | Websocket origins cockpit accepts (`Origins`) |
| `vm_base_cockpit_protocol_header` | X-Forwarded-Proto | Header telling cockpit the proxy spoke TLS (`ProtocolHeader`) |
| `login_banner_text`, `ssh_*`, `timezone` | group_vars | Shared with the other hosts |
