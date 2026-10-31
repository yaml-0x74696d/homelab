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
- One central apps map in `group_vars/all/apps.yml` describes each app: host, uid, units, secrets, dirs, cifs, `allow_from`, routes
- The playbooks stay thin

Updates:
- `AutoUpdate=registry` with a `podman-auto-update.timer` per user, weekly (Sunday 13:00, `podman_base_auto_update_time`) with a random delay
- Every container has a `HealthCmd` and `Notify=healthy`, so an image that starts but doesn't work is rolled back. An image that can't run a check (`scratch`) is marked `healthcheck: false` in the map
- A wrapper around `podman auto-update` (`roles/podman_base`) pushes updated, rolled back and failed units to ntfy. App down/up is Gatus' job, so there is no `OnFailure=`

Secrets and access:
- Secrets come from the vault as Podman secrets (`type=env` / `type=mount`), as a value or rendered into a config file, so no `.env` file sits on disk
- No app gets a container socket, so Diun and docker-proxy are dropped

Storage:
- CIFS mounts use `x-systemd.automount`, so a dropped share is remounted on the next access
- Services that use CIFS paths wait for the share: `ExecStartPre=/usr/bin/ls <path>` (the access triggers the automount), then `ExecStartPre=/usr/bin/findmnt -t cifs <path>`, + `Restart=on-failure` with backoff (an assert never triggers `Restart=`, and autofs alone counts as a mountpoint)
- `UserNS=keep-id` maps the container's UID onto `svc-<app>`

Rollout:
- The host OS stays Debian 13
- The VMs are rebuilt in place one at a time, with the same VMID, IP and MAC
- Each rebuild only happens after a restore rehearsal worked

- Enforced by: `argument_specs` on every deploy, `scripts/check_wiring.py` and ansible-lint in pre-commit (so `just check` and CI)

## Consequences

- Easier: no root daemon, a compromised app stays inside its own user
- Easier: updates and rollbacks happen without manual pulls, and failures land in ntfy
- Easier: systemd owns the start order, the restarts and the mount dependencies

- Harder: rootless apps can't share a container network. App-to-app traffic goes over `<host ip>:<port>`, with a firewall rule for each caller
- Harder: more files per app (one unit per container, pod and network) instead of one compose file

- Accepted: an update can still break a service between two weekly runs. Health checks and rollback limit the damage, and ntfy reports it

- Once done, this supersedes [0002](0002-generic-docker-app-role.md) (`docker_app` role) and [0006](0006-latest-images-notify-only.md) (`:latest` + Diun)

- Related: [0002](0002-generic-docker-app-role.md), [0006](0006-latest-images-notify-only.md), [0012](0012-no-kubernetes.md) (why not K8s), [0017](0017-smb-shares-to-docker-vms.md) (CIFS mounts), [0024](0024-ansible-run-os-updates.md) (OS updates), [0025](0025-debian-guests-until-x86-64-v3.md) (Debian pod hosts), [0026](0026-ufw-as-guest-firewall.md) (firewall), [0027](0027-gatus-generated-from-apps-map.md) (gatus)
