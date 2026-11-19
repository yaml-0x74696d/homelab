# 27. Gatus for uptime checks, generated from the apps map

Status: Accepted

## Context

- Uptime Kuma kept its 34 monitors only in its SQLite DB: changes were clicks and drift was invisible. After the Podman move, its pod-2 checks broke without anything in git showing why
- Kuma 2 has no supported way to define monitors as code

- Alternatives:
  - Uptime Kuma 2 (why not: monitors only in the UI, a 1.x → 2.x DB migration, about 20 times the RAM of Gatus on pod-2)
  - Gatus (chosen)

## Decision

- Gatus runs on pod-2 as a rootless Podman app in Kuma's slot (port 3001, `status.<domain>`)
- `apps/gatus/config.yaml.j2` generates every check: each route in `apps.yml` (status and certificate expiry), Traefik, a ping for every guest in the inventory, the PVE and PBS ports, the domain's A record, and the last run of each scheduled Semaphore template
- Jobs that can silently stop push a heartbeat instead: one external endpoint per backup host (`roles/pbs`) and per Semaphore template (`roles/gatus_push`, the last play of `repo-pull.yml`, `aide.yml` and `update.yml`). Gatus alerts when no push arrives within the window of that job's schedule (`heartbeat_daily`, `heartbeat_weekly` in `schedules.yml`)
- A push needs the Gatus backend port on pod-2, the route sits behind authentik. `allow_from` lets pod-1 and pod-3 in, the playbooks push from pod-2 itself. The token is `gatus_push_token` in the vault
- A thin pool filling up on the PVE nodes: `roles/pve_thinpool` writes its data and metadata percent into node-exporter's textfile dir, Gatus asks Prometheus per node (data, metadata and freshness of the file) and alerts above `gatus_thinpool_max_pct` or when the file is older than `gatus_thinpool_stale_max`
- `metrics: true` exposes the results to Prometheus (job `gatus`), Grafana's lab health dashboard reads them ([0040](0040-grafana-dashboards-as-code.md))
- Alerts go to ntfy, with server and topic split from the one `ntfy_url` ([0019](0019-ntfy-single-alert-channel.md))
- A route behind authentik only proves the login (`[STATUS] == 302`), so an app with a port in the map gets a second check on its backend
- The status page itself sits behind authentik: it shows the topology and internal IPs
- Route names are pinned to Traefik's IP in Gatus' container (`AddHost=`, from `apps.yml` and `app_sources.edge`): the checks don't depend on DNS, so a DNS outage can't turn every check red

- Enforced by: the config is rendered into a Podman secret by `roles/podman_app`, nothing is edited in a UI

## Consequences

- Easier: a new app or guest is checked without a manual step
- Easier: about 6 MB of RAM instead of about 120 MB, and no growing DB

- Harder: a missed heartbeat is noticed at the next heartbeat tick, between one and two windows after the last push
- Harder: no container-state checks. cloudflare-ddns has no port, so only its DNS record is checked

- Accepted: Gatus itself has no health check (its image is `scratch`, `healthcheck: false`)
- Accepted: pod-1 and pod-3 reach Gatus' backend port directly for the heartbeats, so from those hosts its UI and API skip Authentik
- Accepted: one push token is shared by all pushers. Any pod VM holds it in `/etc/pbs.env` and can fake any heartbeat

- Related: [0013](0013-pbs-file-level-backups.md) (backups), [0019](0019-ntfy-single-alert-channel.md) (ntfy), [0021](0021-podman-quadlets.md) (Podman), [0026](0026-ufw-as-guest-firewall.md) (ufw), [0031](0031-semaphore-on-a-single-board-computer.md) (scheduled runs), [0032](0032-edge-vm-traefik-adguard-on-nixos.md) (edge reads the same map), [0040](0040-grafana-dashboards-as-code.md) (dashboards)
