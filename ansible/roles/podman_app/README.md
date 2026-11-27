# podman_app

- Deploys one rootless Podman app from its entry in `group_vars/all/apps.yml` and its unit templates in `apps/<name>/`
- One user per app (`svc-<name>`), quadlets in that user's `~/.config/containers/systemd/`, data in `/srv/apps/<name>`
- Built: single- and multi-container apps (one pod), secrets, pool shares over CIFS, keep-id, devices. No per-app `.network` or init containers. The role refuses an entry that needs more

## Runs on

- The app's `host:` from the map, through `playbooks/deploy-app.yml`:
  ```
  ansible-playbook playbooks/deploy-app.yml -e app=gatus
  ```
- Needs `roles/podman_base` on that host first

## How it works

1. Checks the entry: `runtime: podman`, `state: present`, the right host (a `hosts:` entry: no port, routes, tiles or sources), unique container names, one named like the app and the rest `<name>-<role>`, `after`/`cifs` only naming what the entry has, `user` on every container with `container_uid`, a password per CIFS user, one source per secret, a template per container (+ `<name>.pod.j2` for a pod), known `allow_from` names (single-host apps only)
2. Writes `svc-<name>:<uid*65536>:65536` to `/etc/subuid` and `/etc/subgid` before creating the user, so useradd doesn't add a second range. Then checks there's exactly one line each
3. Creates group + user `svc-<name>` with the map's `uid`: locked password, `nologin`, member of `svc-apps` (may read the ntfy env file) and of each `devices` entry's group on the host (`render` for `/dev/dri/renderD128`)
4. Linger, then starts `user@<uid>.service`. A range change on an existing user runs `podman system migrate`
5. Data dir `/srv/apps/<name>` (+ `dirs`), owned by `svc-<name>`. A dir with `owner: <uid>` belongs to that uid inside the container instead (host id `uid*65536 + owner - 1`, with keep-id see below), and the app dir becomes `0711` so the uid can pass through
6. Pool shares (`cifs`): `cifs-utils`, `/etc/cifs/<share>.creds` (root, `0600`, password from `smb_passwords`), an fstab line at `cifs_mount_root/<path>` with `uid`/`gid` = `svc-<name>`, `nofail` and `x-systemd.automount`, then the automount unit started. A changed line unmounts the share so the next access mounts the new options, and restarts the app
7. Unit files for each container:
   - `container.d/10-homelab.conf`: house rules (`Notify=healthy`, `HealthOnFailure=kill`, restart with backoff, start timeout, `WantedBy=default.target`)
   - `<container>.container.d/50-map.conf`: what the map says (image + tag, `AutoUpdate=registry` unless `auto_update: false`, `Pod=` or `UserNS=keep-id`, `User=`, `StopTimeout=`, `Notify=false` + `HealthOnFailure=none` for `healthcheck: false`, `NoNewPrivileges=`, caps, `ReadOnly=`, `AddDevice=` + `GroupAdd=keep-groups`, `Requires=` + `After=` for `after`, the mount gate for `cifs`)
   - `<container>.container`: rendered from `apps/<name>/<container>.container.j2` (volumes, ports, env, health)
   - a pod also gets `<name>.pod` from `apps/<name>/<name>.pod.j2` (ports, `AddHost=`) and `<name>.pod.d/50-map.conf` (`PodName=`, `UserNS=keep-id`)
8. Config: `apps/<name>/config/` mirrored to `/srv/apps/<name>/config/`, `*.j2` rendered, the rest copied, files gone from the repo removed. With `private_dir` set (in `private.yml`), `<private_dir>/apps/<name>/config/` lays over it: plain files, no templates, a file there replaces the public one with the same path and is never shown in `--diff`. A set `private_dir` without `apps/` fails the deploy, a silent public-only run would drop the private files as stale. Owned by root and world-readable (worker uids land on subuids), so the app can't rewrite it; units mount it `:ro`. A change restarts the app
9. ufw: one rule per port and `allow_from` source, commented `podman <name>`. Rules with that comment the entry doesn't list are deleted
10. Podman secrets as the user: the value from the vault variable or the rendered template, replaced only when the content differs (`podman secret inspect --showsecret`)
11. Pulls the images as the user (so a pull never eats the start timeout), reloads + restarts on unit changes (a pod as a whole, `<name>-pod.service`), starts the units
12. Enables the user's `podman-auto-update.timer` (schedule + ntfy wrapper from `roles/podman_base`), then `podman image prune -af`: every image the app doesn't run goes, old tags too. Each app has its own user, so this never touches another app's images

