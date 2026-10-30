# 3. NetBird instead of port forwards

Status: Accepted

## Context

- I want remote access to the LAN-only apps without exposing them to the internet
- Before: Traefik and the web apps were open on public 443
- The FRITZ!Box has a built-in WireGuard server, but every device needs its own config, made in the router UI

- Alternatives:
  - Headscale: self-hosted Tailscale control plane, used with the Tailscale clients (why not: clients not fully open source)
  - Pangolin: ingress through a WireGuard tunnel, exposes services without port forwards (why not: reverse proxy, not a mesh VPN)
  - Plain FRITZ!Box WireGuard (why not: no web UI and no zero trust)
  - Keep 443 open (why not: every app on the WAN)
- NetBird was picked as the "easiest self-hosted UI" (roadmap)
- Why: I wanted a fully open source, fully self-hosted zero trust mesh VPN

## Decision

The control plane:
- Self-hosted NetBird on its own NixOS VM (`netbird`, VMID 250, on pve-2, `.250`), using nixpkgs `services.netbird.server` ([0008](0008-nixos-for-the-dmz-box.md))
- Parts: management (SQLite), signal, dashboard, coturn (STUN/TURN) and nginx with one TLS vhost
- TLS through ACME DNS-01 (Cloudflare), so port 80 isn't forwarded
- Login through Authentik OIDC (public PKCE client)
- Peers join with setup keys, because Authentik isn't reachable from the internet

What the WAN sees:
- The router forwards only to `.250`: 443/tcp and 3478/udp
- Optional: the other TURN ports and the relay range 49160–49200/udp
- 443 moved from Traefik to NetBird, so the web apps are now LAN + VPN only

The routing:
- docker-2 is the routing peer (`netbird_agent` group, `roles/netbird_agent`)
- The role adds the apt repo, turns on IP forwarding and enrolls the peer with a setup key
- The network route `192.168.178.0/24` with masquerade is set in the dashboard
- NetBird's nameserver for the lab domain is Pi-hole, so `*.<domain>` resolves to LAN IPs through the tunnel

The DMZ firewall (`roles/pve_firewall`, `netbird.fw.j2`):
- In: 443, TURN, the relay range, and SSH/ICMP from the LAN only
- Out: everything to the routing peers, DNS + HTTPS to Pi-hole/Traefik, DNS to the gateway
- The rest of the LAN is dropped, the internet is open

The fallback:
- FRITZ!Box WireGuard (51820/udp) stays as a backup
- It lives on the router alone, so it still works when the whole cluster is down

- Enforced by: the PVE firewall drops everything else to the DMZ guest (`roles/pve_firewall`), nftables denies by default on the VM itself, and the FRITZ!Box forwards only to `.250`

## Consequences

- Easier: only one box faces the WAN instead of every app, and that box is hardened and checked by AIDE ([0009](0009-aide-with-manual-accept.md))
- Easier: FRITZ!Box WireGuard stays as an independent way in

- Harder: NetBird and FRITZ!Box WireGuard must never run at the same time. Both route the LAN, the routes collide and break NetBird's routing and DNS
- Harder: the nameserver has to be a peer's overlay IP, not a LAN IP behind a route, or the macOS/iOS resolvers fail
- Harder: docker-1 left NetBird after NetBird's DNS and nftables pushed Pi-hole off port `:53` there. Pi-hole now runs on docker-2, with NetBird's DNS management turned off for that group ([0010](0010-pihole-on-a-service-ip.md))

- Accepted: coturn has no `external-ip` because the WAN IP keeps changing, so the TURN relay is unreliable by design. Direct P2P + STUN cover normal use
- Accepted: user and group sync from the IdP is turned off (Authentik's machine auth answered 405). Users still log in through OIDC
- Accepted: the server secrets were put on the VM by hand and are not in git. agenix/sops is planned

- Related: [0008](0008-nixos-for-the-dmz-box.md) (NixOS), [0010](0010-pihole-on-a-service-ip.md) (Pi-hole on docker-2)
