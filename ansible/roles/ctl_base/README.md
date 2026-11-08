# ctl_base

- What ctl-1 needs on top of `vm_base` + `podman_base`: static address, ufw, the git clone Semaphore runs from and a copy of the private overlay dir
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
4. `ctl-preparation.yml` clones `ctl_base_repo_url` (branch `ctl_base_repo_version`) copies the gitignored `ctl_base_private_files` from the controller's checkout and mirrors `<private_dir>/apps`
5. AIDE hashes: copy the controller's `ansible/aide/*.sha256` once into Semaphore's `aide` dir, owned by the container's uid 1001:
   ```
   ansible ctl-1 -b -m copy -a "src=aide/ dest=/srv/apps/semaphore/aide/ owner=<subuid of 1001> group=<subuid of 1001> mode=0644"
   ```

## How it works

- Static address: a NetworkManager keyfile (`ctl_base_connection`) with address, gateway and DNS. With it in place NetworkManager no longer creates its in-memory "Wired connection 1". Never reloaded, so the address changes at the next boot
- DNS is the gateway only: the hosts are reached by IP, and `auth.<domain>` is pinned in the quadlet (`AddHost=`)
- ufw: deny in, ssh rate-limited from the LAN, node-exporter from Prometheus only. Semaphore's port comes from `podman_app` (`allow_from`)
- The clone: `ctl-preparation.yml` clones once, after that `playbooks/repo-pull.yml` pulls (a Semaphore template). Vault password and tofu state never land on ctl-1, the vault password lives in Semaphore's key store
- Private files: `vault.yml` and `private.yml` are gitignored, so they're copied from the controller. After a change to them or to `private_dir` on ctl-0: `ctl-preparation.yml -l ctl-1 -t private-files`. Mode `0640`, `0600` would hide the ACL entry behind the mask
- Private dir: the controller's `<private_dir>/apps` (the app roles' config overlays) is mirrored with rsync to `<ctl_base_private_dir>/apps`, deletions included. Only `apps/`: `private_dir` also holds the vault password, keys and tofu state, which stay on the controller. So so a Semaphore deploy lays the same private files over the public ones and doesn't drop them as stale. Same tag, same run as the private files. The quadlet mounts it read-only at the same path and sets `HOMELAB_PRIVATE_DIR` to it: `private.yml`'s `~/...` would expand to the container user's home there, `podman_app`/`docker_app` read the env var first
- Vault password: `ansible.cfg`'s `vault_password_file` has to exist, so the clone gets a `dummy` one (`ctl_base_vault_pass_dummy`), like CI. Ansible tries every vault secret, the real one comes from Semaphore's key store
- Owner: the clone, the private files and the overlay copy belong to `admin_user` (`ansible_become: false` on those tasks, the inventory's become would beat the keyword). Root only sets the ACLs
- Checkout access: the home dir gets `g:<svc-semaphore gid>:x`, the clone and the private dir `rX` plus a default ACL that covers later pulls. The `rX` pass reruns with `-t private-files`, since copy and rsync reset the mask. Set by gid, so it works before the group exists. In the rootless container that gid is gid 0, which the image's `semaphore` user runs as
- AIDE hashes: Semaphore keeps them in its own rw dir (`/srv/apps/semaphore/aide`, `AIDE_CHECKSUM_DIR` in the quadlet, passed to tasks through `SEMAPHORE_FORWARDED_ENV_VARS`), the reference for every host. ctl-0's `ansible/aide` is a copy, pull it back after accepts:
  ```
  rsync -rt ctl-1:/srv/apps/semaphore/aide/ ~/homelab/ansible/aide/
  ```

## Settings

| Variable | Default | What |
|---|---|---|
| `ctl_base_iface` | `eth0` | LAN interface |
| `ctl_base_connection` | `lan` | NetworkManager profile name |
| `ctl_base_ip` | `ctl1_ip` | Static address, prefix from `lan_cidr` |
| `ctl_base_dns` | `[gateway_ip]` | Resolvers, internet names only |
| `ctl_base_repo_dir` | `semaphore_repo_dir` | The clone (`/home/<admin_user>/homelab`) |
| `ctl_base_repo_url` | `semaphore_repo_url` | Repo to clone |
| `ctl_base_repo_version` | `semaphore_repo_version` | Branch, `repo-pull.yml` follows it |
| `ctl_base_repo_gid` | `apps.semaphore.uid` | svc-semaphore's gid |
| `ctl_base_private_files` | `vault.yml`, `private.yml` | Gitignored files copied from the controller |
| `ctl_base_private_src` | `<private_dir>/apps` | The controller's overlays. Empty or missing = no sync |
| `ctl_base_private_dir` | `semaphore_private_dir` | ctl-1's copy (`/home/<admin_user>/homelab-private`) |
| `ctl_base_private_excludes` | `[.git]` | Left out of the sync |
| `ctl_base_vault_pass_dummy` | `ansible/.vault_pass` | Placeholder for `vault_password_file` |

## Notes

- `vm_base` runs with `vm_base_guest_agent: false` and `vm_base_cockpit: false` here (`host_vars/ctl-1.yml`)
- The journal is volatile and goes to the log CT (`base.yml`: journald + rsyslog), so the SD card only sees Semaphore's SQLite
- No backup: the PBS client is amd64-only. Projects and templates are a few clicks to redo, run history is lost with the card. The AIDE hashes survive as ctl-0's copy
- Semaphore's own ssh key lives in its key store. Its public key goes into `authorized_keys` on the hosts like the controller's (`push-keys.yml`, on pve once into the cluster-wide `/etc/pve/priv/authorized_keys`)
