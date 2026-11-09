# Bootstrap

The whole lab from bare hardware, in order. Each step needs the one before it. Steps done by hand are marked **(hand)**, everything else is in the repo.

- With backups: the apps come back with their data (step 7), SSO included, since Authentik's database holds every OIDC client
- Without backups: the same steps, the apps start empty and OIDC is set up per app by hand ([ADR 0014](adr/0014-authentik-as-idp.md))

## 0. Controller (ctl-0)

- Clone the repo, `just setup` (pre-commit, the Ansible collections)
- **(hand)** The private files come from Tresorit (`~/Tresorit/Sync/homelab`, symlinked into the repo): `ansible/group_vars/all/vault.yml`, `ansible/group_vars/all/private/private.yml`, `ansible/.vault_pass`, the SSH keys
- `just check` passes before anything is deployed

## 1. Proxmox nodes (hand)

- Install PVE from the ISO on pve-1/2/3, IPs from `group_vars/all/network.yml`
- Join the three into one cluster
- Root API token, exempt from 2FA, for OpenTofu ([tofu/README.md](../tofu/README.md), step 1)
- `local` datastore: turn on the **import** content type
- pve-3: PBS as a host package, datastore `homelab` at `/mnt/pbs`, token `backup@pbs!client` with `DatastoreBackup` on `/datastore/homelab` only, retention in the PBS UI ([ADR 0013](adr/0013-pbs-file-level-backups.md))
- PVE storage `pbs` pointing at that datastore (used by the HAOS vzdump job)

Then from ctl-0:

```bash
cd ~/homelab/ansible
ansible-playbook playbooks/push-keys.yml -l proxmox
ansible-playbook playbooks/deploy-storage.yml -l pve-3   # mergerfs pool, the storage CT bind-mounts it
```

## 2. Guests (OpenTofu)

- tfvars, LXC template, HAOS image: [tofu/README.md](../tofu/README.md), steps 2–3b
- Applied guest by guest, the log LXC first (every other host ships its logs there):

```bash
cd ~/homelab/tofu
tofu init
tofu plan -target='proxmox_virtual_environment_container.log' -out=/tmp/g.plan
tofu apply /tmp/g.plan && rm /tmp/g.plan
# same for: container.storage, container.iot, vm.pod["pod-1"], vm.pod["pod-2"], vm.pod["pod-3"], netbird, haos
```

- **(hand)** FRITZ!Box: DHCP reservation for HAOS on `macs.haos`, port forwards to the NetBird VM only (443/tcp, 3478/udp, the TURN relay range)

## 3. Firewall and base

```bash
cd ~/homelab/ansible
ansible-playbook playbooks/deploy-pve-firewall.yml
ansible-playbook playbooks/deploy-login-notify.yml
ansible-playbook playbooks/vm-preparation.yml    # pod-N: vm_base, podman_base, ufw, docker on docker_hosts, aide
ansible-playbook playbooks/base.yml              # cron, journald, rsyslog, chrony, lxc hardening
ansible-playbook playbooks/deploy-storage.yml -l storage
```

## 4. NetBird VM

- nixos-anywhere once onto the empty VM, then `nixos/update.sh` ([docs/nixos-layout.md](nixos-layout.md), [ADR 0008](adr/0008-nixos-for-the-dmz-box.md))
- `ansible-playbook playbooks/deploy-netbird-agent.yml` (pod-2 is the routing peer)

## 5. ctl-1 (Semaphore)

- **(hand)** Admin user on ctl-1 ([roles/ctl_base/README.md](../ansible/roles/ctl_base/README.md))
- `ctl-preparation.yml -l ctl-1`, `base.yml -l ctl-1`, `deploy-app.yml -e app=semaphore`
- `push-keys.yml` again, so Semaphore's key lands on every host ([ADR 0031](adr/0031-semaphore-on-a-pi.md))

## 6. Apps

```bash
ansible-playbook site.yml
```

- `site.yml` holds the order: ingress (Traefik, Pi-hole) and Authentik before the apps that log in through it, storage before the CIFS apps on pod-3, the PBS client last
- One app on its own: `deploy-app.yml -e app=<name>` (Podman) or `deploy-<app>.yml` (`runtime: compose`)
- IoT gateway: `deploy-iot.yml` (also in `site.yml`)

## 7. Restore the data

Per app, after its deploy, so the user, subuid range, units and secrets exist: stop the units, restore from PBS, fix the owners, start ([docs/restore-rehearsal.md](restore-rehearsal.md), steps 3–5).

