# netbird_agent

- Installs a NetBird peer on a LAN host and keeps IP forwarding on for the LAN route
- The role only enrolls the box. Making it route is done in `tofu/netbird.tf` (Network `lan`, router, masquerade)

## Runs on

- The `netbird_agent` inventory group: pod-2, the routing peer that's always on
- Members stay in their main group (pod_vms / proxmox) for the connection settings

## How it works

1. If `/usr/bin/netbird` is missing, the role adds the official apt repo (deb822, key in `/etc/apt/keyrings/netbird.asc`) and installs it
2. If NetBird was already installed by hand, the repo step is skipped, because its own repo with `Signed-By` would clash
3. The `netbird` daemon is enabled and started
4. `net.ipv4.ip_forward=1` is saved as a sysctl, so it survives a reboot (NetBird also sets it at runtime)
5. If `/etc/netbird/config.json` is missing and a setup key is given, it runs `netbird up --management-url … --setup-key-file …` (`no_log`). The key goes in a 0600 temp file that is removed after, so it is not in argv
6. After enrollment the daemon reconnects on its own
7. Routes, DNS and ACLs are managed in `tofu/netbird.tf`

## Enrollment

- Peers join with setup keys, not SSO. The IdP isn't reachable from the internet, so a fresh peer couldn't log in
- The key is stored as `vault_netbird_setup_key`. Keys are one-off and short-lived: how to get one and how to re-enroll pod-2 is in [docs/netbird.md](../../../docs/netbird.md) (Administration, "Re-enrolling pod-2")
- With an empty key, the role only installs NetBird and you enroll by hand

## Settings

| Variable | Default | What |
|---|---|---|
| `netbird_agent_mgmt_url` | `https://nb.{{ domain }}` | The management server |
| `netbird_agent_setup_key` | `vault_netbird_setup_key`, or empty | One-off setup key from tofu |
| `netbird_agent_enable_forwarding` | `true` | Keep IP forwarding on |

## Notes

- dns-relay (CoreDNS, port 1053) shares pod-2 with the agent and answers the VPN clients ([ADR 0003](../../../docs/adr/0003-netbird-instead-of-port-forwards.md), [ADR 0010](../../../docs/adr/0010-lan-dns-on-a-service-ip.md))
- NetBird's DNS management stays off for pod-2's group, so NetBird never takes port 53 on its routing peer
- Don't run NetBird and the router's WireGuard at the same time. Both route the LAN CIDR, the routes collide and NetBird's routing and DNS break
- The routing peer must resolve `nb.{{ domain }}` to the NetBird VM (local DNS override)

## Related

- [ADR 0003: NetBird instead of port forwards](../../../docs/adr/0003-netbird-instead-of-port-forwards.md)
- [ADR 0010: LAN DNS behind a service IP](../../../docs/adr/0010-lan-dns-on-a-service-ip.md)
- Control plane: `nixos/netbird/` (separate NixOS VM), firewall: `pve_firewall` role
