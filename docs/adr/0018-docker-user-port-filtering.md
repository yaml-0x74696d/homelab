# 18. Filter published container ports in DOCKER-USER

Status: Accepted

## Context

- The Docker VMs run ufw with default deny ([0002](0002-generic-docker-app-role.md), `vm-preparation.yml`)
- Docker publishes ports with its own NAT rules, and those apply before ufw ever sees the packet
- So a published port is open to the whole LAN, no matter what ufw says
- The apps on docker-2/3 publish ports so Traefik on docker-1 can reach them

- Alternatives:
  - No published ports (overlay / one Docker network across hosts) (why not: needs Swarm or an overlay, extra complexity)
  - Bind ports to one IP (why not: still open to every host on the LAN)
  - `iptables: false` in the daemon (why not: breaks Docker's own networking)
  - Keep as is (why not: every backend open to the whole LAN)
- Why: keeps Docker's networking, only the right hosts get through

## Decision

How it works:
- Published ports are filtered by source in the `DOCKER-USER` chain
- `vm-preparation.yml` writes the rules to `/etc/ufw/after.rules` (tag `docker-user`)
- For each port in `docker_published_allow`:
  - its allowed sources and the Docker bridge get `RETURN` (let through)
  - everyone else gets `DROP`
- The rules match on `--ctorigdstport`, the port before Docker's NAT rewrote it

Who may call (`docker_backend_callers` in `group_vars/all/ports.yml`):
- docker-1: Traefik, Homepage, Home Assistant
- docker-2: Prometheus, Grafana
- mqtt-exporter only accepts calls from docker-2

What's filtered and what's open:
- Filtered: docker-socket-proxy and every backend app port (Nextcloud, Immich, Jellyfin, Paperless, Grafana, Prometheus, InfluxDB and more)
- Open on purpose: 53 (DNS), 80/443 (Traefik), 1883 (MQTT), 2222 (Gitea SSH)

- Enforced by: `vm-preparation.yml` rewrites the block on every run, and the ports come from the same `app_ports` map that compose uses ([0007](0007-group-vars-single-source-of-truth.md))

## Consequences

- Easier: backends only answer the proxy and the monitoring, not every client in the LAN
- Easier: adding an app is one line in `docker_published_allow`

- Harder: a new caller (e.g. another monitoring tool) needs its IP added, or it's dropped without any error
- Harder: rule changes need a ufw reload (`--tags docker-user`)

- Accepted: the traffic between Traefik and the backends is plain HTTP inside the LAN

- Related: [0002](0002-generic-docker-app-role.md) (app role), [0007](0007-group-vars-single-source-of-truth.md) (ports map), [0015](0015-tls-via-dns-01.md) (TLS at Traefik), [0026](0026-ufw-as-guest-firewall.md) (guest firewall)
