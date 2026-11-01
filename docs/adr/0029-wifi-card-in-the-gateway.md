# 29. The IoT WiFi card moves into the gateway LXC, pve-1 leaves the IoT net

Status: Accepted

## Context

- The IoT WiFi came from hostapd on pve-1, bridged into `vmbr1` with `192.168.50.1` on the node. DHCP was dnsmasq on pve-1, set up by hand
- So the node itself had an address in the IoT net, and anyone on the IoT WiFi with the password could reach pve-1 directly
- The card is pve-1's onboard Intel AC 9560 (CNVi, `iwlwifi`), alone in its IOMMU group. The phy supports AP mode and `set_wiphy_netns`, so it can move into another network namespace
- CNVi passthrough to a VM is known to be flaky: the card has no clean reset, it lives partly in the chipset
- Tested 2026-11-01: with the phy moved into CT 302, hostapd in the unprivileged CT reaches `AP-ENABLED`. Setting the regulatory domain from inside fails (`Failed to set country code`), it needs root in the host namespace
- When the CT stops, the kernel hands the card back only once the CT's network namespace is gone, and under its name inside the CT (`wlan0`): LXC can't rename a WiFi card back. The next start then fails (`Failed to retrieve ifindex`)

- Alternatives:
  - Keep hostapd on pve-1, only DHCP onto the gateway (why not: pve-1 stays in the IoT net and needs its own firewall there)
  - A VM with the card passed through, e.g. OpenWrt (why not: CNVi passthrough without a clean reset, a whole VM for an AP)
  - A separate access point device, e.g. one running OpenWrt (why not: one more box with its own firmware and updates, the gateway already sits right next to the card)
- Why: the card moves cleanly into the LXC that already serves the IoT net, and pve-1 drops out of it completely

## Decision

- The first play of `deploy-iot.yml` adds raw `lxc.net.9` lines to CT 302's config on `iot_node`: `type: phys` on `iot_wifi_nic`, named `wlan0` inside, `iot_ip` set by LXC, up. LXC moves the whole phy into the CT at start and back to the node at stop. The API can't set raw `lxc` keys, so it's Ansible on the node, not tofu
- A changed line restarts the CT
- A hook on the node (`/usr/local/sbin/iot-wifi-back`) gives the card back: as `lxc.hook.stop` it renames it to `iot_wifi_nic` inside the CT's namespace and moves the phy to the node itself, as `lxc.hook.pre-start` it renames a stray `wlan0` in case the stop hook didn't run (crash). So every stop and start works: GUI, `pct`, tofu, boot
- The node keeps only the regulatory domain (`iot_wifi_country`, `cfg80211 ieee80211_regdom` at boot plus `iw reg set` now); hostapd in the CT runs without `country_code`
- `roles/iot_ap` in the CT: hostapd (WPA2, 2.4 GHz, TX power by a drop-in) and dnsmasq for DHCP on `wlan0` only (`iot_dhcp_range`, no DNS, no router option)
- No `vmbr1`, no address of pve-1 in the IoT net; CT 302 has no second veth
- Firewall: the card isn't a Proxmox NIC, so the PVE firewall never sees the IoT side. ufw inside filters it alone, only `on wlan0`: `iot_net_ports` (1883, 80) from `iot_cidr` and 67/udp for DHCP. `iot.fw` stays for the LAN leg and the egress limit

- Enforced by: the lines and the hook in `deploy-iot.yml`'s first play, the `wlan0` check at the start of `roles/iot_ap`, ufw's default deny

## Consequences

- Easier: pve-1 is out of the IoT net, nothing there can reach a node
- Easier: WiFi, DHCP, broker and firmware are one box, built by one playbook; moving to pve-2 is `iot_node` (and `iot_wifi_nic`)
- Easier: nothing set up by hand on the node anymore

- Harder: the IoT side has one firewall layer, ufw in the CT. A root shell in the CT can open the IoT side
- Harder: CT down means no IoT WiFi at all (before, the WiFi stayed up without the broker)
- Harder: a tofu rebuild of the CT drops the raw lines; `deploy-iot.yml` puts them back

- Accepted: the regulatory domain and the pre-start hook are node settings the CT depends on
- Accepted: the PVE firewall's `ipfilter` doesn't cover the card, so the CT could send from any address in the IoT net

- Related: [0028](0028-iot-gateway-lxc.md) (the gateway), [0026](0026-ufw-as-guest-firewall.md) (ufw), [0016](0016-ansible-vault-for-secrets.md) (WiFi passphrase in the vault)