## The apps.yml entry

Full schema with defaults: `meta/argument_specs.yml`.

```yaml
apps:
  gatus:
    host: pod-2
    uid: 2010                     # svc-gatus, subuid range 2010*65536
    port: 3001
    allow_from: [edge, netbird, homepage, pod-1, pod-3]   # names from app_sources, or another app
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
        add_caps: [NET_RAW]       # runs as root in the container, so pings use raw sockets
    routes:
      - host: status              # read by edge and gatus, not by this role
        middlewares: [authentik]
```

An app with more than one container runs as one pod:

```yaml
  paperless:
    host: pod-3
    uid: 2100
    port: 8083
    allow_from: [edge, netbird, homepage]
    secrets:
      - name: paperless-db-pass
        vault: paperless_db_pass
    container_uid: 1000           # the image drops to 1000, keep-id puts it on svc-paperless
    dirs:
      - path: data
      - path: database
        owner: 70                 # postgres in the alpine image
        mode: "0700"              # initdb sets it, 0750 would flip back each run
    cifs:
      - {share: documents, user: paperless, path: documents}   # /srv/documents, password: smb_passwords.paperless
    containers:
      - name: paperless           # the main one is named like the app (apps logs paperless)
        image: ghcr.io/paperless-ngx/paperless-ngx
        tag: latest
        user: "0:0"               # s6 starts as root, then drops to USERMAP_UID
        after: [paperless-db, paperless-redis]
        cifs: [documents]         # waits for the share
      - name: paperless-db
        image: docker.io/library/postgres
        tag: 16-alpine
        user: "70:70"
      - name: paperless-redis
        image: docker.io/library/redis
        tag: 8-alpine
        user: "999:1000"
    routes:
      - host: paperless
```

(trimmed: more secrets, two more containers, the homepage tile)

- A pod shares one network: the containers reach each other on `127.0.0.1:<port>`, not by name. `PublishPort=` and `AddHost=` go in `apps/<name>/<name>.pod.j2`, podman refuses them on a pod's container (`scripts/check_wiring.py` checks that)
- `after` waits for the other container's health (`Notify=healthy`), like compose's `service_healthy`. `Requires=` also stops and restarts it with that container
- `container_uid` sets `UserNS=keep-id:uid=<n>,gid=<n>`, on the pod for a pod. That uid is then `svc-<name>` on the host, so it owns the data dirs without `owner` and the CIFS files. A `dirs` owner below it maps to `uid*65536 + owner`, above it to `uid*65536 + owner - 1`
- Keep-id makes `svc-<name>`'s uid the default user, so every container states its `user` (root for images that drop privileges themselves)
- `cifs` mounts the share on the host, the unit template bind-mounts `cifs_mount_root/<path>`. A container listing the path in its own `cifs` waits for it: `ExecStartPre=` `ls` (triggers the automount), then `findmnt -t cifs`, with `Restart=` retrying
- `devices` adds `AddDevice=` and `GroupAdd=keep-groups`, and puts `svc-<name>` in the device's group on the host
- `ShmSize=`, `Tmpfs=`, `Exec=` are plain unit keys: they go in the template, not the map. In a pod `ShmSize=` goes in the pod template (one IPC namespace)
- `hosts: [a, b]` instead of `host:` runs one copy on each host (cloudflare-ddns). Only for apps nothing reaches: no port, routes, homepage or `allow_from`, those resolve the app to one host
- Config vs secrets: anything secret goes in `secrets:` (a podman secret), plain config and static files in `apps/<name>/config/`
- A secret's `Secret=` line (env or mount, target) is in the app's unit template, the map only says where the value comes from
- `allow_from` names resolve through `app_sources` (`group_vars/all/app_settings.yml`), an app name to its host's IP

## Owner mapping

Copying data into a rootless app: the files need the owner the container sees, in host ids.

- Without `container_uid` (no keep-id): container root is `svc-<app>`, container uid `n` is `S + n - 1`
- With `container_uid: c`: `c` is `svc-<app>`, `n < c` is `S + n`, `n > c` is `S + n - 1`
- `S` is the svc user's subuid start: `uid × 65536` (`grep svc-<app> /etc/subuid`)
- Check the real owners of the source first: `sudo find <dir> -printf "%u:%g\n" | sort | uniq -c`
- Example, Authentik (uid 2170, `S` = 142213120): postgres 70 → 142213189, authentik 1000 → 142214119

## Rendered for review

