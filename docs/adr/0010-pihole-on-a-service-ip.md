# 10. Pi-hole on docker-2 behind a service IP

Status: Accepted

## Context

- Every LAN client resolves through Pi-hole, the FRITZ!Box hands it out as the only IPv4 DNS server. So it has to run 24/7
- Split horizon: `*.<domain>` points at Traefik on docker-1, `nb.<domain>` at the NetBird VM
- Pi-hole used to run on docker-1. NetBird's DNS and nftables on the same host pushed it off port 53 on every reboot, so NetBird was removed from docker-1 first
- Clients pointed at a host IP, so moving DNS meant reconfiguring the FRITZ!Box and every client with a static config

- Alternatives:
  - DNS on the FRITZ!Box (why not: no ad blocking, no wildcard records)
  - AdGuard Home (why not: Pi-hole was already running)
  - A dedicated LXC (why not: one more guest to maintain)
- Why docker-2: NetBird took :53 on docker-1

## Decision

The service IP:
- Pi-hole runs on docker-2 (`deploy-dns.yml`, `apps/dns`)
- Clients use `dns_ip` (`192.168.178.53`), an extra address on docker-2's network card
- `dns-ip.service` adds that address at boot (a oneshot `ip addr replace`)

The setup:
- The deploy frees port 53 first: the systemd-resolved stub listener is turned off, and `/etc/resolv.conf` points at the real upstream servers
- The split-horizon records are in `02-local.conf.j2` (dnsmasq `address=`). The longest match wins, so `nb.` beats the wildcard
- The web UI is behind Traefik (`dns.<domain>`), published on `app_ports.pihole`
- NetBird's DNS management is turned off for docker-2's peer group, so the routing peer and Pi-hole can share the host
- The query log (`pihole-FTL.db`) is left out of PBS, because it's huge and disposable

- Enforced by: one variable, `dns_ip`, in group_vars, read by Ansible, OpenTofu and Nix ([0007](0007-group-vars-single-source-of-truth.md))

## Consequences

- Easier: moving DNS later, or adding a second resolver, just means moving the address. Clients never change

- Harder: the FRITZ!Box needs local DNS set to `.53` and IPv6 RDNSS turned off, or clients go around Pi-hole over IPv6

- Accepted: one resolver, no HA yet. If docker-2 is down, DNS in the LAN is down, because `.53` is the only DNS server the FRITZ!Box hands out

- Other config points at `dns_ip` too: the NetBird VM's resolver in Nix and its OpenTofu bootstrap
- Later: AdGuard Home on a NixOS edge VM (see "Future plans" in the README)

- Related: [0003](0003-netbird-instead-of-port-forwards.md)
