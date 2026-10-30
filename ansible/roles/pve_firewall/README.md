# pve_firewall

- Writes the cluster, host and guest firewall rules from the shared variables
- Scope: the NetBird VM, the log LXC and the management access to the PVE hosts. The Docker VMs and the storage LXC stay unfiltered
- Done with Ansible, not OpenTofu, because bpg/proxmox can't manage the host-level firewall options

## Runs on

- proxmox (`playbooks/deploy-pve-firewall.yml`, `gather_facts: false`)
- The cluster-wide files are written once (`run_once`), `host.fw` once per node

## Files it manages

| File | What |
|---|---|
| `/etc/pve/firewall/cluster.fw` | Master switch, default policy, ipsets, the `pve-mgmt` group |
| `/etc/pve/firewall/<netbird vmid>.fw` | The NetBird VM's allow list and egress rules |
| `/etc/pve/firewall/<log vmid>.fw` | The log LXC: RELP only from known hosts |
| `/etc/pve/firewall/<vmid>.fw` | `enable: 0` for each guest that stays open |
| `/etc/pve/nodes/<node>/host.fw` | Host lockdown, uses `GROUP pve-mgmt` |

- At the end, `pve-firewall compile` checks the result

## Cluster

- Incoming is dropped by default (`policy_in: DROP`), outgoing is allowed (`policy_out: ACCEPT`)
- ipsets:
  - `pve_ssh`: the admin hosts
  - `pve_ui`: the admins, the Homepage widget and Uptime Kuma
  - `pve_nodes`: the nodes themselves (corosync, migration)
- The `pve-mgmt` group allows SSH from `pve_ssh`, the web UI from `pve_ui`, the PBS port and ICMP from the LAN, and everything between the nodes

## NetBird VM

- In: 443, STUN/TURN on 3478 + 5349 (TCP+UDP), the narrowed TURN relay range (UDP), and SSH + ICMP from the LAN only
- Out: everything to the routing peers, because the TURN relay uses arbitrary ports
- Out: DNS + HTTPS to `pve_firewall_netbird_dns_https`, DNS to the gateway, RELP to the log LXC
- Out: the rest of the LAN is dropped, the internet is open

## Log LXC

- In: RELP (`log_relp_port`) from `pve_firewall_log_sources` only, SSH + ICMP from the LAN
- Out: open

## Settings

| Variable | Default | What |
|---|---|---|
| `pve_firewall_cluster_enabled` | `true` | Master switch. On means the NetBird VM and the log LXC are filtered |
| `pve_firewall_host_enabled` | `false` | Host management lockdown, the layer that can lock you out |
| `pve_firewall_lan_cidr` | `lan_cidr` | The LAN |
| `pve_firewall_gateway_ip` | `gateway_ip` | The router, DNS fallback for the NetBird VM |
| `pve_firewall_open_guests` | docker-1/2/3, storage | VMIDs that stay unfiltered |
| `pve_firewall_routing_peers` | the `netbird_agent` group | Hosts the NetBird VM may reach fully |
| `pve_firewall_netbird_dns_https` | docker-1, `dns_ip` | Hosts the NetBird VM may reach on DNS + HTTPS (Traefik, Pi-hole) |
| `pve_firewall_ssh_hosts` | `admin_hosts` | Who may SSH into the nodes |
| `pve_firewall_ui_hosts` | `admin_hosts` + `admin_ui_hosts` + docker-1 + docker-2 | Who may open the web UI (8006) |
| `pve_firewall_node_ips` | pve-1/2/3 | The cluster nodes |
| `pve_firewall_netbird_vmid` | `vmids.netbird` | The NetBird VM |
| `pve_firewall_netbird_relay_range` | from `netbird_relay_ports` | TURN relay ports |
| `pve_firewall_netbird_turn_ports` | `[3478, 5349]` | STUN/TURN and TURN over TLS |
| `pve_firewall_log_vmid` | `vmids.log` | The log LXC |
| `pve_firewall_log_ip` | `log_ip` | The log LXC, target of the NetBird VM's RELP rule |
| `pve_firewall_log_sources` | docker-1/2/3, storage, netbird | Hosts that may send RELP to the log LXC |
| `pve_firewall_log_port` | `log_relp_port` | The RELP port |

## Rollout

Every guest's network card has `firewall=1`, so turning on the master switch drops traffic to all of them at once. That's why it goes in stages:

1. Pre-flight: list the guests with the firewall bit (`qm config` / `pct config` piped to `grep firewall=1`). Every one except NetBird and the log LXC goes into `pve_firewall_open_guests`
2. Stage 0: both switches off, files written, check the compiled ruleset
3. Stage 1: master switch on, so only NetBird and the log LXC are filtered
4. Stage 2: host lockdown on one node, test SSH and `:8006` from an admin device, then the other nodes
5. Stage 3: set both defaults to true, or a plain re-run turns them off again

- Locked out? On the node's console run `pve-firewall stop`, or set `enable: 0` in the file

## Notes

- The switches must match what's live, a re-run flips them
- `/etc/pve` is pmxcfs: copy can't create files there and there's no atomic rename. So the role creates the file first, then templates it with `unsafe_writes`
- pmxcfs sets fixed file modes and doesn't allow chmod, hence the `noqa` on the mode
- If Authentik or Gitea move to another host, or the TURN relay needs another LAN peer, the NetBird egress needs a new OUT rule

## Related

- [ADR 0003: NetBird instead of port forwards](../../../docs/adr/0003-netbird-instead-of-port-forwards.md)
- `netbird_agent` role (defines the routing peers), `nixos/netbird/` (the VM itself)
