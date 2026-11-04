# ctl_base

- What ctl-1 needs on top of `vm_base` + `podman_base`: static address, ufw, and read access to the checkout for Semaphore
- ctl-1 is a Raspberry Pi 3 B+ on Raspberry Pi OS Lite (trixie, 64-bit) outside the cluster, always on, running the Semaphore app (`apps/semaphore`)

## Runs on

- `podman_hosts` (ctl-1), in `playbooks/ctl-preparation.yml`

## First setup, by hand

1. Raspberry Pi Imager: Raspberry Pi OS Lite (64-bit), hostname `ctl-1`, user `admin_user` with the vault's `sudo_pass`, ssh on
2. From the controller, the key and a first run on the DHCP address:
   ```
   ssh-copy-id <admin_user>@<dhcp ip>
   ansible-playbook playbooks/ctl-preparation.yml -e ansible_host=<dhcp ip>
   ```
   Then reboot ctl-1: it comes back on `ctl1_ip`. `vm_base` turns password logins off
3. `base.yml -l ctl-1`, then `deploy-app.yml -e app=semaphore`
4. Copy the checkout to `semaphore_repo_dir` with the private files as real files, not symlinks:
   ```
   rsync -rLt --delete --delete-excluded \
     --exclude .git --exclude .vault_pass --exclude .ansible --exclude ansible/collections \
     --exclude tofu --exclude 'nixos/result*' --exclude architecture/dist \
     ~/homelab/ ctl-1:homelab/
   ```
   No vault password (it lives in Semaphore's key store), no tofu state, no nix store. `--delete-excluded` cleans up what an older copy left behind.
   Then run `ctl-preparation.yml` again, it sets the ACL on what arrived

## How it works

- Static address: a NetworkManager keyfile (`ctl_base_connection`) with address, gateway and DNS. With it in place NetworkManager no longer creates its in-memory "Wired connection 1". Never reloaded, so the address changes at the next boot
- DNS is the gateway only: the hosts are reached by IP, and `auth.<domain>` is pinned in the quadlet (`AddHost=`)
- ufw: deny in, ssh rate-limited from the LAN, node-exporter from Prometheus only. Semaphore's port comes from `podman_app` (`allow_from`)
- Checkout access: the home dir gets `g:<svc-semaphore gid>:x`, the checkout `rX` plus a default ACL. Set by gid, so it works before the group exists. In the rootless container that gid is gid 0, which the image's `semaphore` user runs as
- The ACL is set again on every run: `rsync -p` copies the source's `0600` and the mask hides the group entry

## Settings

| Variable | Default | What |
|---|---|---|
| `ctl_base_iface` | `eth0` | LAN interface |
| `ctl_base_connection` | `lan` | NetworkManager profile name |
| `ctl_base_ip` | `ctl1_ip` | Static address, prefix from `lan_cidr` |
| `ctl_base_dns` | `[gateway_ip]` | Resolvers, internet names only |
| `ctl_base_repo_dir` | `semaphore_repo_dir` | The checkout (`/home/<admin_user>/homelab`) |
| `ctl_base_repo_gid` | `apps.semaphore.uid` | svc-semaphore's gid |

## Notes

- `vm_base` runs with `vm_base_guest_agent: false` and `vm_base_cockpit: false` here (`host_vars/ctl-1.yml`)
- The journal is volatile and goes to the log CT (`base.yml`: journald + rsyslog), so the SD card only sees Semaphore's SQLite
- No backup: the PBS client is amd64-only. Projects and templates are a few clicks to redo, run history is lost with the card
- Semaphore's own ssh key lives in its key store. Its public key goes into `authorized_keys` on the hosts like the controller's (`push-keys.yml`, on pve once into the cluster-wide `/etc/pve/priv/authorized_keys`)
