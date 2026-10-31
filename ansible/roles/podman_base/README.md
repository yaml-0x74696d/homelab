# podman_base

- What a VM needs before its first rootless Podman app: Podman and auto-update with ntfy
- Per-app parts (svc users, subuid ranges, linger, quadlets, secrets, app firewall rules) are `podman_app`'s job

## Runs on

- `docker_hosts`, in `playbooks/vm-preparation.yml` after `roles/vm_base`. Podman runs next to Docker while the apps move over one by one

## How it works

1. Installs `podman_base_packages`: Podman with `crun`, what Debian only recommends for rootless (`passt`, `uidmap`, `dbus-user-session`, `catatonit`), `systemd-container`, `acl`, `jq`
2. `short-name-mode = "enforcing"` in `/etc/containers/registries.conf.d/`: an ambiguous short image name fails instead of picking a registry
3. Group `podman_svc_group` (`svc-apps`) and `/etc/podman-ntfy.env` (root:svc-apps, 0640) with the ntfy URL and token
4. Drop-ins in `/etc/systemd/user/` for every user:
   - `podman-auto-update.timer`: `OnCalendar=` cleared, then `podman_base_auto_update_time`
   - `podman-auto-update.service`: runs the wrapper (`podman_base_wrapper`) instead of `podman auto-update`

## The auto-update wrapper

- Runs `podman auto-update --format json` as the svc user, the JSON lands in that user's journal
- Pushes updated units at default priority, rolled back or failed units and a non-zero exit at high priority
- Quiet when nothing changed
- Exits 1 on rolled back / failed, so the unit shows as failed in `systemctl --user`

## Settings

| Variable | Default | What |
|---|---|---|
| `podman_base_packages` | see above | Package set |
| `podman_base_wrapper` | `/usr/local/bin/podman-auto-update-ntfy` | The auto-update wrapper |
| `podman_base_ntfy_env` | `/etc/podman-ntfy.env` | ntfy settings for the wrapper |
| `podman_base_auto_update_time` | `Sun *-*-* 13:00:00` | One schedule for every svc user. Upstream adds `RandomizedDelaySec=900` |
| `podman_svc_group` | group_vars `app_settings.yml` | Shared with `roles/podman_app` |
| `ntfy_url`, `ntfy_token`, `ntfy_timeout` | group_vars / vault | Shared ntfy settings. With an empty URL nothing is pushed |

## Notes


- `crun`, not `runc`: Docker's `containerd.io` conflicts with Debian's `runc` package

- Loopback is always accepted, so apps on the same VM reach each other's ports (the VM is the trust boundary, see the Podman plan)
- No firewall here: ufw stays the host firewall (`vm-preparation.yml`), `roles/podman_app` adds each app's rules. firewalld is out on Debian: cloud-init conflicts with it (Debian #1025618, a boot ordering cycle)
- Published rootless ports are plain host sockets (pasta), so ufw filters them directly. No `DOCKER-USER` workaround
