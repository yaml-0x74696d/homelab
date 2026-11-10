# Bootstrap

The whole lab from bare hardware, in order. Each step needs the one before it. Steps done by hand are marked **(hand)**, everything else is in the repo. `<...>` is a value from `network.yml`, `private.yml` or the vault.

- With backups: the apps come back with their data (step 7), SSO included, since Authentik's database holds every OIDC client
- Without backups: the same steps, the apps start empty and OIDC is set up per app by hand ([ADR 0014](adr/0014-authentik-as-idp.md))

## 0. Controller (ctl-0)

The private files live in one folder on secure storage (encrypted, synced offsite), symlinked into the repo ([ADR 0016](adr/0016-ansible-vault-for-secrets.md)):

```bash
git clone https://github.com/yaml-0x74696d/homelab.git ~/homelab && cd ~/homelab
P=<secure storage>/homelab
ln -s $P/vault.yml       ansible/group_vars/all/vault.yml
ln -s $P/private.yml     ansible/group_vars/all/private/private.yml
ln -s $P/.vault_pass     ansible/.vault_pass
ln -s $P/aide            ansible/aide
ln -s $P/terraform.tfvars tofu/terraform.tfvars
ln -s $P/terraform.tfstate tofu/terraform.tfstate   # only with an existing lab
just setup    # pre-commit hooks, ansible collections
just check    # must pass before anything is deployed
ssh-add <admin key>
```

## 1. Proxmox nodes

**(hand)** Install PVE from the ISO on pve-1/2/3, each on its IP from `network.yml`. Then:

```bash
# pve-1
pvecm create homelab
# pve-2, pve-3
pvecm add <pve1_ip>

# any node: the token for OpenTofu, its secret goes into terraform.tfvars
pveum user token add root@pam tofu --privsep 0
pvesm set local --content iso,vztmpl,backup,snippets,import
```

- The token has to be exempt from 2FA, more in [tofu/README.md](../tofu/README.md), step 1

From ctl-0, keys first, then the pool on pve-3 (the storage CT bind-mounts it):

```bash
cd ~/homelab/ansible
ansible-playbook playbooks/push-keys.yml -l proxmox
ansible-playbook playbooks/deploy-storage.yml -l pve-3
```

PBS on pve-3 as a host package ([ADR 0013](adr/0013-pbs-file-level-backups.md)):

```bash
apt install proxmox-backup-server
proxmox-backup-manager datastore create homelab /mnt/pbs
proxmox-backup-manager user create backup@pbs
proxmox-backup-manager user generate-token backup@pbs client   # secret into the vault
proxmox-backup-manager acl update /datastore/homelab DatastoreBackup --auth-id 'backup@pbs!client'
```

- **(hand)** In the PBS UI: retention (keep 7 daily / 4 weekly / 3 monthly) and daily garbage collection
- **(hand)** In the PVE UI: storage `pbs` pointing at the datastore, used by the HAOS vzdump job

## 2. Guests (OpenTofu)

- LXC template and HAOS image: [tofu/README.md](../tofu/README.md), steps 3 and 3b
- Applied guest by guest, the log LXC first, since every other host ships its logs there:

```bash
cd ~/homelab/tofu
tofu init
for t in 'proxmox_virtual_environment_container.log' \
         'proxmox_virtual_environment_container.storage' \
         'proxmox_virtual_environment_container.iot' \
         'proxmox_virtual_environment_vm.pod["pod-1"]' \
         'proxmox_virtual_environment_vm.pod["pod-2"]' \
         'proxmox_virtual_environment_vm.pod["pod-3"]' \
         'proxmox_virtual_environment_vm.netbird' \
         'proxmox_virtual_environment_vm.haos'; do
  tofu plan -target="$t" -out=/tmp/g.plan && tofu apply /tmp/g.plan; rm -f /tmp/g.plan
done
```

- `tofu apply` asks nothing with a saved plan, so read each plan as it goes by, or run the targets one at a time
- **(hand)** Router: a DHCP reservation for HAOS on `macs.haos` (HAOS has no cloud-init), and port forwards to the NetBird VM only: 443/tcp, 3478/udp, the TURN relay range

## 3. Firewall and base

```bash
cd ~/homelab/ansible
ansible-playbook playbooks/push-keys.yml
ansible-playbook playbooks/deploy-pve-firewall.yml
ansible-playbook playbooks/deploy-login-notify.yml
ansible-playbook playbooks/vm-preparation.yml    # pod-N: vm_base, podman_base, ufw, docker on docker_hosts, aide
ansible-playbook playbooks/base.yml              # cron, journald, rsyslog, chrony, lxc hardening
ansible-playbook playbooks/deploy-storage.yml -l storage
```

## 4. NixOS VMs (netbird, edge)

Each is installed once with nixos-anywhere, OpenTofu only made the empty Debian VM ([docs/nixos-layout.md](nixos-layout.md), [ADR 0008](adr/0008-nixos-for-the-dmz-box.md), [ADR 0032](adr/0032-edge-vm-traefik-adguard-on-nixos.md)). `private.yml` is a symlink and nix copies links without their targets, so the system is built locally with `--override-input` first, then installed from the store paths. Otherwise it gets the example values, the example SSH keys included.

