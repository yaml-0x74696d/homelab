# pve_firewall

- Writes the cluster, host and guest firewall rules from the shared variables
- Scope: the NetBird VM, the log LXC, the IoT gateway LXC, the HAOS VM and the management access to the PVE hosts. The pod VMs and the storage LXC stay unfiltered
- Done with Ansible, not OpenTofu, because bpg/proxmox can't manage the host-level firewall options

## Runs on

- proxmox (`playbooks/deploy-pve-firewall.yml`, `gather_facts: false`)
- The cluster-wide files are written once (`run_once`), `host.fw` once per node

## How it works

1. Touches each target file first, because `/etc/pve` is pmxcfs and `copy` can't create files there
2. `cluster.fw` (once): master switch, default policy, ipsets, the `pve-mgmt` group
3. One file each for the NetBird VM, the log LXC, the IoT gateway LXC and the HAOS VM (once)
4. `enable: 0` for every guest in `pve_firewall_open_guests`
5. `host.fw` on every node
6. `pve-firewall compile` checks the result

## Files it manages

| File | What |
|---|---|
| `/etc/pve/firewall/cluster.fw` | Master switch, default policy, ipsets, the `pve-mgmt` group |
| `/etc/pve/firewall/<netbird vmid>.fw` | The NetBird VM's allow list and egress rules |
| `/etc/pve/firewall/<log vmid>.fw` | The log LXC: RELP only from known hosts |
| `/etc/pve/firewall/<iot vmid>.fw` | The IoT gateway LXC: inbound as its ufw, egress limited |
| `/etc/pve/firewall/<haos vmid>.fw` | The HAOS VM: HA's port from Traefik and Homepage, admins direct |
| `/etc/pve/firewall/<vmid>.fw` | `enable: 0` for each guest that stays open |
| `/etc/pve/nodes/<node>/host.fw` | Host lockdown, uses `GROUP pve-mgmt` |

## Cluster

- Incoming is dropped by default (`policy_in: DROP`), outgoing is allowed (`policy_out: ACCEPT`)
- ipsets:
  - `pve_ssh`: the admin hosts
  - `pve_ui`: the admins, the Homepage widget and Gatus
  - `pve_nodes`: the nodes themselves (corosync, migration)
- The `pve-mgmt` group allows SSH from `pve_ssh`, the web UI from `pve_ui`, the PBS port and ICMP from the LAN, and everything between the nodes

## NetBird VM

- In: 443, STUN/TURN on 3478 + 5349 (TCP+UDP), the narrowed TURN relay range (UDP), node-exporter from Prometheus' host, and SSH + ICMP from the LAN only
- Out: everything to the routing peers, because the TURN relay uses arbitrary ports
- Out: DNS + HTTPS to `pve_firewall_netbird_dns_https`, DNS to the gateway, RELP to the log LXC
- Out: the rest of the LAN is dropped, the internet is open

## Log LXC

- In: RELP (`log_relp_port`) from `pve_firewall_log_sources` only, node-exporter from Prometheus' host, SSH + ICMP from the LAN
- Out: open

## IoT gateway LXC

- Inbound the same as the ufw inside (`playbooks/deploy-iot.yml`), so a root shell in the CT can't open anything. Both read `mqtt_lan_clients` and `prometheus_ip`. ufw's default `before.rules` additionally answer ping (and take mDNS/UPnP multicast) from anywhere
- Covers the LAN leg (`net0`) only. The IoT net is the CT's WiFi card (`wlan0`, moved in by `deploy-iot.yml`), not a Proxmox NIC, so only the ufw inside filters it ([ADR 0029](../../../docs/adr/0029-wifi-card-in-the-gateway.md))
- `ipfilter: 1`: the NIC only sends from its own configured IP
- In from the LAN: `mqtt_port` from Home Assistant's host, `mqtt_exporter_port` and node-exporter from Prometheus' host, SSH + ICMP
- Out (`policy_out: DROP`): DNS to the router (the CT's resolver), RELP to the log LXC, HTTP/HTTPS to the internet (apt, ntfy). The rest of the LAN is dropped. No NTP, the CT uses the host's clock
- ufw inside only filters inbound, its outbound stays allow; the egress limit is this file

## HAOS VM

- In (`policy_in: DROP`): HA's port from `pve_firewall_haos_callers` (Traefik, Homepage's status dot), HA's port and the Observer (4357) from the admin hosts, ping from the LAN
- So `ha.<domain>` is the way in, and nothing on the LAN reaches the Supervisor or the add-on ports
- Out stays open: MQTT to the gateway, the router integration, updates
- LAN devices that fetch media from HA directly (Cast, TTS) are dropped too, they'd need a rule

