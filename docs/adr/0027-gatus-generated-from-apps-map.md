# 27. Gatus for uptime checks, generated from the apps map

Status: Accepted

## Context

- Uptime Kuma kept its 34 monitors only in its SQLite DB: changes were clicks and drift was invisible. After the Podman move, its docker-2 checks broke without anything in git showing why
- Kuma 2 has no supported way to define monitors as code

- Alternatives:
  - Uptime Kuma 2 (why not: monitors only in the UI, a 1.x → 2.x DB migration, about 20 times the RAM of Gatus on docker-2)
  - Gatus (chosen)

## Decision

- Gatus runs on docker-2 as a rootless Podman app in Kuma's slot (port 3001, `status.<domain>`)
- `apps/gatus/config.yaml.j2` generates every check: each route in `apps.yml` (status and certificate expiry), Traefik, a ping for every guest in the inventory, the PVE and PBS ports, and the domain's A record
- Alerts go to ntfy, with server and topic split from the one `ntfy_url` ([0019](0019-ntfy-single-alert-channel.md))
- A route behind authentik only proves the login (`[STATUS] == 302`), so an app with a port in the map gets a second check on its backend
- The status page itself sits behind authentik: it shows the topology and internal IPs
- Route names are pinned to Traefik's IP in Gatus' container (`AddHost=`, from `apps.yml` and `app_sources.edge`): the checks don't depend on DNS, so a DNS outage can't turn every check red

- Enforced by: the config is rendered into a Podman secret by `roles/podman_app`, nothing is edited in a UI

## Consequences

- Easier: a new app or guest is checked without a manual step
- Easier: about 6 MB of RAM instead of about 120 MB, and no growing DB

- Harder: no container-state checks. cloudflare-ddns has no port, so only its DNS record is checked

- Accepted: Gatus itself has no health check (its image is `scratch`, `healthcheck: false`)

- Related: [0019](0019-ntfy-single-alert-channel.md) (ntfy), [0021](0021-podman-quadlets.md) (Podman), [0026](0026-ufw-as-guest-firewall.md) (ufw)