```bash
cd ~/homelab/nixos
H=edge   # or netbird
P=$(dirname "$(realpath ../ansible/group_vars/all/private/private.yml)")
SYS=$(nix build --no-link --print-out-paths --override-input private path:$P .#nixosConfigurations.$H.config.system.build.toplevel)
DISKO=$(nix build --no-link --print-out-paths --override-input private path:$P .#nixosConfigurations.$H.config.system.build.diskoScript)
grep -c "$(cut -d' ' -f2 ~/.ssh/id_ed25519.pub)" $SYS/etc/ssh/authorized_keys.d/root   # 1, else the install locks you out
# secrets as a tree in ram: /var/lib/secrets/<host>/..., /var/lib/secrets/aide/ntfy.env (docs/nixos-layout.md)
S=$XDG_RUNTIME_DIR/$H-secrets
nix run github:nix-community/nixos-anywhere -- --store-paths $DISKO $SYS --extra-files $S --chown /var/lib/secrets 0:0 -i ~/.ssh/id_ed25519 --target-host <admin_user>@<host ip>
rm -rf $S; ssh-keygen -R <host ip>
cd ../ansible && ansible-playbook playbooks/deploy-netbird-agent.yml   # pod-2 is the routing peer
```

- Edge only holds `dns_ip` while `dns_ip_host` in `network.yml` says `edge`. On a fresh lab it does from the start

## 5. ctl-1 (Semaphore)

**(hand)** Flash Raspberry Pi OS Lite (64-bit): hostname `ctl-1`, user `admin_user` with the vault's `sudo_pass`, ssh on ([roles/ctl_base/README.md](../ansible/roles/ctl_base/README.md)). Then:

```bash
cd ~/homelab/ansible
ssh-copy-id <admin_user>@<dhcp ip>
ansible-playbook playbooks/ctl-preparation.yml -e ansible_host=<dhcp ip>
# reboot ctl-1, it comes back on ctl1_ip
ansible-playbook playbooks/base.yml -l ctl-1
ansible-playbook playbooks/deploy-app.yml -e app=semaphore
ansible-playbook playbooks/push-keys.yml   # semaphore's key onto every host (ADR 0031)
```

## 6. Apps

```bash
cd ~/homelab/ansible
ansible-playbook playbooks/site.yml
```

- `site.yml` holds the order: Authentik before the apps that log in through it (ingress and DNS are already up on edge), storage before the CIFS apps on pod-3, the PBS client last
- One app on its own: `deploy-app.yml -e app=<name>` (Podman) or `deploy-<app>.yml` (`runtime: compose`)
- Gitea without a backup has no admin yet, create it once (values from the vault, `gitea_admin_*`):
  `ssh pod-1 'cd / && sudo -u svc-gitea XDG_RUNTIME_DIR=/run/user/$(id -u svc-gitea) podman exec -u git gitea gitea admin user create --username <user> --email <email> --password <pw> --admin --must-change-password=false'`

## 7. Restore the data

Per app, after its deploy, so the user, subuid range, units and secrets exist: stop the units, restore from PBS, start ([docs/restore-rehearsal.md](restore-rehearsal.md) has the full walk-through).

- Authentik first: its database brings back every OIDC provider and the forward-auth outposts
- CIFS data (photos, media, documents) lives on the pool, not in PBS

On the target host:

```bash
pbc() { sudo bash -c 'set -a; . /etc/pbs.env; set +a; exec proxmox-backup-client "$@"' pbc "$@"; }
pbc snapshot list host/<host>                  # pick the newest <time>
R=/var/tmp/restore
pbc restore host/<host>/<time> dumps.pxar        $R/dumps
pbc restore host/<host>/<time> podman-apps.pxar  $R/podman-apps   # podman apps
pbc restore host/<host>/<time> apps.pxar         $R/apps          # compose apps
```

Podman app with Postgres, as its svc user:

```bash
sudo systemctl --user -M svc-<app>@ stop <app>-pod
sudo rsync -a --delete $R/podman-apps/<app>/ /srv/apps/<app>/   # numeric owners come back with it
sudo systemctl --user -M svc-<app>@ start <app>-db
sudo -u svc-<app> XDG_RUNTIME_DIR=/run/user/<uid> podman exec -i <app>-db \
  sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1' < $R/dumps/<app>.sql
sudo systemctl --user -M svc-<app>@ start <app>-pod
```

- A single-container app (no db) only needs the stop, the `rsync` and a start of `<app>`
- **(hand)** HAOS: restore VM 210 from its vzdump in the PVE UI, then add the vzdump job again (Datacenter, Backup, first Saturday 15:00, [ADR 0030](adr/0030-haos-vm-on-pve-3.md)). HA's trusted proxies come back with it

## 8. AIDE baselines

The first run on each host builds its baseline. Once the apps are in place:

```bash
cd ~/homelab/ansible
ansible-playbook playbooks/aide-accept.yml
rsync -a <admin_user>@<ctl1_ip>:/srv/apps/semaphore/aide/ aide/
```

- The hashes live on ctl-1 (`/srv/apps/semaphore/aide`). ctl-0's `ansible/aide` is a copy, synced back after an accept

## 9. Verify

```bash
cd ~/homelab/ansible
ansible 'pod_vms:docker_hosts' -a 'apps ps'                    # every container healthy
ansible 'pod_vms:docker_hosts' -b -a 'systemctl start pbs-backup.service'   # one backup now, then check the PBS UI
```

- Gatus: every check green
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
