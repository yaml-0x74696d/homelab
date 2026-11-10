# Updates

What updates itself, what waits for a run, and how the pinned parts move. Times live in `group_vars/all/schedules.yml`.

## What runs on its own

| What | When | How | Reports |
|---|---|---|---|
| App images on a floating tag (`latest`, `stable`, `alpine`, ...) | Sun 13:00 | `podman auto-update` per svc user, rolls back when the new container fails its health check ([ADR 0021](adr/0021-podman-quadlets.md)) | ntfy: updated, rolled back, failed |
| Newer tags of pinned images | Sun 12:00 | `podman-new-tags` lists newer tags of the same shape (`16-alpine` → `17-alpine`) | ntfy, nothing is changed |
| Security updates, pod VMs and LXCs | daily | unattended-upgrades, security origins only, no reboot ([ADR 0024](adr/0024-ansible-run-os-updates.md)) | |
| NixOS VMs | netbird 03:00, edge 04:00 | `system.autoUpgrade`, reboots only inside their window, one after the other | |
| Home Assistant OS | in HA | HA's own updates, Ansible never logs in | HA |

## Debian hosts: `update.yml`

All apt hosts in one run: the LXCs, then the pod VMs and ctl-1, then the PVE nodes, one host at a time. Semaphore runs it on its schedule, by hand:

```bash
ansible-playbook playbooks/update.yml
```

- `dist-upgrade`, then `needrestart` restarts what runs on old libraries. Nothing reboots
- AIDE is checked before and re-baselined after, so an update needs no accept, unless the host was dirty before
- The summary at the end (terminal + ntfy) is the to-do list. How to read it: [`roles/update/README.md`](../ansible/roles/update/README.md#reading-the-summary)

Reboots, when the summary says `REBOOT due`:
- A pod VM: `ssh pod-N sudo reboot`. Its apps start again on their own (`WantedBy=default.target`, linger). pod-1 takes SSO down for a minute, pod-2 the VPN routing and DNS for VPN clients
- A PVE node: shut its guests down first, then reboot the node. pve-1 carries edge (LAN DNS + every route) and the IoT gateway
- Never two nodes at once, the cluster needs quorum

## Pinned images

Auto-update only refreshes the tag an app pins. `podman-new-tags` says when a newer one exists, the bump is a change in `group_vars/all/apps.yml` plus a deploy:

```bash
just deploy-app <app>
```

Images that need more than a tag change:
- **Postgres major** (`16-alpine` → `17-alpine`): the data dir doesn't open on a new major. Dump, start empty on the new tag, import:
  1. `ssh pod-N sudo systemctl start pbs-backup.service` (fresh dump on PBS, and in the staging dir until the run ends)
  2. Stop the app, move `/srv/apps/<app>/database` aside
  3. Bump the db tag, deploy: the db starts empty
  4. Import the dump as in [bootstrap step 7](bootstrap.md#7-restore-the-data), start the app, then delete the old dir
- **Nextcloud** (`35-apache`): one major at a time, it refuses to skip. `start_timeout: 15min` covers `occ upgrade` on the first start
- **Authentik**: one release series at a time, never down. Raise the tag on `authentik` and `authentik-worker` in `apps.yml`, then `just deploy authentik`. The wrapper refuses skipped series, downgrades and a nearly full thin pool, and waits for ready through edge ([ADR 0014](adr/0014-authentik-as-idp.md)). Add the new series to `authentik_series` in `app_settings.yml`
- **Immich's Postgres** (vectorchord build): follow the Immich release notes, never plain Postgres
- **Gotenberg** `8`, **Valkey** `8-alpine` / `9`: a major bump is a tag change, check the release notes first

## NixOS VMs by hand

```bash
nixos/update.sh <netbird|edge>
```

- Bumps the flake inputs, builds locally (catches option renames before anything is live), switches, lists failed units
- If the switch over SSH hangs: [troubleshooting](troubleshooting.md#nixos-vms-netbird-edge)
- After a switch: `nixos/aide-accept.sh <host>`, then sync the hashes ([troubleshooting, AIDE](troubleshooting.md#aide))
- Rollback: boot the previous generation, or `switch-to-configuration` of an older system profile

## Proxmox

- Package updates come with `update.yml` (the `proxmox` play checks quorum before and after)
- A major PVE release: one node at a time, after the official upgrade checker (`pve<N>to<N+1> --full`) is clean. Guests of that node off or moved first

## The next Debian release

- Debian 13 gets security updates until mid-2028. The guests move before that
- The pod VMs: in place (`dist-upgrade` to the new release, one VM at a time), or rebuilt from OpenTofu with a new image and the data restored. A rebuild needs a restore rehearsal first ([restore-rehearsal.md](restore-rehearsal.md))
- The LXCs: a new template in `tofu/locals.tf`, rebuilt, `base.yml` again
- The PVE nodes follow Proxmox's release, not Debian's
- Before a guest OS change, check the EL10 list in [bootstrap.md](bootstrap.md#guests-on-el10-what-changes) for what else moves with it

## After any update

- AIDE: `update.yml` accepts by itself. Anything else (a NixOS switch, a manual package) needs `aide-accept.yml -l <host>` or `nixos/aide-accept.sh <host>`, then the hash sync
- Look at Gatus (every route and host) and Homepage once
