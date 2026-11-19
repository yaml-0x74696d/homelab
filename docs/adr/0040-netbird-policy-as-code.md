# 40. What a VPN peer may reach is NetBird policy, in code

Status: Accepted

## Context

- The routing peer masquerades ([0003](0003-netbird-instead-of-port-forwards.md)), so every VPN peer reaches the LAN as pod-2
- pod-2 is also the monitoring host. Whatever lets Prometheus and Gatus in (`netbird` in `app_sources`, SSH from the LAN) lets every peer in
- What a peer may reach was set in the NetBird dashboard and nowhere else
- Today every peer is mine. Family devices are next

- Alternatives:
  - Masquerade off, the firewalls filter by overlay address (why not: a static route on the router, a detour for every reply)
  - A routing peer of its own (why not: one more guest on a node with half a GB free)
  - Keep it by hand in the dashboard (why not: the access model of the VPN is in no file)
  - NetBird policies on single hosts, managed with OpenTofu (chosen)
- Why: NetBird is the only place that knows whose packet it is

## Decision

The setup:
- One NetBird Network `lan` in `tofu/netbird.tf`, pod-2 as its router through the peer group `routing`, masquerade on
- Resources are single hosts, each in its own resource-only group: `res-edge` (`edge_ip`/32), `res-netbird` (`netbird_ip`/32), `res-lan` (`lan_cidr`)
- Peer groups `admin`, `household` and `routing`. Their members are the peer ids in `netbird_peers` in `private.yml`
- Policies, one group per side: `admin-lan` (admin to the LAN), `household-web` (household to edge on `https_port` (443)), `vpn-dns-admin` and `vpn-dns-household` (the `dns-relay` port from `apps.yml`, UDP and TCP, to `routing`)
- No policy lets household reach the NetBird VM yet. The resource and its group exist for it
- NetBird's built-in all-to-all policy is imported and disabled
- A posture check sets the oldest client a household device may use (`netbird_min_client_version`), on `household-web` and `vpn-dns-household`
- The nameserver group `lab` sends the lab domain to `dns-relay` on pod-2's overlay IP for `admin` and `household`. DNS management is off for `routing`
- One reusable setup key per peer group, with `netbird_setup_key_expiry_seconds`, read with `tofu output -json netbird_setup_keys`
- The provider `netbirdio/netbird` is pinned to exactly 0.0.11 in `tofu/providers.tf`. The token is the PAT of the service user `tofu` (`netbird_token`)

- Enforced by: NetBird's policy on the peers and the routing peer, the exact provider pin, and `tofu plan` showing anything changed in the dashboard

## Consequences

- Easier: a new device gets a group, not the whole LAN
- Easier: the VPN's rules are read in a diff, not in a dashboard
- Easier: the last network config that lived only in a database is in git

- Harder: a full `tofu plan` needs the NetBird VM up and a valid PAT
- Harder: a new peer needs its id added to `private.yml`, or the next plan removes it from its group

- Accepted: the LAN still sees pod-2 for every peer, so the per-person audit trail of [0022](0022-central-logging-relp.md) is lost for VPN logins
- Accepted: the PAT lives up to a year and is rotated by hand
- Accepted: a young provider, with its bug #268 (peers and resources in one group) worked around by the split groups
- Accepted: the provider has no registry signature, only the hashes in the lock file
- Accepted: the setup keys are plaintext in the local state

- Related: [0003](0003-netbird-instead-of-port-forwards.md) (NetBird), [0001](0001-tofu-and-cloud-init-for-vms.md) (OpenTofu), [0022](0022-central-logging-relp.md) (logging)
