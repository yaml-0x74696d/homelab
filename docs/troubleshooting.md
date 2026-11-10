# Troubleshooting

Known failures with their cause and fix, grouped by where they show up. Commands run from `~/homelab/ansible` on the controller unless they start with `ssh`. `<...>` is a value from `network.yml`, `private.yml` or the vault.

## Where to look first

Every app runs rootless as its own user, so plain `podman ps` and `journalctl -u` as the admin show nothing.

```bash
ssh pod-1 apps                          # every container on the host: user, status, ports
ssh pod-1 apps logs <app> --tail 50     # podman logs as the app's svc user
ssh pod-1 apps status <app>             # the app's systemd user units
ansible pod_vms -a 'apps ps'            # all pod VMs at once
```

- systemd's messages about a user unit: `journalctl USER_UNIT=<app>.service`, not `-u` (that only matches system units). Several matches joined with `+` are an OR: `journalctl SYSLOG_IDENTIFIER=<app> + USER_UNIT=<app>.service`
- A container that crashes on start is gone before you can read it: quadlet runs it with `--rm`. Catch the next restart instead:
  `ssh pod-1 'cd / && sudo -u svc-<app> XDG_RUNTIME_DIR=/run/user/$(id -u svc-<app>) sh -c "until podman container exists <app>; do sleep 1; done; podman logs -f <app> 2>&1 | tail -40"'`
- Filters inside that `sh -c "..."` without quotes survive the three shell layers (fish, ssh, sh): `grep -i -e error -e traceback`, `grep -v level...info`

## Podman apps

**`sudo -u svc-<app> ...` or `runuser` fails with "cannot chdir"**
- Cause: the svc user can't read the admin's home, where the command starts
- Fix: `cd /` first

**A unit fails to start, the journal says `unhealthy` three times, then exit 137**
- Cause: `HealthOnFailure=kill` (`roles/podman_app`, house rules) counts failed checks from the first second. A slow first start (migrations on an empty database) dies before it answers
- Fix: `HealthStartPeriod=` in the container template, long enough for the migrations (Authentik `10m`, Nextcloud `10m`, the rest `3m`). Raise `start_timeout` in `apps.yml` too when the start takes longer than `podman_app_start_timeout` (5 min)

**`HealthStartPeriod=3min` is rejected**
- Cause: podman wants Go durations
- Fix: `3m`, `10m`, `90s`

