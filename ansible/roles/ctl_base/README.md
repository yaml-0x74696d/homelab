# ctl_base

- What ctl-1 needs on top of `vm_base` + `podman_base`: static address, ufw, and read access to the checkout for Semaphore
- ctl-1 is a Raspberry Pi 3 B+ outside the cluster, always on, running the Semaphore app (`apps/semaphore`)

## Runs on

- `podman_hosts` (ctl-1), in `playbooks/ctl-preparation.yml`

## First setup, by hand

1. Flash the Debian raspi image (trixie, arm64) to the SD card. In `sysconf.txt` on the boot partition set `root_authorized_key` and `hostname=ctl-1`
2. In `/etc/network/interfaces.d/eth0` set the static address from `ctl1_ip` (the role keeps that file afterwards)
3. As root over ssh: create `admin_user` with your key, sudo with `sudo_pass`:
   ```
   adduser <admin_user>
   usermod -aG sudo <admin_user>
   install -d -m 700 -o <admin_user> -g <admin_user> /home/<admin_user>/.ssh
   cp /root/.ssh/authorized_keys /home/<admin_user>/.ssh/ && chown <admin_user>: /home/<admin_user>/.ssh/authorized_keys
   ```
4. From the controller: `ctl-preparation.yml`, `base.yml -l ctl-1`, then `deploy-app.yml -e app=semaphore`. `vm_base` turns root login off
5. Copy the checkout to `semaphore_repo_dir` with the private files as real files, not symlinks:
   ```
   rsync -rLt --exclude .git --exclude ansible/collections ~/homelab/ ctl-1:homelab/
   ```
   Then run `ctl-preparation.yml` again, it sets the ACL on what arrived

## How it works

- Static address: `/etc/network/interfaces.d/<iface>` and `/etc/resolv.conf`. Never restarts networking, a wrong file shows up at the next boot
- ufw: deny in, ssh rate-limited from the LAN, node-exporter from Prometheus only. Semaphore's port comes from `podman_app` (`allow_from`)
- Checkout access: the home dir gets `g:<svc-semaphore gid>:x`, the checkout `rX` plus a default ACL. Set by gid, so it works before the group exists. In the rootless container that gid is gid 0, which the image's `semaphore` user runs as
- The ACL is set again on every run: `rsync -p` copies the source's `0600` and the mask hides the group entry

## Settings

| Variable | Default | What |
|---|---|---|
| `ctl_base_iface` | `eth0` | LAN interface (the raspi image keeps the old names) |
| `ctl_base_ip` | `ctl1_ip` | Static address, prefix from `lan_cidr` |
| `ctl_base_dns` | `[gateway_ip]` | Resolvers, like the other hosts |
| `ctl_base_repo_dir` | `semaphore_repo_dir` | The checkout (`/home/<admin_user>/homelab`) |
| `ctl_base_repo_gid` | `apps.semaphore.uid` | svc-semaphore's gid |

## Notes

- `vm_base` runs with `vm_base_guest_agent: false` and `vm_base_cockpit: false` here (`host_vars/ctl-1.yml`)
- The journal is volatile and goes to the log CT (`base.yml`: journald + rsyslog), so the SD card only sees Semaphore's SQLite
- No backup: the PBS client is amd64-only. Projects and templates are a few clicks to redo, run history is lost with the card
- Semaphore's own ssh key lives in its key store. Its public key goes into `authorized_keys` on the hosts like the controller's (`push-keys.yml`)
