# lxc_base

- Hardening and base packages every LXC gets, the LXC side of `roles/vm_base`
- Only what works in an unprivileged CT: no guest agent, auditd, AppArmor, sysctl or cockpit (the host owns the kernel), no chrony (the CT uses the host's clock)

## Runs on

- `lxc_containers` (storage, log, iot), in the last play of `playbooks/base.yml`

## How it works

1. Installs `lxc_base_packages` (fail2ban, unattended-upgrades, needrestart, node_exporter)
2. unattended-upgrades: `vm_base`'s file (`tasks_from: unattended_upgrades`), security origins only, no automatic reboot
3. sshd drop-in `/etc/ssh/sshd_config.d/10-homelab.conf`, checked with `sshd -t`: root by key only (Ansible logs in as root here), no passwords, no X11, `MaxAuthTries` + keepalive from group_vars. A drop-in, because the first value sshd reads wins
4. fail2ban: the `sshd` jail on the journal (`backend = systemd`)
5. node_exporter listens on the LXC's LAN address only (`ARGS` in `/etc/default/prometheus-node-exporter`), never on the IoT leg
6. Timezone, then enables fail2ban and node_exporter
7. With `lxc_base_ufw: true` (host_vars storage, iot): ufw rule for node_exporter from `prometheus_ip`, tagged `node-exporter`. The PVE firewall lets Prometheus in on its own where it filters (`log.fw`, `iot.fw`)

## Settings

| Variable | Default | What |
|---|---|---|
| `lxc_base_packages` | see defaults | Package set |
| `lxc_base_services` | fail2ban, node_exporter | Enabled and started |
| `lxc_base_node_exporter_listen` | `ansible_host:node_exporter_port` | node_exporter's listen address |
| `lxc_base_ufw` | `false` | `true` on the LXCs that filter with ufw (storage, iot) |
| `prometheus_ip` | `app_settings.yml` | Source of the node_exporter rule |
| `timezone`, `ssh_*` | group_vars | Shared with `vm_base` |

## Notes

- `tasks/ufw_rules.yml`: allow rules tagged with a comment; tagged rules that left the list are deleted (the podman_app pattern). `deploy-iot.yml` uses it too
- `--check` on a fresh CT: tasks that need the packages are `ignore_errors` in check mode
- Prometheus scrapes every LXC in the `node-exporter` job (`apps/prometheus/config/prometheus.yml.j2`)
- In an unprivileged CT node_exporter sees lxcfs' view: CPU and memory are the CT's, some disk and network numbers are the host's
