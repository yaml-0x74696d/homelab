# iot_node

- The node side of the IoT gateway: moves the node's WiFi card into CT 302 and hands it back when the CT stops
- Everything else about the WiFi runs in the CT (`roles/iot_ap`), [ADR 0029](../../../docs/adr/0029-wifi-card-in-the-gateway.md)

## Runs on

- `iot_node` (pve-1), first play of `playbooks/deploy-iot.yml`

## How it works

1. Regulatory domain: `cfg80211 ieee80211_regdom` in `/etc/modprobe.d` for the next boot, `iw reg set` now if it differs. The CT isn't allowed to set it
2. `/usr/local/sbin/iot-wifi-back` (from `files/`) plus `/etc/default/iot-wifi` with the card's name
3. Raw lines in `/etc/pve/lxc/<ct>.conf`, the API can't set them: `lxc.net.9` as `phys` on the card, named `wlan0` in the CT, with `iot_ip`; the script as `lxc.hook.stop` and `lxc.hook.pre-start`
4. A changed line restarts the CT (`pct shutdown` + `start`, not reboot) and waits for its SSH

The hook: left alone, a stopped CT hands the card back minutes later (with its network namespace) and as `wlan0`, with the old name taken as an `altname`, so the next start fails. On stop it renames the card inside the CT's namespace and moves the phy to the node itself; on pre-start it renames a stray `wlan0`, in case the stop hook didn't run.

## Settings

| Variable | Default | What |
|---|---|---|
| `iot_node_ct` | `vmids.iot` | The gateway CT |
| `iot_node_nic` | `iot_wifi_nic` (`network.yml`) | The card's name on the node |
| `iot_node_country` | `iot_wifi_country` | Regulatory domain |
| `iot_node_ct_address` | `iot_ip` + prefix | The CT's address on the card, set by LXC |
| `iot_node_ct_start_timeout` | `120` | Seconds until SSH answers after a restart |
| `iot_node_ct_lines` | see defaults | The raw LXC lines |

## Notes

- A tofu rebuild of the CT drops the raw lines, the next `deploy-iot.yml` puts them back
- No `#` markers in `/etc/pve`: Proxmox moves comment lines into the guest's description
- CT won't start (`Failed to retrieve ifindex`): see "Check it" in `docs/iot.md`
