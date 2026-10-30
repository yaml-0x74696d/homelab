# 6. `:latest` images, notify-only updates

Status: Accepted

## Context

- 25 apps with 37 images, run by one person, so there's no time to follow every upstream release
- Pulling and recreating everything at once restarts too many containers together, fills the thin pool and can take a Docker VM down

- Alternatives:
  - Pinned tags + Renovate (why not: a PR for every image update, too much for one person)
  - Watchtower auto-pull (why not: auto-pull without rollback, same risk as the bulk pull)
  - A bulk-pull playbook (why not: restarts everything at once, see above)
- Why: `:latest` means an update is just a pull, no tag edits. Auto-update without rollback was too risky after the docker-1 crash

## Decision

Which images move and which are pinned:
- Most app images are on `:latest` (19 of 37) or a moving channel (`stable`, `release`, `alpine`, `apache`)
- Stateful or picky images are pinned through `<app>_*_tag` variables in the deploy playbooks:
  - Databases: Postgres `16-alpine` (Authentik, Nextcloud, Paperless), Immich's Postgres build with vector support, Redis `6.2-alpine`, Valkey `8-alpine`
  - Pinned to a major version: InfluxDB `2`, uptime-kuma `1`, Gotenberg `8`
  - Pinned to an exact version: Vaultwarden `1.37.1`, and Authentik through `authentik_tag` in `group_vars/all/apps.yml` (stepped through release by release)

How I find out about updates (Diun, on every Docker host, `apps/diun`, `deploy-diun.yml`):
- Diun watches the local Docker socket and checks the image digests once a day (`diun_schedule: "0 6 * * *"`, `diun_jitter: 30s`)
- New versions are pushed to ntfy
- It only notifies, it never pulls or restarts anything
- Every container is watched by default (`WATCHBYDEFAULT=true`), a single container can opt out with the label `diun.enable=false`
- It doesn't notify on the first check (`FIRSTCHECKNOTIF=false`) and keeps its state in `./data`, so it doesn't repeat itself every run
- It has no network except the socket and outbound traffic (`docker_app_networks: []`)

How an update happens:
- A normal redeploy never pulls a newer image (`docker_app_compose_pull: policy`)
- Updates are done by hand, one app at a time: `docker compose pull && up -d`, check that `ps` shows it healthy, then the next one
- docker-1 is busy, so its apps are updated off-peak

- Enforced by: `docker_app_compose_pull: policy` (a redeploy never pulls), and Diun can only notify

## Consequences

- Easier: no tag bumps for 19 images in 17 apps, Diun says when something new is out
- Easier: databases never jump a major version by accident, because they're pinned

- Harder: Diun needs the Docker socket (mounted read-only)

- Accepted: not reproducible by tag. Two hosts can run different builds of the same "latest"
- Accepted: a bad release shows up on the next manual pull, not at 3am

- Rollback: pin the previous tag in the compose file, or restore from PBS
- Later: Podman `AutoUpdate=registry` with rollback replaces this ([0021](0021-podman-quadlets.md))

- Related: [0002](0002-generic-docker-app-role.md) (`docker_app` role), `roles/pbs` (rollback path)