- Authentik first: its database brings back every OIDC provider and the forward-auth outposts
- Podman apps: `dumps.pxar` + `podman-apps.pxar` from `host/pod-N`, the dump goes into `<app>-db` as the svc user
- Compose apps: `dumps.pxar` + `apps.pxar`
- CIFS data (photos, media, documents) lives on the pool, not in PBS
- **(hand)** HAOS: restore VM 210 from its vzdump in the PVE UI, then the vzdump job again (Datacenter, Backup, first Saturday 15:00, [ADR 0030](adr/0030-haos-vm-on-pve-3.md)). HA's trusted proxies come back with it

## 8. AIDE baselines

- The first run of each host builds its baseline. Once the apps are in place, accept on every host:

```bash
ansible-playbook playbooks/aide-accept.yml
```

- The hashes live on ctl-1 (`/srv/apps/semaphore/aide`). ctl-0's `ansible/aide` is a copy, rsynced back by hand after an accept

## 9. Verify

- Gatus: every check green
- `apps ps` on each pod-N: every container healthy
- `deploy-pbs.yml` ran, and the first evening's backup shows up in PBS per host
- One SSO login per app

## Guests on EL10: what changes

The guests stay Debian 13 until the CPUs have x86-64-v3 ([ADR 0025](adr/0025-debian-guests-until-x86-64-v3.md)). The PVE nodes and the NetBird VM aren't affected. These are the Debian-only places a move would hit.

Images (`tofu/variables.tf`):
- `debian_image_url` → an EL10 GenericCloud image, `lxc_template` → an EL10 LXC template
- All guests on a node move together: with `cpu = host`, an EL10 guest can only run on a node with x86-64-v3

Packages and repos:
- Every `ansible.builtin.apt` → `ansible.builtin.dnf` (or `package` where the name is the same): vm_base, podman_base, podman_app, cronie, chrony, aide, rsyslog, pbs, update, lxc_base, samba, mosquitto, mqtt_exporter, ota_server, iot_ap
- `deb822_repository` → `yum_repository`, EPEL on (fail2ban, node_exporter, hostapd)
- `ansible_facts['distribution_release']` in repo URLs (pbs, the docker block in vm-preparation)
- `vm_base_packages`: `auditd` → `audit`, `libpam-pwquality` → `libpwquality`, `apparmor*` out, `unattended-upgrades` → `dnf-automatic`, `needrestart` → `dnf-utils`, `prometheus-node-exporter` → EPEL's `golang-github-prometheus-node-exporter` (other unit name)
- PBS client: no EL package, only the static binary ([ADR 0013](adr/0013-pbs-file-level-backups.md))
- cronie: the unit is `crond`, not `cronie`

Updates (`roles/update`, `vm_base/tasks/unattended_upgrades.yml`, [ADR 0024](adr/0024-ansible-run-os-updates.md)):
- dist-upgrade → `dnf upgrade`
- `/run/reboot-required` → `needs-restarting -r`, needrestart → `needs-restarting -s`
- New configs: `.rpmnew` instead of `.dpkg-dist`
- Security-only auto updates through `dnf-automatic` (`upgrade_type = security`)

Firewall ([ADR 0026](adr/0026-ufw-as-guest-firewall.md)):
- ufw → firewalld: vm-preparation, `podman_app` (rules + `ufw-stale.j2`), `lxc_base` (`ufw_rules.yml` + `ufw-stale.j2`)
- Per-source app rules become rich rules or one zone per caller

SELinux instead of AppArmor ([ADR 0021](adr/0021-podman-quadlets.md)):
- Local volumes already carry `:Z`
- CIFS volumes have no label: `context=system_u:object_r:container_file_t:s0` in the `podman_app` fstab opts, or the `virt_use_samba` boolean
- `apparmor` out of `vm_base_services`

Paths:
- chrony: `/etc/chrony/chrony.conf` → `/etc/chrony.conf`
- aide: `/etc/aide/aide.conf.d/` → `/etc/aide.conf` (check the include), the Debian daily-check mask goes, the excludes swap apt paths for `/var/lib/dnf`, `/var/cache/dnf`
- sshd: EL reads `sshd_config.d/` first (`50-redhat.conf`), so the hardening goes into a drop-in instead of lines in `sshd_config`

ADRs to revise then: 0025 (superseded), 0026 (firewalld), 0024 (dnf), 0013 (static PBS client), 0021 (SELinux)
