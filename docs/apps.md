# Adding, changing and removing an app

Every app is an entry in `group_vars/all/apps.yml` plus a folder `ansible/apps/<name>/`. Where each piece goes is in [podman-layout.md](podman-layout.md), the fields in `roles/podman_app/meta/argument_specs.yml`.

## Add an app

1. **The entry** in `apps.yml`:
   - `host`, a free `uid` (the next after the highest, 2000 to 65534), `port`
   - `allow_from`: who may reach the port, usually `[edge, netbird, homepage]`
   - `secrets`: each from a vault key (`vault:`) or a template in the app folder (`template:`)
   - `dirs` for data, with `owner` when the image doesn't run as root and `mode: "0700"` for Postgres
   - `containers`: fully qualified image, a tag. More than one container makes a pod: the main one is named like the app, the rest `<name>-<role>`, databases get `auto_update: false` and a pinned tag
   - `routes` (the hostname edge serves) and a `homepage` block for the tile
2. **The units** in `ansible/apps/<name>/`: `<container>.container.j2` per container, `<name>.pod.j2` for a pod (ports and `AddHost=` go there). Copy a similar app: single container `vaultwarden`, pod with Postgres `paperless` or `authentik`
   - A `HealthCmd=` the image can run, and a `HealthStartPeriod=` if the first start is slow
   - `AddHost=auth.{{ domain }}:{{ app_sources.edge }}` if it logs in through Authentik
3. **Secrets** into the vault: `ansible-vault edit group_vars/all/vault.yml`, and the key with a placeholder in `vault.yml.example`
4. **Config files** in `ansible/apps/<name>/config/`, private ones (logos, anything not for the public repo) in `<private_dir>/apps/<name>/config/`
5. **Backups**: a `pbs_jobs` line in `host_vars/<host>.yml` for its database (`type: sqlite` with `path`, or `type: postgres` with `container`, `data_dir`, `app`), `pbs_exclude` for caches
6. **Order**: a `deploy-app.yml` import with `vars: {app: <name>}` in `playbooks/site.yml`
7. **Check, render, commit**: `just check`. It validates the entry against the schema, the wiring (ports, uids, tiles, pbs jobs, units) and renders the example into `rendered_config/example/<name>/` for review
8. **Deploy**: `just deploy-app <name>`
9. **Edge**: the new route and its DNS rewrite come from `apps.yml`. Edge builds from the default branch every night, or now: `nixos/update.sh edge`
10. **Afterwards**: Gatus and Homepage pick the app up from `apps.yml` on their next deploy (`just deploy-app gatus`, `just deploy-app homepage`). OIDC: a provider and application in Authentik, the client ID and secret into the vault. AIDE accept on the host

## Change an app

- Any change to its entry, units, config or secrets: `just deploy-app <name>`. The role restarts the app only when something changed
- A new image tag: see [updates.md](updates.md#pinned-images)
- A new port or `allow_from`: the deploy adds the new ufw rules and removes the app's stale ones
- Move to another host: stop it, deploy on the new host (new `host:` in `apps.yml`), copy the data with the owner mapping ([troubleshooting](troubleshooting.md#moving-data-between-hosts-or-apps)), start, then remove it from the old host (below)

## Remove an app

The role only builds apps, it has no remove path (`state: absent` is refused). By hand:

1. A last backup: `ssh <host> sudo systemctl start pbs-backup.service`
2. Stop and delete it on the host, as root:
   ```bash
   cd /
   systemctl --user -M svc-<app>@ stop <app>       # or <app>-pod for a pod
   loginctl disable-linger svc-<app>
   userdel -r svc-<app>                            # home with quadlets, images, podman secrets
   grep svc-<app> /etc/subuid /etc/subgid          # nothing left, or remove the line
   rm -rf /srv/apps/<app>
   ufw status numbered                             # delete the app's port rules, highest number first
   ```
   - CIFS: its lines in `/etc/fstab` and `/etc/cifs/<share>.creds`, if no other app on the host uses that share
3. In the repo: the `apps.yml` entry, `ansible/apps/<name>/`, its `site.yml` import, its `pbs_jobs` and `pbs_exclude` lines, its vault keys (vault and example). `just check` removes its rendered example
4. Edge, Gatus and Homepage follow `apps.yml`: `nixos/update.sh edge` (or the nightly build), `just deploy-app gatus`, `just deploy-app homepage`
5. Semaphore: delete its template, if it had one
6. AIDE accept on the host
