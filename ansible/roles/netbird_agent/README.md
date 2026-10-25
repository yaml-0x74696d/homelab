# netbird_agent

- Installs a NetBird peer on a LAN host and keeps IP forwarding on for the LAN route
- The role only enrolls the box. Making it route is done in the dashboard (network route + masquerade)

## Runs on

- The `netbird_agent` inventory group: docker-2, the routing peer that's always on
- Members stay in their main group (docker_hosts / proxmox) for the connection settings

## How it works

- If `/usr/bin/netbird` is missing, the role adds the official apt repo (deb822, key in `/etc/apt/keyrings/netbird.asc`) and installs it
- If NetBird was already installed by hand, the repo step is skipped, because its own repo with `Signed-By` would clash
- The `netbird` daemon is enabled and started
- `net.ipv4.ip_forward=1` is saved as a sysctl, so it survives a reboot (NetBird also sets it at runtime)
- If `/etc/netbird/config.json` is missing and a setup key is given, it runs `netbird up --management-url … --setup-key …` (`no_log`)
- After enrollment the daemon reconnects on its own
- Routes, DNS and ACLs are managed in the dashboard

## Enrollment

- Peers join with setup keys, not SSO. The IdP isn't reachable from the internet, so a fresh peer couldn't log in
- The key comes from the dashboard and is stored as `vault_netbird_setup_key`
- With an empty key, the role only installs NetBird and you enroll by hand

## Settings

| Variable | Default | What |
|---|---|---|
| `netbird_agent_mgmt_url` | `https://nb.{{ domain }}` | The management server |
| `netbird_agent_setup_key` | `vault_netbird_setup_key`, or empty | Reusable setup key from the dashboard |
| `netbird_agent_enable_forwarding` | `true` | Keep IP forwarding on |

## Notes

- docker-1 left after NetBird's DNS took port 53 from Pi-hole there. Pi-hole now shares docker-2 with the agent ([ADR 0003](../../../docs/adr/0003-netbird-instead-of-port-forwards.md), [ADR 0010](../../../docs/adr/0010-pihole-on-a-service-ip.md))
- NetBird's DNS management must be turned off for docker-2's group, or NetBird grabs port 53 there too
- Don't run NetBird and the FRITZ!Box WireGuard at the same time. Both route the LAN CIDR, the routes collide and NetBird's routing and DNS break
- The routing peer must resolve `nb.{{ domain }}` to the NetBird VM (local DNS override)

## Related

- [ADR 0003: NetBird instead of port forwards](../../../docs/adr/0003-netbird-instead-of-port-forwards.md)
- [ADR 0010: Pi-hole on a service IP](../../../docs/adr/0010-pihole-on-a-service-ip.md)
- Control plane: `nixos/netbird/` (separate NixOS VM), firewall: `pve_firewall` role
