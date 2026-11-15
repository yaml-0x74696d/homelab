# ctl_base

- What ctl-1 needs on top of `vm_base` + `podman_base`: static address, ufw, the git clone Semaphore runs from and a copy of the private overlay dir
- ctl-1 is a Raspberry Pi 3 on Raspberry Pi OS Lite (trixie, 64-bit) outside the cluster, always on, running the Semaphore app (`apps/semaphore`)

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
4. `ctl-preparation.yml` clones `ctl_base_repo_url` (branch `ctl_base_repo_version`) copies the gitignored `ctl_base_private_files` from the controller's checkout and sets up Syncthing (below)
5. AIDE hashes and overlays: Syncthing brings them over once ctl-0 is paired (below)

## How it works

- Static address: a NetworkManager keyfile (`ctl_base_connection`) with address, gateway and DNS. With it in place NetworkManager no longer creates its in-memory "Wired connection 1". Never reloaded, so the address changes at the next boot
- DNS is the gateway only: the hosts are reached by IP, and `auth.<domain>` is pinned in the quadlet (`AddHost=`)
- ufw: deny in, ssh rate-limited from the LAN, node-exporter from Prometheus only, Syncthing (`syncthing_port`) from the LAN. Semaphore's port comes from `podman_app` (`allow_from`)
- The clone: `ctl-preparation.yml` clones once, after that `playbooks/repo-pull.yml` pulls (a Semaphore template). Vault password and tofu state never land on ctl-1, the vault password lives in Semaphore's key store
- Private files: `vault.yml` and `private.yml` are gitignored, so they're copied from the controller. After a change to them on ctl-0: `ctl-preparation.yml -l ctl-1 -t private-files`. Mode `0640`, `0600` would hide the ACL entry behind the mask
- Private dir: the controller's `<private_dir>/apps` (the app roles' config overlays) syncs both ways with `<ctl_base_private_dir>/apps` through Syncthing, deletions included. Only `apps/`: `private_dir` also holds the vault password, keys and tofu state, which stay on the controller. So a Semaphore deploy lays the same private files over the public ones and doesn't drop them as stale. The quadlet mounts it read-only at the same path and sets `HOMELAB_PRIVATE_DIR` to it: `private.yml`'s `~/...` would expand to the container user's home there, `podman_app` reads the env var first
- Vault password: `ansible.cfg`'s `vault_password_file` has to exist, so the clone gets a `dummy` one (`ctl_base_vault_pass_dummy`), like CI. Ansible tries every vault secret, the real one comes from Semaphore's key store
- Owner: the clone, the private files and the overlay copy belong to `admin_user` (`ansible_become: false` on those tasks, the inventory's become would beat the keyword). Root only sets the ACLs
- Checkout access: the home dir gets `g:<svc-semaphore gid>:x`, the clone and the private dir `rX` plus a default ACL that covers later pulls. The `rX` pass reruns with `-t private-files`, since copy resets the mask. Syncthing runs with `ignorePerms`, so it never touches the mask. Set by gid, so it works before the group exists. In the rootless container that gid is gid 0, which the image's `semaphore` user runs as
- AIDE hashes: Semaphore keeps them in its own rw dir (`/srv/apps/semaphore/aide`, `AIDE_CHECKSUM_DIR` in the quadlet, passed to tasks through `SEMAPHORE_FORWARDED_ENV_VARS`), the reference for every host. Syncthing keeps it and ctl-0's `ansible/aide` the same, both ways: an accept on either side reaches the other within seconds. The ACLs give `admin_user` (Syncthing) and Semaphore's container user (`ctl_base_semaphore_uid`) write access

## Syncthing with ctl-0

ctl-1's side is this role (`tasks/syncthing.yml`, tag `syncthing`): the Debian package as `syncthing@<admin_user>`, LAN only (no global discovery, relays, NAT traversal or usage reports), GUI and API on `127.0.0.1:8384`. Two folders, both send and receive:

| Folder id | ctl-1 | ctl-0 |
|---|---|---|
| `homelab-aide` | `/srv/apps/semaphore/aide` | `~/homelab-sync/aide` (`ansible/aide` links here) |
| `homelab-private` | `<ctl_base_private_dir>/apps` | `~/homelab-sync/apps` (`private_dir`) |

On ctl-0 both folders live in `~/homelab-sync`, outside the secure storage: Syncthing never touches the folder with the vault password, keys and tofu state. A daily rsync on ctl-0 copies the folder into the secure storage, one way (step 8). `private_dir` points at it, `ansible/aide` is a symlink into it.

ctl-0 by hand, once:
1. `mkdir -p ~/homelab-sync/{apps,aide}`, move the overlays and hashes in, `private_dir: ~/homelab-sync` in `private.yml`, `ln -sfn ~/homelab-sync/aide ~/homelab/ansible/aide`
2. `sudo pacman -S syncthing`, then `systemctl --user enable --now syncthing`
3. `syncthing device-id` (2.x, `--device-id` on 1.x) into `private.yml` as `syncthing_ctl0_id`, then `ansible-playbook playbooks/ctl-preparation.yml -l ctl-1 -t private-files,syncthing`
4. GUI on `http://127.0.0.1:8384`, Settings → Connections: global discovery, local discovery, relays and NAT traversal off
5. Add device: ctl-1's id (`ssh ctl-1 syncthing --device-id`, Debian ships 1.x), address `tcp://<ctl1_ip>:22000`
6. Accept the two folders ctl-1 offers, with the paths from the table, "Ignore Permissions" on. On `homelab-aide`: File Versioning → Simple, so every overwritten hash stays in `.stversions` (ADR 0039)
7. `.stignore` with `.git` in `<private_dir>/apps`, Syncthing never syncs that file itself
8. The off-site copy: `cp files/ctl-0/homelab-sync-copy.{service,timer} ~/.config/systemd/user/`, `~/.config/homelab-sync-copy.env` with `SYNC_COPY_DEST=<secure storage>/homelab/sync-copy`, then `systemctl --user enable --now homelab-sync-copy.timer`. Daily at 21:00, rsync mirrors `~/homelab-sync` into `<secure storage>/homelab/sync-copy`, one way, without Syncthing's own files. The secure storage keeps the versions

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
| `ctl_base_private_dir` | `semaphore_private_dir` | ctl-1's copy (`/home/<admin_user>/homelab-private`) |
| `ctl_base_private_excludes` | `[.git]` | Syncthing's `.stignore` in the overlays |
| `ctl_base_syncthing_peer_id` | `syncthing_ctl0_id` | ctl-0's device id from `private.yml`, empty = no device or folders yet |
| `ctl_base_syncthing_home` | `~<admin_user>/.local/state/syncthing` | Holds `config.xml` with the API key |
| `ctl_base_syncthing_aide_dir` | `/srv/apps/semaphore/aide` | The synced hash dir |
| `ctl_base_semaphore_uid` | subuid start + 1000 | Semaphore's container user on the host |
| `ctl_base_vault_pass_dummy` | `ansible/.vault_pass` | Placeholder for `vault_password_file` |

## Notes

- `vm_base` runs with `vm_base_guest_agent: false` and `vm_base_cockpit: false` here (`host_vars/ctl-1.yml`)
- The journal is volatile and goes to the log CT (`base.yml`: journald + rsyslog), so the SD card only sees Semaphore's SQLite
- No backup: the PBS client is amd64-only. Projects and templates are a few clicks to redo, run history is lost with the card. The AIDE hashes survive as ctl-0's copy
- Semaphore's own ssh key lives in its key store. Its public key goes into `authorized_keys` on the hosts like the controller's (`push-keys.yml`, on pve once into the cluster-wide `/etc/pve/priv/authorized_keys`)
