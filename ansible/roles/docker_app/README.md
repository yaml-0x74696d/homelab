# docker_app

- Deploys one compose app from `apps/<name>/`: renders the `*.j2` files and copies the rest
- It's the only app role. Every app is a folder plus a thin playbook that sets `docker_app_name` and a few variables

## Runs on

- Every `deploy-<app>.yml` (26 apps), the host is picked by the playbook's `hosts:`
- `site.yml` imports them all

## How it works

1. Creates `<apps_root>/<app>/` on the host (`/opt/apps/<app>`)
2. Creates extra folders with owner and mode (`docker_app_dirs`), e.g. data folders a container writes to as a fixed UID
3. Makes sure the Docker networks exist on the host (`proxy-net` by default, the compose file declares it `external`)
4. Creates empty files once if they're missing (`docker_app_touch`, e.g. `acme.json` with mode `0600`). They're never overwritten
5. Adds ufw allow rules (`docker_app_ufw`)
6. Mirrors the subfolders, then copies every file that isn't `.j2` (mode `u=rwX,g=rX,o=rX`, so only files that are executable in the source stay executable)
7. Finds every `*.j2` on the controller (including hidden ones like `.env.j2`) and renders it next to its source, without the `.j2`
8. Rendered `.env` files get mode `0600`, other templates `0644`
9. CIFS: installs `cifs-utils`, writes the credentials to `/etc/cifs/<share>.creds` (mode `0600`, `no_log`) and adds an fstab mount with `nofail,_netdev`
10. Starts the app with `docker_compose_v2` (`pull: policy`, so it only pulls images that are missing)
11. A handler restarts the containers in `docker_app_restart` when a file or template changed

## App folder conventions

- A file only becomes `.j2` if it needs Jinja, everything else is copied as it is
- Traefik's dynamic config uses Go templates (`{{ env "DOMAIN" }}`), so it has to stay a plain file
- Secrets and host facts only come in through `.env.j2` → `${VAR}` in compose, so the compose files stay plain YAML
- Databases go on local volumes under the app folder, bulk data on the CIFS pool mounts
- Databases and Redis get a healthcheck, and the app waits for them with `depends_on: condition: service_healthy`. The timings are playbook variables

## Settings

| Variable | Default | What |
|---|---|---|
| `docker_app_name` | | The app, required |
| `docker_app_src` | `apps/<name>` | Source folder on the controller |
| `docker_app_root` | `apps_root` | Parent folder on the host |
| `docker_app_dirs` | `[]` | Extra folders, e.g. `[{path: data, owner: '472'}]` |
| `docker_app_networks` | `[proxy-net]` | Docker networks to create on the host |
| `docker_app_touch` | `[]` | Empty files to create, e.g. `[{path: acme.json, mode: '0600'}]` |
| `docker_app_ufw` | `[]` | ufw allow rules, e.g. `[{port: 1883}]` |
| `docker_app_cifs` | `[]` | Pool mounts: `{share, user, path, uid, gid, file_mode?, dir_mode?, extra_opts?}`, the password comes from the vault (`smb_passwords[user]`) |
| `docker_app_cifs_vers` | `3.1.1` | SMB version for the mounts |
| `docker_app_restart` | `[]` | Containers to restart when the config changes |
| `docker_app_compose_state` | `present` | Passed to `docker_compose_v2` |
| `docker_app_compose_pull` | `policy` | Passed to `docker_compose_v2` |
| `docker_app_compose_remove_orphans` | `false` | Passed to `docker_compose_v2` |

## Examples

- Nextcloud: its own share as www-data (UID 33) with `nobrl` for SMB locking, plus media, documents and photos as external storage. Photos are `ro`, because Immich owns that library
- Paperless / Immich: the CIFS UID/GID is set to the container's user, or it can't write
- dashboard: `docker_app_restart: [homepage]` plus `remove_orphans`

## Notes

- The UID/GID on the CIFS mount must match the user inside the container
- `.j2` sources never reach the host, only the rendered files do

## Related

- [ADR 0002: One generic role for all apps](../../../docs/adr/0002-generic-docker-app-role.md)
- [ADR 0006: `:latest` images, notify-only updates](../../../docs/adr/0006-latest-images-notify-only.md)
- `samba` role (the shares these mounts use)