**Authentik: `InconsistentMigrationHistory` after a killed start**
- Cause: the first start on an empty database was killed halfway through the migrations
- Fix: the database is unusable. Stop the pod, empty `/srv/apps/authentik/database`, start again (or restore it, [bootstrap step 7](bootstrap.md#7-restore-the-data))

**A container gets ECONNREFUSED on its own host's IP**
- Cause: pasta gives a rootless container the host's IPs. Inside the container, the host's own address is the container itself
- Fix: reach the host as `host.containers.internal` (Gatus and Homepage do that for the apps on their own host)

**A container keeps answering for an IP its host no longer has**
- Cause: pasta copies the host's addresses at container start. When an address leaves the host (the `.53` service IP moving to edge), the running container keeps it, and traffic to that IP stays inside the container (dns-relay answered SERVFAIL)
- Fix: restart the container after an IP moves

**A container can't resolve `auth.<domain>` (OIDC discovery fails, Vaultwarden: "Failed to discover OpenID provider")**
- Cause: the pod VMs resolve through the router, which doesn't know the LAN names
- Fix: `AddHost=auth.{{ domain }}:{{ app_sources.edge }}` in the unit (in the `.pod.j2` for a pod), [ADR 0032](adr/0032-edge-vm-traefik-adguard-on-nixos.md)

**`exec /coredns: Operation not permitted`**
- Cause: the binary carries a file capability (`cap_net_bind_service`), and `drop_caps: [ALL]` leaves nothing it may hold
- Fix: `add_caps: [NET_BIND_SERVICE]` on the container in `apps.yml`

**Two containers of one pod fight over a port or a socket**
- Cause: a pod shares one network and one IPC namespace. Containers that each listen on the same default port (the Authentik server and worker) collide
- Fix: give the second one its own listen ports (`authentik-worker.container.j2`)

**Postgres data dir flips between 0700 and 0750 on every deploy**
- Cause: initdb sets 0700, the role's default dir mode is 0750
- Fix: `mode: "0700"` on that dir in `apps.yml`

**Disk full after moving an app with `container_uid` (keep-id)**
- Cause: keep-id stores a remapped copy of every image layer, the image disk use doubles
- Fix: `podman image prune -af` as the svc user, then grow the disk: `disk` in `tofu/locals.tf`, a targeted `tofu apply`, then `growpart <disk> <partition number>` and `resize2fs <root partition>` in the VM (names from `lsblk`)

**Nextcloud returns 500 after a move into a pod**
- Cause: `config.php` still names the old compose hosts (`db`, `redis`)
- Fix: `dbhost` and the redis host to `127.0.0.1`, everything in a pod shares localhost

**"User already exists" on the first Authentik login in an app**
- Cause: the app already has a local account with the same email
- Fix: log in locally and link the account in the app (Paperless: My profile, Connect)

## Moving data between hosts or apps

**Owner mapping when copying data into a rootless app**
- Without `container_uid` (no keep-id): container root is `svc-<app>`, container uid `n` is `S + n - 1`
- With `container_uid: c`: `c` is `svc-<app>`, `n < c` is `S + n`
- `S` is the svc user's subuid start: `uid × 65536` (`grep svc-<app> /etc/subuid`)
- Check the real owners of the source first: `sudo find <dir> -printf "%u:%g\n" | sort | uniq -c`
- Example, Authentik (uid 2170, `S` = 142213120): postgres 70 → 142213189, authentik 1000 → 142214119

**`rsync: command not found` on a pod VM**
- Cause: the pod VMs don't ship rsync
- Fix: `sudo find <dst> -mindepth 1 -delete && sudo cp -a <src>/. <dst>/` does the same as `rsync -a --delete`

## DNS, ingress and VPN

**`resolvectl query` says "Data from: synthetic"**
- Cause: the answer came from `/etc/hosts`, not from DNS
- Fix: remove the stale line from `/etc/hosts`

**`resolvectl dns` doesn't switch to the new server**
- Cause: systemd-resolved keeps its current server
- Fix: set it in NetworkManager: `nmcli con mod "<connection>" ipv4.dns "<edge_ip> <dns_ip>" ipv4.ignore-auto-dns yes && nmcli con up "<connection>"`. In the browser: `about:networking#dns`, clear the cache

**Moving the `.53` service IP**
- The old host drops it first, the new host adds it, then a gratuitous ARP so the LAN's caches follow: `arping -U -I <interface> -c 3 <dns_ip>`
- "Device ... not available": the interface name differs per VM, read it from `ip route`
- Both hosts holding it at once breaks DNS for half the LAN. A failed run on one side (an Ansible run from `nixos/` has no vault) has to be finished by hand before anything else

**VPN clients (iOS) resolve nothing**
- The NetBird nameserver group points at pod-2's overlay IP with port 1053 (dns-relay), not 53: NetBird's own DNS holds 53 on a peer
- dns-relay forwards to `dns_ip`. If it answers SERVFAIL after `.53` moved, restart it (see the pasta entries above)

**Home Assistant answers 400 through edge**
- Cause: HA only trusts forwarded requests from its listed proxies
- Fix: `trusted_proxies` in HA must hold `edge_ip` (Settings, or `configuration.yaml`), then restart HA. A HAOS restore brings the old list back, check it after one

**AdGuard Home UI while Authentik is down**
- `ssh -L 3000:127.0.0.1:3000 <admin_user>@<edge_ip>`, then `http://localhost:3000`. There's no AdGuard user on purpose ([ADR 0032](adr/0032-edge-vm-traefik-adguard-on-nixos.md))

**Traefik logs "tls: bad certificate" right after a restart**
- Cause: for a moment it serves its default certificate, before the ACME one is loaded
- Harmless, it stops by itself

**Jellyfin won't play in one browser**
- Cause: the browser's ffmpeg lacks H.264
- Fix: on the client, not the server (install a full ffmpeg, or use another browser)

## NixOS VMs (netbird, edge)

**`nix flake check` or a build can't find a new file**
- Cause: flakes only see files git knows about
- Fix: `git add` (or `git add -N`) first

**The build doesn't see `private.yml`**
- Cause: `private.yml` is a symlink into the private folder, and nix copies the link, not its target
- Fix: `--override-input private path:<real private dir>` (`nixos/update.sh` does that)

**`nixos-rebuild switch --target-host` hangs**
- Fix: build locally, copy, switch on the VM:
  ```bash
  SYS=$(nix build --no-link --print-out-paths ".#nixosConfigurations.<host>.config.system.build.toplevel" --override-input private path:<real private dir>)
  nix copy --to ssh://root@<host_ip> "$SYS"
  ssh root@<host_ip> "nix-env -p /nix/var/nix/profiles/system --set $SYS && $SYS/bin/switch-to-configuration switch"
  ```
- Never Ctrl-C a switch on edge: it can stop between dropping and adding `.53`. If it happened: `systemctl start dns-ip` on edge, check with `dig @<dns_ip>`

**Ansible run from `nixos/` fails on vault variables**
- Cause: `ansible.cfg` and the vault password file are found relative to `ansible/`
- Fix: run Ansible from `ansible/`

## Proxmox, OpenTofu, VMs

**`tofu validate` complains about a missing `macs.<guest>`**
- Fix: add a MAC to `private.yml`. Proxmox prefix plus three random bytes, in fish:
  `printf 'BC:24:11:%02X:%02X:%02X\n' (random 0 255) (random 0 255) (random 0 255)`

**`moved` blocks fail with a partial `-target`**
- Fix: move the state by hand: `tofu state mv '<old address>' '<new address>'`

**`tofu fmt` realigns lines after a comment**
- A comment line splits an alignment group, the lines below it align on their own. Expected

**A renamed VM keeps its old hostname or SSH keys**
- Cause: cloud-init only runs again on a new instance-id, which needs a cold stop and start, not a reboot
- Fix: `qm stop <vmid> && qm start <vmid>`. New SSH host keys follow: `ssh-keygen -R <ip>` on the controller and ctl-1, AIDE accept on that host. PBS starts a new backup group `host/<new name>`, delete the old one in the PBS UI once it's not needed

**`qm reboot` hangs**
- Cause: no guest agent answering
- Fix: power off inside the VM, then `qm start <vmid>`

**`rp_filter` is back to strict after a reboot**
- Known: the sysctl reverts at boot on the VMs. Check with `sysctl net.ipv4.conf.all.rp_filter` when routed traffic (NetBird) drops after a reboot

## Repo and checks

**`just check` fails at "rendered_config/example up to date"**
- Cause: a template or `apps.yml` change renders new files, the hook writes them and fails once
- Fix: `git add -A`, commit again

**`rendered_config/example` lost files (many `D` in `git status`)**
- Cause: Ctrl-C during the render step of `just check`
- Fix: `scripts/render_podman.sh example && git add -A rendered_config`, then `git status --short rendered_config` shows only real changes

**Hooks report "files were modified by this hook" with nothing changed**
- Cause: two `just check` runs at the same time
- Fix: one at a time

**ansible ad-hoc mangles `{{ ... }}` (podman/docker `--format`)**
- Cause: Ansible renders `{{ }}` in ad-hoc arguments as Jinja
- Fix: `--format json` and filter with `jq`, or run it over plain `ssh`

**ansible-lint: `partial-become`**
- Fix: `become: true` next to every `become_user:` on the same task

## Secrets

**Never `--diff` a task or file that holds secrets**
- `--diff` prints the old and new content, secrets included, into the terminal, CI logs and Semaphore's run history
- Secret tasks carry `no_log: true` and `diff: false`. If a value was printed anyway: change it in `vault.yml`, deploy the app again, and change it in the app itself where it holds a copy (database users, OIDC clients)

## AIDE

The database hashes are the integrity anchor ([ADR 0009](adr/0009-aide-with-manual-accept.md)):
- ctl-1 holds the reference, `/srv/apps/semaphore/aide/<host>.sha256`. Semaphore's accept runs write there
- The controller's `ansible/aide/` is a copy. After every accept, from either side:
  `rsync -a <admin_user>@<ctl1_ip>:/srv/apps/semaphore/aide/ aide/`
- On ctl-1 the files belong to the subuid that Semaphore's container user maps to. Copying into that dir needs `sudo` and the same owner afterwards
- Renaming a host: rename `<host>.sha256` on both sides, then accept on that host
- "database hash mismatch": the database changed outside an accept, or a copy is stale. Compare both copies first, then look at the host before accepting

## Backups (PBS)

**A run fails with `pg_dump <name>`**
- Cause: the database container isn't running (the app is stopped)
- Fix: start the app, run again (`systemctl start pbs-backup.service`, it waits until done). An empty dump also fails the run on purpose

**A run on a part-time node's guest fails**
- pve-3 holds the datastore. With pve-3 off, every run fails and pushes to ntfy

## Known open

- Chromium hangs on the Authentik redirect for some apps, other browsers log in
