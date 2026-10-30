# 21. Podman quadlets instead of Docker

Status: Proposed

## Context

- 25 apps run as Docker Compose stacks through the `docker_app` role ([0002](0002-generic-docker-app-role.md)), all as root under the Docker daemon
- Updates are manual: `:latest` images plus Diun notifications ([0006](0006-latest-images-notify-only.md))
- No compose file needs privileged mode, devices or host networking. The only extra capability is `NET_RAW` for homelable
- Goal: the lab should run for months without hands-on updates

- Alternatives:
  - Keep Docker + compose (why not: root daemon, no auto-update with rollback)
  - Rootful Podman (why not: no gain over Docker, still root)
  - Kubernetes / k3s (why not: see [0012](0012-no-kubernetes.md))
- Why: I want to be able to leave the homelab alone for a couple of months. I'd rather fix a broken service when I have time than run an unpatched vulnerability

## Decision

Rootless, one user per app:
- Podman, rootless only
- Every app gets its own system user (`svc-<app>`) with its own subuid range and linger turned on
- The UIDs are fixed in the apps map

Apps as quadlets:
- A new `podman_app` role renders quadlet units from Jinja templates (`*.container.j2`, `*.pod.j2`, `*.network.j2`)
- Apps with more than one container get one `.pod`
- One central apps map in `group_vars/all/apps.yml` describes each app: host, uid, units, secrets, dirs, cifs, ufw, routes
- The playbooks stay thin

Updates:
- `AutoUpdate=registry` with a `podman-auto-update.timer` per user, nightly with a random delay
- Every container has a `HealthCmd` and `Notify=healthy`, so an image that starts but doesn't work is rolled back
- Failures are pushed to ntfy through `OnFailure=`

Secrets and access:
- Secrets come from the vault as Podman secrets (`type=env` / `type=mount`), so no `.env` file sits on disk
- No app gets a container socket, so Diun and docker-proxy are dropped

Storage:
- Services that use CIFS paths wait for the mount (`AssertPathIsMountPoint=` + `Restart=`)
- `UserNS=keep-id` maps the container's UID onto `svc-<app>`

Rollout:
- The host OS stays Debian 13
- The VMs are rebuilt in place one at a time, with the same VMID, IP and MAC
- Each rebuild only happens after a restore rehearsal worked

- Enforced by: a quadlet dry-run in CI (`quadlet -dryrun` on the rendered templates), an Ansible syntax check and ansible-lint in `just check`

## Consequences

- Easier: no root daemon, a compromised app stays inside its own user
- Easier: updates and rollbacks happen without manual pulls, and failures land in ntfy
- Easier: systemd owns the start order, the restarts and the mount dependencies

- Harder: rootless apps can't share a container network. App-to-app traffic goes over `<host ip>:<port>`, with a ufw rule for each caller
- Harder: more files per app (one unit per container, pod and network) instead of one compose file

- Accepted: an update can still break a service between two nightly runs. Health checks and rollback limit the damage, and ntfy reports it

- Once done, this supersedes [0002](0002-generic-docker-app-role.md) (`docker_app` role) and [0006](0006-latest-images-notify-only.md) (`:latest` + Diun)

- Related: [0002](0002-generic-docker-app-role.md), [0006](0006-latest-images-notify-only.md), [0012](0012-no-kubernetes.md) (why not K8s), [0017](0017-smb-shares-to-docker-vms.md) (CIFS mounts)
