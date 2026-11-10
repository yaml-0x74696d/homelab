# 32. Edge VM: Traefik and AdGuard Home on NixOS, routes from the apps map

Status: Proposed

## Context

- Traefik runs as a container on pod-1, Pi-hole as a container on pod-2 behind `dns_ip` ([0010](0010-pihole-on-a-service-ip.md))
- Both Docker VMs get rebuilt as Podman hosts, so ingress and LAN DNS would go down with each rebuild
- Traefik's routers are written by hand in `apps/proxy/traefik/dynamic/remote_services.yml` next to the `routes:` in `apps.yml`. `scripts/check_wiring.py` only finds a mismatch after the fact
- pve-1 and pve-2 carry the vital services ([0030](0030-haos-vm-on-pve-3.md)), pve-1 has room for a small VM since HA moved to pve-3
- The NetBird VM already shows the NixOS pattern: flake, nixos-anywhere, autoUpgrade, facts from group_vars ([0008](0008-nixos-for-the-dmz-box.md))

- Alternatives:
  - Keep Traefik and Pi-hole in Docker (why not: they go down with every rebuild, routers stay hand-written)
  - Traefik and Pi-hole as Podman apps (why not: ingress and DNS would share a VM with apps and its rebuilds)
  - Pi-hole on the new VM (why not: AdGuard Home's NixOS module takes the whole config and speaks DoT/DoH upstream on its own)
  - Traefik + AdGuard Home in an LXC (why not: it shares the host kernel, and edge takes the LAN's traffic, so it gets a VM's isolation. nixos-anywhere + disko, the NixOS pattern here, also only covers VMs)
  - Caddy instead of Traefik (why not: the Authentik forward-auth middlewares and the DNS-01 setup already exist for Traefik, a switch adds risk for no gain)
- Why: one small VM that only does ingress and DNS, declared in the same flake as the NetBird VM, with routes generated from the map

## Decision

The VM:
- `edge`, VM 200 on pve-1, `edge_ip` (`192.168.178.200`), 1 core, 1.5 GB (the upgrade builds on the box), 16 GB disk (`tofu/vms.tf`, `tofu/locals.tf`)
- NixOS, `nixosConfigurations.edge` in the same flake as the NetBird VM, host modules in `nixos/edge/`
- Hardening, AIDE, time, logging and the disk layout are shared with the NetBird VM from `nixos/base/`
- `dns_ip` (`.53`) becomes a second address on edge. `dns_ip_host` in `network.yml` says who holds it, edge only adds it once it says `edge`, after pod-2 dropped it. Clients and the router keep `.53` ([0010](0010-pihole-on-a-service-ip.md) holds)

Traefik (`nixos/edge/traefik.nix`):
- One router and service per entry in `apps.<name>.routes` and per `infra_routes` entry with a `target`, read through `facts.nix` from `apps.yml` (yq at build time)
- A route's host is resolved to its IP through the inventory (`host_ips` in `facts.nix`), the backend port is the route's `port` or the app's. Infra routes name a ports.yml key (`port_var`), `scheme` and `insecure_tls`
- Middlewares (`authentik` forward-auth, `nextcloud-dav`) live in the module. A route that names an undefined middleware fails the build
- The dynamic config is a copied file, `/etc/traefik/dynamic.yml`, which Traefik watches. A route change is a `nixos-rebuild`, Traefik isn't restarted
- One wildcard certificate `*.<domain>` via DNS-01 (Cloudflare, `cf_token` in `/var/lib/secrets/edge/cloudflare.env`) ([0015](0015-tls-via-dns-01.md))
- Dashboard at `traefik.<domain>` behind Authentik, access log to the journal and on to the log LXC ([0022](0022-central-logging-relp.md))

AdGuard Home (`nixos/edge/adguard.nix`):
- `mutableSettings = false`, the config comes only from the module
- Rewrites: every routed host to `edge_ip`, `nb.<domain>` to `netbird_ip`
- VPN clients: NetBird's nameserver group points at `dns-relay` on pod-2 (the routing peer, overlay IP, port 1053), CoreDNS that forwards to `dns_ip`. Rootless Podman can't bind 53, and a nameserver behind a NetBird route fails on macOS and iOS clients
- Upstreams Quad9 and Cloudflare over DoT and DoH, one blocklist (AdGuard DNS filter), query log kept 7 days
- UI on localhost only, served as `dns.<domain>` behind Authentik, no AdGuard login
- Break-glass when Authentik is down: `ssh -L 3000:127.0.0.1:3000 <admin_user>@<edge_ip>`, then `http://localhost:3000`. The SSH key is the lock, no AdGuard user (its hash would land in the world-readable nix store)

Updates:
- autoUpgrade at 04:00 (up to 20 minutes random delay), reboots only between 04:00 and 04:45, right after the NetBird VM (03:00 to 04:00), so the two never reboot at once. Both windows in `schedules.yml`
- `nixos/update.sh edge` and `nixos/aide-accept.sh edge` from the controller

- Enforced by: nftables on edge (80/443 and 53 from `lan_cidr` only, SSH from the LAN), `nix flake check` builds both hosts, the middleware assertion in `traefik.nix`

## Consequences

- Easier: a new route is an `apps.yml` entry plus `nixos-rebuild`, there is no router file to keep in sync
- Easier: ingress and DNS survive the Docker VM rebuilds, they are on their own VM
- Easier: one wildcard certificate instead of one per router, fewer Let's Encrypt orders

- Harder: edge is a single point for LAN DNS and every route, a broken switch takes both down (rollback is the previous generation)
- Harder: autoUpgrade builds on a 1.5 GB VM, zram is the only cushion
- Harder: the Cloudflare token now also lives on edge

- Accepted: changes made in the AdGuard UI are gone at the next restart, the UI is for looking
- Accepted: a wildcard certificate covers every name under the domain, a stolen key would too

- Before the cutover both Traefiks run in parallel: `ingress_extra_sources` (`app_settings.yml`) lets edge through the backend firewalls as well, so every route can be tested on edge while the LAN still uses pod-1
- Later: at the cutover, `app_sources.edge` and the callers of the pod-1 ports move to `edge_ip`, `ingress_extra_sources` goes back to `[]`, `dns_ip_host` flips to `edge`, Traefik on pod-1 and Pi-hole on pod-2 stop
- Later: rollback for a week after the cutover: Traefik on pod-1 and Pi-hole on pod-2 are only stopped, not removed. If edge fails, starting them again and `dns_ip_host` back to `pod-2` restores ingress and DNS within minutes

- Related: [0003](0003-netbird-instead-of-port-forwards.md) (NetBird), [0005](0005-prevent-destroy-on-stateful-vms.md) (prevent_destroy), [0007](0007-group-vars-single-source-of-truth.md) (shared vars), [0008](0008-nixos-for-the-dmz-box.md) (NixOS), [0009](0009-aide-with-manual-accept.md) (AIDE), [0010](0010-pihole-on-a-service-ip.md) (service IP), [0014](0014-authentik-as-idp.md) (forward-auth), [0015](0015-tls-via-dns-01.md) (DNS-01), [0022](0022-central-logging-relp.md) (logging), [0027](0027-gatus-generated-from-apps-map.md) (apps map)