## Rollout

Every guest's network card has `firewall=1`, so turning on the master switch drops traffic to all of them at once. That's why it goes in stages:

1. Pre-flight: list the guests with the firewall bit (`qm config` / `pct config` piped to `grep firewall=1`). Every one except NetBird, the log LXC, the IoT LXC and HAOS goes into `pve_firewall_open_guests`
2. Stage 0: both switches off, files written, check the compiled ruleset
3. Stage 1: master switch on, so only NetBird, the log + IoT LXCs and HAOS are filtered
4. Stage 2: host lockdown on one node, test SSH and `:8006` from an admin device, then the other nodes
5. Stage 3: set both defaults to true, or a plain re-run turns them off again

- Locked out? On the node's console run `pve-firewall stop`, or set `enable: 0` in the file

## Settings

<!-- settings:start -->
| Variable | Default | What |
|---|---|---|
| `pve_firewall_cluster_enabled` | `true` | Master switch. On means the NetBird VM, the log + IoT LXCs and the HAOS VM are filtered |
| `pve_firewall_host_enabled` | `false` | Host management lockdown, the layer that can lock you out |
| `pve_firewall_lan_cidr` | `lan_cidr` | The LAN |
| `pve_firewall_gateway_ip` | `gateway_ip` | The router, DNS fallback for the NetBird VM |
| `pve_firewall_routing_peers` | see `defaults/main.yml` | Hosts the NetBird VM may reach fully, default the `netbird_agent` group |
| `pve_firewall_netbird_dns_https` | `[app_sources.edge, dns_ip] + ingress_extra_sources` | LAN hosts the NetBird VM may reach on DNS and HTTPS only |
| `pve_firewall_ssh_hosts` | `admin_hosts` | May SSH to the nodes |
| `pve_firewall_ui_hosts` | see `defaults/main.yml` | Who may open the web UI (8006), default `admin_hosts` + `admin_ui_hosts` + pod-1 + pod-2 |
| `pve_firewall_node_ips` | `['{{ pve1_ip }}', '{{ pve2_ip }}', '{{ pve3_ip }}']` | The nodes, for corosync and migration |
| `pve_firewall_netbird_vmid` | `vmids.netbird` | The NetBird VM |
| `pve_firewall_netbird_relay_range` | `{{ netbird_relay_ports.min }}:{{ netbird_relay_ports.max }}` | TURN relay ports, min:max |
| `pve_firewall_netbird_turn_ports` | `[3478, 5349]` | STUN/TURN and TURN over TLS |
| `pve_firewall_log_vmid` | `vmids.log` | The log LXC |
| `pve_firewall_log_ip` | `log_ip` | The log LXC, target of the NetBird VM's RELP rule |
| `pve_firewall_log_port` | `log_relp_port` | RELP port |
| `pve_firewall_log_sources` | see `defaults/main.yml` | Hosts that may send RELP to the log LXC, default pod-1/2/3, storage, iot, netbird, edge, ctl-1 |
| `pve_firewall_prometheus_ip` | `prometheus_ip` | May scrape the log and IoT LXCs |
| `pve_firewall_iot_vmid` | `vmids.iot` | The IoT gateway LXC |
| `pve_firewall_iot_mqtt_clients` | `mqtt_lan_clients` | May reach the broker from the LAN |
| `pve_firewall_haos_vmid` | `vmids.haos` | The HAOS VM |
| `pve_firewall_haos_port` | `apps['homeassistant'].port` | HA's web port |
| `pve_firewall_haos_callers` | see `defaults/main.yml` | May reach HA's port, default `app_sources.edge` and Homepage's host |
| `pve_firewall_haos_observer_port` | `4357` | The Supervisor's health page, admins only |
| `pve_firewall_open_guests` | see `defaults/main.yml` | VMIDs that stay unfiltered, default edge, pod-1/2/3, storage |
<!-- settings:end -->

## Notes

- The switches must match what's live, a re-run flips them
- `/etc/pve` is pmxcfs: copy can't create files there and there's no atomic rename. So the role creates the file first, then templates it with `unsafe_writes`
- pmxcfs sets fixed file modes and doesn't allow chmod, hence the `noqa` on the mode
- The NetBird egress follows `app_sources.edge`, `dns_ip` and the `netbird_agent` group. Any other LAN target needs a new OUT rule

## Related

- [ADR 0003: NetBird instead of port forwards](../../../docs/adr/0003-netbird-instead-of-port-forwards.md)
- `netbird_agent` role (defines the routing peers), `nixos/netbird/` (the VM itself)
