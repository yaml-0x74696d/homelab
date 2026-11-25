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
├── ansible.cfg          roles_path, collections_path, vault password file, ssh options
├── requirements.yml     the collections, one major each, installed into collections/ (gitignored)
├── .ansible-lint        lint rules
├── ansible-navigator.yml.example  settings for the navigator container, the real file is gitignored
├── inventory.yml        hosts and groups only: proxmox, pod_vms, podman_hosts (ctl-1), lxc_containers, netbird_agent, appliances (never logged in to)
├── group_vars/all/      every shared variable, one topic per file
├── group_vars/<group>.yml  how a group is logged in to (user, become)
├── host_vars/<host>.yml what only one host has
├── playbooks/           what is run where: hosts are picked, roles are called
├── roles/<role>/        how something is installed
├── apps/<app>/          what an app is made of
└── aide/                accepted AIDE hashes, gitignored (a link into the synced private folder on the controller)
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
├── meta/                galaxy info, types of the inputs in argument_specs.yml
└── README.md            what is done, step by step, every variable
```

- Defaults point at group_vars (`mosquitto_port: "{{ mqtt_port }}"`): the value is kept in one place, the role stays reusable
- `vars/` isn't used: too strong to be overridden

Every `README.md` has the same headings, in this order:

```
# <role>
- what it does, what it leaves to others (2-3 bullets)

## Runs on         hosts, the playbook, what has to be there first
## How it works    numbered steps, in task order
## <topic>         optional, one section per thing that needs more words
## Settings        | Variable | Default | What |, defaults in backticks
## Notes           gotchas, one line each
## Related         ADRs and the code outside the role
```

Types and required inputs go in `meta/argument_specs.yml`, not in the README.

## Playbooks

Run from `ansible/`: `ansible-playbook playbooks/<file>`.

| File | Hosts | What | How it's run |
|---|---|---|---|
| `site.yml` | what the imported ones pick | `base.yml`, every app, authentik, iot, storage, `deploy-pbs.yml`, in order | by hand |
| `vm-preparation.yml` | `pod_vms` | `vm_base`, `podman_base`, ufw, AIDE | by hand, once per VM |
| `ctl-preparation.yml` | `podman_hosts` | `vm_base`, `podman_base`, `ctl_base`, AIDE for ctl-1 | by hand, once |
| `base.yml` | guests, VMs, ctl-1 | cron, journald, rsyslog, chrony, LXC hardening | by hand, from `site.yml` |
| `deploy-app.yml` | the app's hosts | one Podman app, `-e app=<name>` | by hand, `just deploy-app` |
| `deploy-authentik.yml` | `pod-1` | Authentik with guards: no skipped release series, no downgrade | by hand, from `site.yml` |
| `deploy-iot.yml` | `proxmox`, `iot` | Wi-Fi card into the IoT LXC, broker, exporter, firmware server | by hand, from `site.yml` |
| `deploy-storage.yml` | `pve-3`, `storage` | mergerfs pool, Samba shares | by hand, from `site.yml` |
| `deploy-pbs.yml` | `pod_vms` | PBS backup client and timer | by hand, from `site.yml` |
| `deploy-pve-firewall.yml` | `proxmox` | Proxmox firewall files | by hand |
| `deploy-pve-thinpool.yml` | `proxmox` | thin pool metrics for node-exporter | by hand |
| `deploy-login-notify.yml` | `proxmox` | ntfy alert on SSH and PVE web logins | by hand |
| `deploy-netbird-agent.yml` | `netbird_agent` | NetBird peer on the LAN routing host | by hand |
| `journald.yml` | `proxmox` | journal size cap | by hand |
| `login-banner.yml` | all but `appliances` | fastfetch login banner | by hand |
| `push-keys.yml` | all but `appliances` | admin and Semaphore keys into `authorized_keys` | by hand |
| `aide.yml` | guests, VMs, nodes, ctl-1 | AIDE install, baseline, daily check, hash verify | by hand, Semaphore (daily) |
| `aide-accept.yml` | same | review and accept changes, one host at a time | by hand, Semaphore with `aide_accept=yes` |
| `update.yml` | same | OS updates one host at a time, no reboot, summary | Semaphore (weekly), by hand |
| `repo-pull.yml` | `podman_hosts` | pulls Semaphore's checkout on ctl-1 | Semaphore (daily) |
| `render-podman.yml` | `pod_vms`, `podman_hosts` | renders every app with example values, touches no host | `just render` |
| `ci-validate-apps.yml` | `localhost` | `apps.yml` against the `podman_app` argument spec | pre-commit hook `apps-schema` |

## group_vars/all

| File | What |
|---|---|
| `connection.yml` | login user and Python for every host, the groups override it |
| `network.yml` | IPs, CIDRs, bridges, VMIDs, the IoT node and its WiFi card |
| `ports.yml` | every port, once |
| `apps.yml` | the apps map. Pure data without Jinja, read by edge and CI with yq. Gatus checks and Homepage tiles are generated from it |
| `app_settings.yml` | around the apps: `podman_apps_root`, `app_sources`, ntfy, Gatus, Homepage, Semaphore, MQTT, the PBS staging dir |
| `hosts.yml` | SSH, journald size, the admin key, the login banner, the part-time hosts (`reach_optional_hosts`) |
| `schedules.yml` | every timer: NixOS upgrade + reboot windows, AIDE, PBS, Podman auto-update, the Gatus heartbeat windows, also read by nixos |
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

`ansible_become: true` is set for `pod_vms` and `podman_hosts` (`group_vars/<group>.yml`), so `become: false` on a play has no effect there. `ansible_become: false` in the play's `vars:` is needed instead.

## Conventions

For new and changed code:

- A config file that has a checker gets `validate:` on its `template`/`copy`, so a broken file never lands (`sshd -t -f %s`, `rsyslogd -N1 -f %s`, `chronyd -p -f %s`, `dnsmasq --test -C %s`, `testparm -s %s`). Without one, a check task right after
- Scripts go into a role's `files/`, not inline `content: |` in a playbook. Values they need come from a small file next to them (`/etc/default/<name>`)
- Playbooks stay thin: hosts and order. Anything with more than a couple of tasks becomes a role with a README
- A role with structured inputs (lists of dicts, entry points called from elsewhere) gets `meta/argument_specs.yml`
- Login variables per group go in `group_vars/<group>.yml`, the inventory only lists hosts
- A task or file that holds a secret gets `no_log: true` and `diff: false`. Never run `--diff` on one: it prints the old and new content, secrets included, into the terminal, CI logs and Semaphore's run history. If a value was printed anyway: change it in `vault.yml`, deploy the app again, and change it in the app itself where it holds a copy (database users, OIDC clients)
