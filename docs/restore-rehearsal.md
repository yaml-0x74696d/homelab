# Restore rehearsal

How a backup is proven to restore: take a fresh PBS snapshot, restore one Podman app and one compose app into a throwaway VM, check they start with their data, destroy the VM. Runs before every in-place rebuild of a Docker VM. What gets backed up is in [`roles/pbs/README.md`](../ansible/roles/pbs/README.md), the why in [ADR 0013](adr/0013-pbs-file-level-backups.md).

## The apps

| | Podman | Compose |
|---|---|---|
| App | Grafana (pod-2) | Immich (pod-3) |
| Database | SQLite, `.backup` dump | Postgres with vector indexes, `pg_dump --clean --if-exists` |
| Archives | `podman-apps.pxar` + `dumps.pxar` | `apps.pxar` + `dumps.pxar` |
| Tests | subuid ownership, quadlet deploy, SQLite swap | Postgres import into a fresh db, compose from the restored folder alone |

- Grafana: pod-2 is the next rebuild, and it's the only Podman app whose data dir belongs to a uid inside the container (`472:0`), so a wrong owner shows right away
- Immich: the Postgres app with the most rows and the hardest import (vector extension). Paperless has no documents, so it would prove little
- Other apps work the same way. The table under [Results](#results) says which ones were rehearsed

## Values

```bash
VMID=299                    # free id, not in network.yml
IP=192.168.178.199          # free lan ip, outside the router's dhcp range
NODE=pve-3                  # next to PBS, the restore reads locally
MEM=3072                    # MB
DISK=32G                    # pod-3's apps.pxar is restored whole
```

- pve-3 has about 3 GB free on a normal day and already swaps, so pod-3 goes off for the rehearsal, see [Make room](#make-room)
- Commands marked "controller" run from `ansible/` on ctl-0 (fish), the rest on the node or the throwaway (bash)

## 1. Fresh backup

Controller:

```bash
ansible pod-2,pod-3 -b -a 'systemctl start pbs-backup.service'
ansible pod-2,pod-3 -b -a 'journalctl -u pbs-backup -n 3 --no-pager'
ansible pod-2,pod-3 -b -m shell -a 'set -a; . /etc/pbs.env; set +a; proxmox-backup-client snapshot list host/{{ inventory_hostname }} | tail -n 3'
```

- The service is a oneshot, `systemctl start` returns when the push is done. "Deactivated successfully" = the script reached `backup ok`
- Note each snapshot's time (`host/pod-2/2026-11-08T18:33:27Z`), the restore pins it so the log has the real backup age
- `catalog dump host/<host>/<time>` lists the files. `dumps.pxar` has to hold `grafana.db` (pod-2) and `immich.sql` (pod-3)

Then the prod counts from [step 6](#6-verify), while the snapshot is still fresh.

## 2. Throwaway VM

Built by hand with `qm` from the cloud image tofu already downloaded to every VM node, so it never shows up in the tofu state and `tofu plan` stays at "No changes".

### Make room

pod-3 goes off: frees ~7 GB on pve-3, and the restore can't lean on the source. Nextcloud, Immich, Jellyfin and Paperless are down until step 7, Gatus alerts on them are expected.

```bash
qm shutdown 203 --timeout 180    # clean guest shutdown, docker stops the stacks
```

### Create

The admin public key goes to the node first (`admin_ssh_pubkey_file` in `group_vars/all/hosts.yml`), e.g. `scp ~/.ssh/id_ed25519.pub pve-3:/root/admin.pub`. On the node:

```bash
qm create $VMID --name restore --memory $MEM --cores 2 --cpu host --ostype l26 \
  --scsihw virtio-scsi-single --serial0 socket \
  --net0 virtio,bridge=vmbr0,firewall=1 \
  --scsi0 local-lvm:0,import-from=local:import/debian-13-genericcloud-amd64.qcow2,iothread=1,discard=on,ssd=1 \
  --ide2 local-lvm:cloudinit --boot order=scsi0 \
  --ciuser <admin_user> --sshkeys /root/admin.pub \
  --ipconfig0 ip=$IP/24,gw=192.168.178.1 --nameserver 192.168.178.1
qm disk resize $VMID scsi0 $DISK
```

- `<admin_user>` is the controller's own user (ansible logs in as it)
- The name `restore` becomes the hostname, so logs that slip through never look like a prod host
- The thin-pool overcommit warning is expected, `lvs pve/data` shows the real use

### Isolation

The firewall goes on before the first boot. `/etc/pve/firewall/$VMID.fw`:

```
[OPTIONS]

enable: 1
ipfilter: 1
policy_in: DROP
policy_out: DROP

[RULES]

IN ACCEPT -source 192.168.178.0/24 -p tcp -dport 22 -log nolog
IN ACCEPT -source 192.168.178.0/24 -p icmp -log nolog
OUT ACCEPT -dest 192.168.178.103 -p tcp -dport 8007 -log nolog
OUT ACCEPT -dest 192.168.178.1 -p udp -dport 53 -log nolog
OUT ACCEPT -dest 192.168.178.1 -p tcp -dport 53 -log nolog
OUT DROP -dest 192.168.178.0/24 -log nolog
OUT ACCEPT -p tcp -dport 80 -log nolog
OUT ACCEPT -p tcp -dport 443 -log nolog

[IPSET ipfilter-net0]

192.168.178.199
```

```bash
pve-firewall compile >/dev/null && qm start $VMID
```

- The LAN is shut except PBS (pve-3:8007) and DNS on the router: OIDC token exchange with Traefik, Prometheus, RELP and the CIFS pool are all dropped
- Out to the internet only 80/443 (apt, image registries), so IMAP and SMTP are dropped too
- `ipfilter` lets only the addresses in `ipfilter-net0` out. PVE fills that set itself for containers, not for VMs: without the IPSET block every new outgoing packet is dropped, DNS included
- The VM gets global IPv6 addresses from the router advertisement, which aren't in the set. IPv6 goes off after boot (below), or apt tries them first and times out
- Apps are checked through an SSH tunnel, there's no Traefik route and no DNS record

Same ports, uids and paths as prod are fine on a separate VM. What still has to stay off:

| | Where it comes from | How it stays off |
|---|---|---|
| ntfy (pbs, aide, podman auto-update) | `ntfy_url` / `ntfy_token` from the vault, public ntfy goes over 443 | `-e @restore-vars.yml` blanks both |
| PBS pushes | `deploy-pbs.yml` installs the nightly timer | never run it here, the client is installed by hand |
| AIDE hash | `vm-preparation.yml` writes `<host>.sha256` on the controller | `--skip-tags aide` |
| DDNS | `cloudflare-ddns` (Podman on pod-1/2) | never deployed here, no `site.yml` |
| Logs, metrics, uptime checks | `base.yml` (rsyslog), the main inventory | not run, VM isn't in `inventory.yml` |
| NetBird | `deploy-netbird-agent.yml` | not run |
| OIDC | Authentik callbacks point at the prod names | log in with the local admin (break-glass) |
| Grafana alerts | contact points in the restored `grafana.db`, public ntfy over 443 | alert execution off, see step 4 |
| CIFS (Immich library) | `docker_app_cifs` in `deploy-immich.yml` | compose starts from the restored folder, the playbook isn't run, the paths stay empty local dirs |
| Diun, docker-proxy | their own compose apps | not deployed |

### Base provisioning

Controller, an inventory next to `inventory.yml` (group_vars only load from there). The throwaway is `restore` in `docker_hosts`, so it gets the same group_vars as pod-2:

```yaml
# ansible/inventory-restore.yml, listed in .git/info/exclude so it's never committed
all:
  children:
    docker_hosts:
      hosts:
        restore:
          ansible_host: 192.168.178.199
```

```yaml
# /tmp/restore-vars.yml
ntfy_url: ""
ntfy_token: ""
```

```bash
ssh <admin_user>@192.168.178.199 'cloud-init status --wait; sudo sysctl -qw net.ipv6.conf.all.disable_ipv6=1'
ansible-playbook -i inventory-restore.yml -e @/tmp/restore-vars.yml playbooks/vm-preparation.yml --skip-tags aide
```

- `cloud-init status --wait`: the first boot runs its own apt, the playbook's apt task fails on the lock otherwise
- `-i` replaces the default inventory, so nothing in this run can reach a prod host
- `--skip-tags aide`: no baseline, no `restore.sha256` on the controller

The PBS client by hand, same repo as `roles/pbs`. On the throwaway:

```bash
sudo curl -fsSo /etc/apt/keyrings/proxmox-release.gpg https://enterprise.proxmox.com/debian/proxmox-release-trixie.gpg
printf '%s\n' 'Types: deb' 'URIs: http://download.proxmox.com/debian/pbs-client' 'Suites: trixie' \
  'Components: main' 'Architectures: amd64' 'Signed-By: /etc/apt/keyrings/proxmox-release.gpg' \
  | sudo tee /etc/apt/sources.list.d/pbs-client.sources >/dev/null
sudo apt-get update -q && sudo apt-get install -yq proxmox-backup-client sqlite3
```

The credentials from the real pod-2, then onto the throwaway. Controller:

```bash
ansible pod-2 -b -m ansible.builtin.fetch -a "src=/etc/pbs.env dest=/tmp/pbs.env flat=true"
ansible -i inventory-restore.yml restore -b -m ansible.builtin.copy -a "src=/tmp/pbs.env dest=/etc/pbs.env mode=0600"
rm /tmp/pbs.env
```

- All hosts push with the same token (`backup@pbs!client`), so it can restore pod-3's groups too. It can't delete
- The VM has no timer and no script, so it never pushes anything

## 3. Restore the archives

On the throwaway:

```bash
pbc() { sudo bash -c 'set -a; . /etc/pbs.env; set +a; exec proxmox-backup-client "$@"' pbc "$@"; }
R=/var/tmp/restore
sudo mkdir -p $R/pod-2 $R/pod-3
time pbc restore host/pod-2/<time> dumps.pxar $R/pod-2/dumps
time pbc restore host/pod-2/<time> podman-apps.pxar $R/pod-2/podman-apps
time pbc restore host/pod-3/<time> dumps.pxar $R/pod-3/dumps
time pbc restore host/pod-3/<time> apps.pxar $R/pod-3/apps
```

- Restored as root, so numeric owners, modes and ACLs come back as they were
- Only one app is moved into place from each tree, the rest is thrown away with the VM

## 4. Podman app: Grafana

Deploy first, so the user, subuid range, units and secrets exist, then swap the data in. `deploy-app.yml` only deploys to the host in `apps.yml`, so a one-off play runs the role on `restore`:

```yaml
# /tmp/restore-grafana.yml
- name: Grafana on the throwaway
  hosts: restore
  become: true
  roles:
    - role: podman_app
      vars:
        podman_app_name: grafana
        podman_app_src: "{{ inventory_dir }}/apps/grafana"
        podman_app_entry: "{{ apps.grafana | combine({'allow_from': [], 'host': 'restore'}) }}"
```

Controller:

```bash
ansible-playbook -i inventory-restore.yml -e @/tmp/restore-vars.yml /tmp/restore-grafana.yml
```

- `podman_app_src`: the role finds the app's templates next to the play by default, `inventory_dir` points it back at `ansible/apps`
- `host`: the role only deploys to the app's own host
- `allow_from: []`: the ufw rules resolve the other apps' hosts, which aren't in this inventory. The PVE firewall isolates the VM anyway

On the throwaway, owners first. Restored and fresh files must show the same subuid (Grafana's 472 inside = svc-grafana's base subuid + 471):

```bash
sudo ls -ln $R/pod-2/podman-apps/grafana/data /srv/apps/grafana/data
```

Then the swap:

```bash
d=/srv/apps/grafana/data
u="systemctl --user -M svc-grafana@"
sudo $u stop grafana
sudo mv $d/grafana.db $d/grafana.db.fresh
sudo rm -f $d/grafana.db-wal $d/grafana.db-shm
sudo cp -a $R/pod-2/podman-apps/grafana/data/. $d/
sudo cp $R/pod-2/dumps/grafana.db $d/grafana.db
sudo chown --reference=$d/grafana.db.fresh $d/grafana.db
sudo chmod --reference=$d/grafana.db.fresh $d/grafana.db
printf '%s\n' '[Container]' 'Environment=GF_UNIFIED_ALERTING_EXECUTE_ALERTS=false' \
  | sudo -u svc-grafana tee /home/svc-grafana/.config/containers/systemd/grafana.container.d/90-restore.conf >/dev/null
sudo $u daemon-reload
sudo $u start grafana
```

- The SQLite file was left out of `podman-apps.pxar`, so the dump is the only copy. No `-wal`/`-shm` may sit next to it, SQLite would replay them over the restored file
- The fresh db from the first start already has the right owner, the dump takes it over
- `EXECUTE_ALERTS=false`: rules stay visible, nothing is evaluated or sent

If the owners don't line up (the uid changed in `apps.yml`):

```bash
sudo -u svc-grafana XDG_RUNTIME_DIR=/run/user/2030 sh -c 'cd /srv/apps/grafana/data && podman unshare chown -R 472:0 .'
sudo chown svc-grafana:svc-grafana /srv/apps/grafana/data   # the dir itself stays the svc user's
```

### Podman with Postgres

No Podman app has a Postgres database yet. When one does, the dump goes in as the svc user, into a db container started alone:

```bash
sudo systemctl --user -M svc-<app>@ start <app>-db
sudo -u svc-<app> XDG_RUNTIME_DIR=/run/user/<uid> podman exec -i <app>-db \
  sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1' < $R/<host>/dumps/<app>.sql
sudo systemctl --user -M svc-<app>@ start <app>-pod
```

<!-- TODO(tim): pbs-backup.sh.j2 dumps postgres with `docker exec` only. a podman postgres job needs a podman path (as the svc user) before this can be rehearsed -->

## 5. Compose app: Immich

Started straight from the restored folder: compose file, rendered `.env` and config all come from the backup, no Ansible. `immich/postgres` is its own backup job and left out of `apps.pxar`, so the db starts empty.

```bash
sudo mkdir -p /opt/stacks
sudo mv $R/pod-3/apps/immich /opt/stacks/immich
cd /opt/stacks/immich
U=$(sudo grep '^UPLOAD_LOCATION=' .env | cut -d= -f2)
for s in library upload thumbs encoded-video profile backups; do sudo mkdir -p $U/$s; sudo touch $U/$s/.immich; done
sudo docker network create proxy-net
sudo docker compose up -d --wait database
sudo sed "s/SELECT pg_catalog.set_config('search_path', '', false);/SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);/" \
  $R/pod-3/dumps/immich.sql \
  | sudo docker exec -i immich_postgres sh -c 'psql -q -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1'
sudo docker compose up -d --wait
```

- The library is on the CIFS pool and not in this backup. Immich refuses to start when its storage folders lack their `.immich` marker, so they're created empty
- The `sed` is from Immich's restore docs: `pg_dump` sets an empty `search_path`, and the vector indexes don't find their functions without it
- The dump has no `CREATE DATABASE`, the db container creates the empty db on its first start. `--clean --if-exists` only drops what exists
- Same pattern for Nextcloud, Paperless and Authentik (container `<app>-db`, no `sed`)

## 6. Verify

It starts:

```bash
curl -fsS http://127.0.0.1:3000/api/health                  # grafana: "database": "ok"
curl -fsS http://127.0.0.1:8081/api/server/ping             # immich: {"res":"pong"}
sudo docker compose -f /opt/stacks/immich/docker-compose.yml ps    # all healthy
```

It has data. The same queries on prod (step 1) and on the throwaway, the counts must match:

```bash
# grafana: users, then dashboards etc. (grafana 12+ keeps dashboards in the unified `resource` table), datasources
sudo sqlite3 /srv/apps/grafana/data/grafana.db 'select count(*) from user; select "group", resource, count(*) from resource group by 1, 2; select count(*) from data_source;'
# immich: assets, users, albums, memories, memory assets
sudo docker exec immich_postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "select (select count(*) from asset), (select count(*) from public.user), (select count(*) from album), (select count(*) from memory), (select count(*) from memory_asset);"'
```

No errors in the logs:

```bash
cd /tmp; sudo -u svc-grafana XDG_RUNTIME_DIR=/run/user/2030 podman logs --since 10m grafana 2>&1 | grep -iE 'level=(error|crit)|permission denied'
sudo docker logs immich_server 2>&1 | grep -iE 'error|fail'
```

- `cd /tmp`: podman as the svc user can't chdir into the admin's home and stops there
- By hand, through `ssh -N -L 3000:127.0.0.1:3000 -L 8081:127.0.0.1:8081 <admin_user>@$IP`: local logins, Grafana panels say "No data" (Prometheus is shut off), Immich thumbnails are missing (library on the pool)

## 7. Destroy

On the node:

```bash
qm stop $VMID && qm destroy $VMID --purge --destroy-unreferenced-disks 1
rm -f /etc/pve/firewall/$VMID.fw /root/admin.pub
qm start 203
```

Controller:

```bash
rm -f /tmp/restore-vars.yml /tmp/restore-grafana.yml inventory-restore.yml
ssh-keygen -R 192.168.178.199
```

- The VM held the restored `.env` files and dumps (vault and SSO secrets), so it goes the same day
- Nothing was pushed to PBS from it, the datastore needs no cleanup
- Gatus goes green for pod-3's apps within a few minutes

## Results

One line per rehearsal. Backup age = start of the restore minus the snapshot time, restore time = archives restored (step 3).

| Date | App | Runtime | Snapshot | Backup age | Restore time | Data check | Issues |
|---|---|---|---|---|---|---|---|
| 2026-11-08 | grafana | podman | host/pod-2/2026-11-08T18:33:27Z | ~50 min | 1 s (podman-apps + dumps, 51 MB) | 2/2 users, 2/2 dashboards, 1/1 datasource | none from the backup |
| 2026-11-08 | immich | compose | host/docker-3/2026-11-08T18:33:28Z | ~50 min | 13 s (apps + dumps, 988 MB), import 32 s | 15334/15334 assets, 193/193 memories | needs empty `.immich` markers |

## Related

- [`roles/pbs/README.md`](../ansible/roles/pbs/README.md): what each host pushes, the dump types
- [`roles/podman_app/README.md`](../ansible/roles/podman_app/README.md): svc users, subuid ranges
- [tofu-layout.md](tofu-layout.md#plan-and-apply): targeted applies only
- [ADR 0013](adr/0013-pbs-file-level-backups.md), [ADR 0021](adr/0021-podman-quadlets.md)
