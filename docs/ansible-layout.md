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
| how ansible logs in to a group | `group_vars/<group>.yml` |
| one host only | `host_vars/<host>.yml` |
| how a role behaves | `roles/<role>/defaults/main.yml` |

## Folders

```
ansible/
├── inventory.yml        hosts and groups only: proxmox, docker_hosts, lxc_containers, netbird_agent
├── group_vars/all/      every shared variable, one topic per file
├── group_vars/<group>.yml  how a group is logged in to (user, become)
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
├── files/               static files copied as they are (scripts, so shellcheck sees them)
├── handlers/main.yml    restarts, only run on change
├── meta/                galaxy info, inputs checked by argument_specs.yml
└── README.md            what is done, step by step, every variable
```

- Defaults point at group_vars (`mosquitto_port: "{{ mqtt_port }}"`): the value is kept in one place, the role stays reusable
- `vars/` isn't used: too strong to be overridden

## group_vars/all

| File | What |
|---|---|
| `connection.yml` | login user and Python for every host, the groups override it |
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
| 3 | group vars in the inventory file | |
| 4 | inventory `group_vars/all` | `group_vars/all/` |
| 5 | playbook `group_vars/all` | |
| 6 | inventory `group_vars/<group>` | `group_vars/<group>.yml` |
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

`ansible_become: true` is set for `docker_hosts` (`group_vars/docker_hosts.yml`), so `become: false` on a play has no effect there. `ansible_become: false` in the play's `vars:` is needed instead.

## Conventions

For new and changed code, not for the compose apps on their way out:

- A config file that has a checker gets `validate:` on its `template`/`copy`, so a broken file never lands (`sshd -t -f %s`, `rsyslogd -N1 -f %s`, `chronyd -p -f %s`, `dnsmasq --test -C %s`, `testparm -s %s`). Without one, a check task right after
- Scripts go into a role's `files/`, not inline `content: |` in a playbook. Values they need come from a small file next to them (`/etc/default/<name>`)
- Playbooks stay thin: hosts and order. Anything with more than a couple of tasks becomes a role with a README
- A role with structured inputs (lists of dicts, entry points called from elsewhere) gets `meta/argument_specs.yml`
- Login variables per group go in `group_vars/<group>.yml`, the inventory only lists hosts