`rendered_config/example/` has every Podman app as this role writes it, filled in with the example values: `<app>.container`, `container.d/10-homelab.conf`, `<app>.container.d/50-map.conf`, `config/` and `secrets/<name>` (what each podman secret holds). Vault values show as `<vault:name>`.

`just render` (`scripts/render_podman.sh example`) rebuilds it from a copy of the repo with the example files in place: `playbooks/render-podman.yml` runs `tasks/render.yml`, the same templates and vars as `main.yml`, without touching a host. CI fails when it's stale.

## Settings

<!-- settings:start -->
| Variable | Default | What |
|---|---|---|
| `podman_app_name` | `""` | The app's key in apps.yml, also the name of apps/\<name>/ and svc-\<name>. Set by deploy-app.yml |
| `podman_app_entry` | `{}` | The app's entry in apps.yml. Set by deploy-app.yml |
| `podman_app_private_dir` | see `defaults/main.yml` | Root of the private config overlay. Default `$HOMELAB_PRIVATE_DIR`, else `private_dir`. Semaphore sets the env var to its mount of ctl-1's copy (roles/ctl_base). empty = none |
| `podman_app_user` | `{{ podman_svc_prefix }}{{ podman_app_name }}` | built from the name, not meant to be set |
| `podman_app_home` | `/home/{{ podman_app_user }}` | built from the name, not meant to be set |
| `podman_app_dir` | `{{ podman_apps_root }}/{{ podman_app_name }}` | built from the name, not meant to be set |
| `podman_app_src` | `{{ playbook_dir }}/../apps/{{ podman_app_name }}` | built from the name, not meant to be set |
| `podman_app_quadlet_dir` | `{{ podman_app_home }}/.config/containers/systemd` | built from the name, not meant to be set |
| `podman_app_config_public` | see `defaults/main.yml` | apps/\<name>/config/ as filetree items (path relative, src, state, root), empty when the app has none |
| `podman_app_private_src` | see `defaults/main.yml` | built from the name, not meant to be set |
| `podman_app_config_private` | see `defaults/main.yml` | private config items, built from the name, not meant to be set |
| `podman_app_config_own` | see `defaults/main.yml` | the public items the overlay doesn't replace, then everything |
| `podman_app_config` | `podman_app_config_own + podman_app_config_private` | config file list, built from the name, not meant to be set |
| `podman_app_render_dir` | `""` | render.yml only (playbooks/render-podman.yml): one folder per app goes here |
| `podman_app_subid_count` | `65536` | subuid range = uid * count, so ranges never overlap while uids stay unique |
| `podman_app_start_timeout` | `5min` | TimeoutStartSec= when the entry has no start_timeout, covers health start, images are pulled before |
| `podman_app_stop_timeout` | `10` | StopTimeout= in seconds when a container has no stop_timeout, podman's own default |
| `podman_app_restart_sec` | `30s` | retry forever with backoff (mount gate, crash loops), silent |
| `podman_app_restart_steps` | `5` | retry forever with backoff: steps |
| `podman_app_restart_max_delay` | `10min` | retry forever with backoff: longest delay |
| `podman_app_cifs_vers` | `3.1.1` | smb dialect of the pool mounts |
| `podman_app_cifs_creds_dir` | `/etc/cifs` | \<share>.creds, root-only |
| `podman_app_pod` | `podman_app_entry.containers \| default([]) \| length > 1` | more than one container = one pod: apps/\<name>/\<name>.pod.j2, \<name>-pod.service |
<!-- settings:end -->

Also from group_vars: `podman_apps_root` (`/srv/apps`, data dirs, backed up by `roles/pbs`), `cifs_mount_root` (`/srv`, where the shares are mounted), `storage_ip` (CT 300, the Samba server), `podman_svc_prefix` (`svc-`) and `podman_svc_group` (`svc-apps`), shared with `roles/podman_base` and the aide excludes.

## Notes

- Unit file rules (drop-in order, `HealthCmd=`, no end-of-line comments): [podman-layout](../../../docs/podman-layout.md#which-unit-file-wins)
- The tasks that need the svc user skip in `--check` until the user exists

## Related

- [ADR 0021: Podman quadlets instead of Docker](../../../docs/adr/0021-podman-quadlets.md)
- [ADR 0026: ufw as the guest firewall, also for Podman](../../../docs/adr/0026-ufw-as-guest-firewall.md)
- [podman-layout](../../../docs/podman-layout.md): where the files land and which unit file wins
- `podman_base` role (once per host)
