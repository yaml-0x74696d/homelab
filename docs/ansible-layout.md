# Ansible layout

Where things are kept in `ansible/`, and which value is used when a variable is set in more than one place.

## Where does it go

| To change | File |
|---|---|
| an IP, a CIDR, a VMID | `group_vars/all/network.yml` |
| a port | `group_vars/all/ports.yml` |
| an app: host, port, image, who may reach it, its Homepage tile | `group_vars/all/apps.yml` |
| what one Podman container mounts or checks | `apps/<app>/<container>.container.j2` |
| an app's config files | `apps/<app>/config/` |
| a secret | `group_vars/all/vault.yml` (encrypted) |
| the domain, a MAC, a disk | `group_vars/all/private/private.yml` |
| one host only | `host_vars/<host>.yml` |
| how a role behaves | `roles/<role>/defaults/main.yml` |

## Folders

```
ansible/
├── inventory.yml        groups: proxmox, docker_hosts, lxc_containers, netbird_agent
├── group_vars/all/      every shared variable, one topic per file
├── host_vars/<host>.yml what only one host has
├── playbooks/           what is run where: hosts are picked, roles are called
├── roles/<role>/        how something is installed
└── apps/<app>/          what an app is made of
```

- Standard Ansible: the inventory, `group_vars/`, `host_vars/`, the role layout, role vars prefixed with the role name (`podman_app_*`, checked by ansible-lint)
- Specific to this repo: playbooks are kept in their own folder, so `group_vars/` is read as inventory group_vars; `apps/` and the `apps.yml` map aren't Ansible concepts

## A role

```
roles/podman_app/
├── defaults/main.yml    dials, the weakest level
├── tasks/main.yml       the steps (render.yml: another entry point)
├── templates/*.j2       Jinja templates
├── handlers/main.yml    restarts, only run on change
├── meta/                galaxy info, inputs checked by argument_specs.yml
└── README.md            what is done, step by step, every variable
```

- Defaults point at group_vars (`mosquitto_port: "{{ mqtt_port }}"`): the value is kept in one place, the role stays reusable
- `vars/` (too strong to be overridden) and `files/` aren't used

## group_vars/all

| File | What |
|---|---|
| `network.yml` | IPs, CIDRs, bridges, VMIDs, the IoT node and its WiFi card |
| `ports.yml` | every port, once |
| `apps.yml` | the apps map. Pure data without Jinja, read by edge and CI with yq. Gatus checks and Homepage tiles are generated from it |
| `app_settings.yml` | around the apps: `apps_root`, ntfy, Gatus, MQTT |
| `hosts.yml` | SSH, Docker logs, journald, AIDE, the admin key |
| `base.yml` | time and logging, also read by nixos |
| `storage.yml` | pool paths, shares |
| `vault.yml` | secrets, encrypted, not in git. `vault.yml.example` has the keys |
| `private/private.yml` | the domain, MACs, disks. Not secret, not public, not in git. `private.yml.example` |

- Each value is set in one place and referenced everywhere else. The same files are read by tofu and nixos ([ADR 0007](adr/0007-group-vars-single-source-of-truth.md))
- A value needed by one role only is kept in that role's defaults

## Which value is used

Weak to strong, the higher number wins. Where each level is used in this repo is noted on the right:

| # | Source | |
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
| 12 | play `vars:` | e.g. `deploy-iot.yml` |
| 13 | play `vars_prompt:` | |
| 14 | play `vars_files:` | |
| 15 | role `vars/` | |
| 16 | block `vars:` | |
| 17 | task `vars:` | |
| 18 | `include_vars` | |
| 19 | `set_fact`, `register` | |
| 20 | role params (`roles:`, `include_role` `vars:`) | `deploy-app.yml` |
| 21 | include params | |
| 22 | extra vars `-e`, always | `-e app=gatus` |

- A child group beats its parent. Groups on the same level are merged alphabetically, unless `ansible_group_priority` is set
- `"{{ … }}"` is resolved when it's used, not when it's set. That's why a role default can point at a group var

## Keywords lose to variables

For connection settings (`become`, `user`, `connection`) the play keyword is overridden by the variable:

```
ansible.cfg < command line < keyword (become: false) < variable (ansible_become: true)
```

`ansible_become: true` is set in the inventory for some groups, so `become: false` on a play has no effect there. `ansible_become: false` in the play's `vars:` is needed instead.
