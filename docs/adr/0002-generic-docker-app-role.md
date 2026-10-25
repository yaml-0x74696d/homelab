# 2. One generic role for all apps

Status: Accepted

## Context

- 26 compose apps across 3 Docker VMs
- Copy-pasted playbooks drift apart over time
- Every app needs the same steps: folders, networks, firewall, config files, secrets, pool mounts, compose up

- Alternatives:
  - One big tagged playbook (why not: one big playbook is less human readable)
  - A role per app (why not: most code would duplicate)
  - Keep copy-paste playbooks (why not: they drift)

## Decision

How an app is set up:
- There is one role, `roles/docker_app`
- Each app is a folder `apps/<name>/` (compose file + config) plus a thin playbook `playbooks/deploy-<name>.yml`
- The smallest playbook only sets the host and `docker_app_name` (`deploy-pdfcraft.yml`, 8 lines)
- `site.yml` imports every deploy playbook in order
- Running one playbook only touches that one app

What the role does for each app, in order:
1. Creates `<apps_root>/<app>/` and any extra folders (`docker_app_dirs`)
2. Creates the Docker networks on the host, by default `[proxy-net]` (the compose file declares it external)
3. Creates empty files if they are missing, e.g. `acme.json` with mode `0600` (`docker_app_touch`)
4. Opens ufw ports (`docker_app_ufw`)
5. Mirrors the subfolders and copies every file that isn't `.j2`
6. Renders every `*.j2` file in place, without the `.j2` ending
7. Mounts the pool shares over CIFS (`docker_app_cifs`), with the credentials in `/etc/cifs/<share>.creds`, mode `0600`
8. Starts the app with `docker_compose_v2` (`pull: policy`, orphans are not removed by default)
9. Restarts the named containers when their config changed (handler, `docker_app_restart`)

Rules:
- A file only becomes `.j2` if it needs Jinja, everything else is copied as it is
- Traefik's `remote_services.yml` uses Go templating, so it has to stay a plain file
- Secrets flow: vault → `.env.j2` (mode `0600`) → `${VAR}` in compose, so the compose files stay plain YAML
- App-specific values go in the `vars:` block at the top of the deploy playbook (tags, UIDs, healthcheck timings, paths)
- Databases stay on local volumes, only bulk data goes on the CIFS pool

- Enforced by: ansible-lint (production profile) in `just check` and CI, and the deploy playbooks only set vars for the one role

## Consequences

- Easier: a new app is a folder plus a short playbook, the role doesn't change
- Easier: a fix in the role fixes all 26 apps at once
- Easier: the settings of each app are visible at the top of its playbook

- Harder: vault values must be alphanumeric, because compose interpolation eats `$`
- Harder: the CIFS UID/GID must match the container's user, or writes fail (Nextcloud 33, Paperless 1000)

- Accepted: files are found and copied one by one instead of copying the whole folder. That's slower for apps with many icons, but `.j2` sources never end up on the host

- The mounts use `mfsymlinks,nofail,_netdev`, so the host still boots when the storage CT is down

- Related: [0004](0004-mergerfs-instead-of-zfs.md) (pool), [0006](0006-latest-images-notify-only.md) (image updates), [0007](0007-group-vars-single-source-of-truth.md) (shared vars)
