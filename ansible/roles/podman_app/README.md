# podman_app

- Deploys one rootless Podman app from its entry in `group_vars/all/apps.yml` and its unit templates in `apps/<name>/`
- One user per app (`svc-<name>`), quadlets in that user's `~/.config/containers/systemd/`, data in `/srv/apps/<name>`
- Built so far: single-container apps with secrets, no CIFS or keep-id yet. The role refuses an entry that needs more

## Runs on

- The app's `host:` from the map, through `playbooks/deploy-app.yml`:
  ```
  ansible-playbook playbooks/deploy-app.yml -e app=gatus
  ```
- Needs `roles/podman_base` on that host first

## How it works

1. Checks the entry: `runtime: podman`, `state: present`, the right host, only built features, one source per secret, a template per container, known `allow_from` names
2. Writes `svc-<name>:<uid*65536>:65536` to `/etc/subuid` and `/etc/subgid` **before** creating the user, so useradd doesn't add a second range. Then checks there's exactly one line each
3. Creates group + user `svc-<name>` with the map's `uid`: locked password, `nologin`, member of `svc-apps` (may read the ntfy env file)
4. Linger, then starts `user@<uid>.service`. A range change on an existing user runs `podman system migrate`
5. Data dir `/srv/apps/<name>` (+ `dirs`), owned by `svc-<name>`
6. Unit files for each container:
   - `container.d/10-homelab.conf`: house rules (`Notify=healthy`, `HealthOnFailure=kill`, restart with backoff, start timeout, `WantedBy=default.target`)
   - `<container>.container.d/50-map.conf`: what the map says (image + tag, `AutoUpdate=registry` unless `auto_update: false`, `User=`, `StopTimeout=`, `Notify=false` + `HealthOnFailure=none` for `healthcheck: false`, `NoNewPrivileges=`, caps, `ReadOnly=`)
   - `<container>.container`: rendered from `apps/<name>/<container>.container.j2` (volumes, ports, env, health)
7. ufw: one rule per port and `allow_from` source
8. Podman secrets as the user: the value from the vault variable or the rendered template, replaced only when the content differs (`podman secret inspect --showsecret`)
9. Pulls the images as the user (so a pull never eats the start timeout), reloads + restarts on unit changes, starts the units
10. Enables the user's `podman-auto-update.timer` (schedule + ntfy wrapper from `roles/podman_base`), prunes old images

## The apps.yml entry

Full schema with defaults: `meta/argument_specs.yml`.

```yaml
apps:
  gatus:
    host: docker-2
    uid: 2010                     # svc-gatus, subuid range 2010*65536
    port: 3001
    allow_from: [edge, netbird]   # names from app_sources, or another app
    secrets:
      - name: gatus-config        # rendered from apps/gatus/config.yaml.j2
        template: config.yaml.j2
    dirs:
      - path: data
    containers:
      - name: gatus               # apps/gatus/gatus.container.j2
        image: ghcr.io/twin/gatus
        tag: stable
        healthcheck: false        # scratch image, nothing to run a check with
        add_caps: [NET_RAW]
    routes:
      - host: status              # read by edge and gatus, not by this role
```

- `runtime: compose` marks an app that still runs on Docker: edge routes it, gatus checks it, `deploy-app.yml` refuses it
- A secret's `Secret=` line (env or mount, target) is in the app's unit template, the map only says where the value comes from
- `allow_from` names resolve through `app_sources` (`group_vars/all/app_settings.yml`), an app name to its host's IP

## Settings

| Variable | Default | What |
|---|---|---|
| `podman_app_name`, `podman_app_entry` | set by `deploy-app.yml` | The app's key and entry |
| `podman_app_subid_count` | `65536` | Size of each subuid/subgid range |
| `podman_app_start_timeout` | `5min` | `TimeoutStartSec=` when the entry has no `start_timeout` |
| `podman_app_stop_timeout` | `10` | `StopTimeout=` when a container has no `stop_timeout` |
| `podman_app_restart_sec` / `_steps` / `_max_delay` | `30s` / `5` / `10min` | Retry forever with backoff |
| `podman_apps_root` | `/srv/apps` (group_vars) | Data dirs, backed up by `roles/pbs` |
| `podman_svc_prefix`, `podman_svc_group` | `svc-`, `svc-apps` (group_vars) | Shared with `roles/podman_base` and the aide excludes |

## Notes

- Drop-ins override the main file, so a template can't change a house rule or a map field. Change the map or the default instead
- Every container needs a `HealthCmd=`: `Notify=healthy` waits for it, so a container without one never counts as started. An image that can't run one (scratch) gets `healthcheck: false`
- No comments at the end of a line in the templates: systemd reads them as part of the value
- Quadlets can't be enabled. `WantedBy=default.target` starts them with the user manager, which linger starts at boot
- The tasks that need the svc user skip in `--check` until the user exists
