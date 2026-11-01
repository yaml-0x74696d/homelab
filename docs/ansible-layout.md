# Ansible layout

Where things live in `ansible/`, and which value wins when the same variable is set in two places.

## Folders

```
ansible/
├── inventory.yml        groups: proxmox, docker_hosts, lxc_containers, netbird_agent
├── group_vars/all/      every shared variable, one topic per file
├── host_vars/<host>.yml what only one host has (pbs_jobs, ufw switches)
├── playbooks/           what runs where: pick hosts, call roles
├── roles/<role>/        how something is installed
└── apps/<app>/          what an app is made of (compose or quadlet templates, config/)
```

- Standard Ansible: inventory, `group_vars/`, `host_vars/`, the role layout, role vars prefixed with the role name (ansible-lint `var-naming`)
- Ours: `playbooks/` as a subfolder, so `group_vars/` counts as inventory group_vars (there's no `playbooks/group_vars/`); `apps/` and the `apps.yml` map, which Ansible itself knows nothing about

A role:

| Path | What |
|---|---|
| `defaults/main.yml` | the role's dials, weakest level, point at group_vars (`mosquitto_port: "{{ mqtt_port }}"`) |
| `tasks/main.yml` | the steps, other entry points via `tasks_from` |
| `templates/*.j2` | Jinja templates |
| `handlers/main.yml` | restarts and reloads, only on change |
| `meta/main.yml` | galaxy info; `argument_specs.yml` checks the inputs |
| `README.md` | what it does, step by step, and every variable |

Not used here: `vars/` (strong role vars) and `files/`.

## group_vars/all

| File | What |
|---|---|
| `network.yml` | IPs, CIDRs, bridges, VMIDs, the IoT node and its WiFi card |
| `ports.yml` | every port, once |
| `apps.yml` | the apps map: host, uid, port, `allow_from`, secrets, dirs, containers, Homepage tile. Pure data, no Jinja |
| `app_settings.yml` | settings around the apps: `apps_root`, ntfy, Gatus, MQTT |
| `hosts.yml` | SSH, Docker logs, journald, AIDE times, the admin key |
| `base.yml` | time and logging on every guest, nixos reads it too |
| `storage.yml` | pool paths, shares |
| `vault.yml` | secrets, encrypted, not in git (`vault.yml.example` has the keys) |
| `private/private.yml` | per-lab values (domain, MACs, disks), not in git (`private.yml.example`) |

- Every literal value has one home, everything else refers to it. tofu and nixos read the same files ([ADR 0007](adr/0007-group-vars-single-source-of-truth.md))
- A value used by one role only stays in that role's `defaults/`

## Variable precedence

Weak to strong, the higher number wins:

| # | Source | Here |
|---|---|---|
| 1 | command-line values that aren't vars (`-u`, `-i`) | |
| 2 | role `defaults/` | every role dial |
| 3 | group vars in the inventory file | `inventory.yml` `vars:` |
| 4 | inventory `group_vars/all` | `group_vars/all/` |
| 5 | playbook `group_vars/all` | |
| 6 | inventory `group_vars/<group>` | |
| 7 | playbook `group_vars/<group>` | |
| 8 | host vars in the inventory file | `ansible_host` |
| 9 | inventory `host_vars/<host>` | `host_vars/` |
| 10 | playbook `host_vars/<host>` | |
| 11 | facts, cached `set_fact` | |
| 12 | play `vars:` | `deploy-iot.yml` |
| 13 | play `vars_prompt:` | |
| 14 | play `vars_files:` | |
| 15 | role `vars/` | |
| 16 | block `vars:` | |
| 17 | task `vars:` | |
| 18 | `include_vars` | |
| 19 | `set_fact`, `register` | |
| 20 | role params (`roles:` / `include_role` `vars:`) | `deploy-app.yml` |
| 21 | include params | |
| 22 | extra vars `-e`, always win | `-e app=gatus` |

- Groups: a child group beats its parent, groups on the same level merge alphabetically unless `ansible_group_priority` is set
- `"{{ … }}"` resolves when it's used, not when it's set, so a role default can point at a group var

## Keywords vs variables

For connection settings (`become`, `user`, `connection`) a variable beats the play keyword:

```
ansible.cfg < command line < keyword (become: false) < variable (ansible_become: true)
```

The inventory sets `ansible_become: true` for some groups, so `become: false` on a play doesn't turn it off. Set `ansible_become: false` in the play's `vars:` instead.
