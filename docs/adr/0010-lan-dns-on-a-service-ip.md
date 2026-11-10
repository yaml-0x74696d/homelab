# 10. LAN DNS behind a service IP

Status: Accepted

## Context

- Every LAN client resolves through one DNS server, the router hands it out as the only IPv4 DNS server. So it has to run 24/7
- Split horizon: the app names point at Traefik, `nb.<domain>` at the NetBird VM
- The DNS server has moved between hosts before: Pi-hole from pod-1 to pod-2 (NetBird's DNS pushed it off port 53), then AdGuard Home on edge ([0032](0032-edge-vm-traefik-adguard-on-nixos.md))
- Clients pointed at a host IP, so moving DNS meant reconfiguring the router and every client with a static config

- Alternatives:
  - Clients on the DNS host's own IP (why not: every move touches the router and every static client)
  - DNS on the router (why not: no ad blocking, no split-horizon records)
- Why: the address stays put, the server behind it can move

## Decision

The service IP:
- Clients use `dns_ip` (`192.168.178.53`), an extra address on the host that runs DNS, the router hands it out as the only IPv4 DNS server
- `dns_ip_host` in `network.yml` names that host, only that host adds the address. Today edge, through networkd ([0032](0032-edge-vm-traefik-adguard-on-nixos.md))
- A move: the old host drops the address first, the new one adds it, then a gratuitous ARP (`arping -U`) so the LAN's caches follow at once

The server:
- AdGuard Home on edge, rewrites and blocklist from the flake ([0032](0032-edge-vm-traefik-adguard-on-nixos.md))
- VPN clients reach it through `dns-relay` on the routing peer, NetBird's nameserver group points there

- Enforced by: `dns_ip` and `dns_ip_host` in group_vars, read by Ansible, OpenTofu and Nix ([0007](0007-group-vars-single-source-of-truth.md))

## Consequences

- Easier: moving DNS, or adding a second resolver, just means moving the address. Clients never change

- Harder: the router needs local DNS set to `.53` and IPv6 RDNSS turned off, or clients go around the LAN DNS over IPv6

- Accepted: one resolver, no HA yet. If edge is down, DNS in the LAN is down, because `.53` is the only DNS server the router hands out

- Other config points at `dns_ip` too: the NixOS VMs' resolvers and their OpenTofu bootstrap

- Related: [0003](0003-netbird-instead-of-port-forwards.md) (NetBird), [0007](0007-group-vars-single-source-of-truth.md) (shared vars), [0032](0032-edge-vm-traefik-adguard-on-nixos.md) (AdGuard Home on edge)
