# iot_ap

- The IoT WiFi, run inside the gateway LXC: hostapd on the WiFi card, DHCP from dnsmasq
- The card itself is moved into the LXC by `roles/iot_node`, with a hook on the node that hands it back when the CT stops ([ADR 0029](../../../docs/adr/0029-wifi-card-in-the-gateway.md))

## Runs on

- The IoT gateway LXC (CT 302), in `playbooks/deploy-iot.yml`, after the card is in (`wlan0`)

## How it works

1. Stops with a hint if `wlan0` isn't in the CT
2. Installs `hostapd`, `dnsmasq` and `iw`
3. `/etc/hostapd/hostapd.conf` (root, 0600, never in `--diff`): WPA2-PSK, 2.4 GHz. No `country_code`: setting the regulatory domain needs the host's root, so `iot_node` sets it (`iot_wifi_country`)
4. A drop-in sets the TX power after every hostapd start (`iw dev wlan0 set txpower`)
5. `/etc/dnsmasq.d/iot.conf`: DHCP on `wlan0` only, `iot_dhcp_range`, no DNS (`port=0`), no router option
6. Unmasks and starts both (Debian masks hostapd until it has a config)

The CT's address on `wlan0` (`iot_ip`) comes from LXC itself (`lxc.net.9.ipv4.address`), so it's up before nginx and the broker start.

## Settings

<!-- settings:start -->
| Variable | Default | What |
|---|---|---|
| `iot_ap_interface` | `wlan0` | the card inside the CT |
| `iot_ap_ssid` | `wifi_ssid` | the network name (vault) |
| `iot_ap_passphrase` | `wifi_pass` | WPA2 passphrase (vault) |
| `iot_ap_channel` | `6` | 2.4 GHz channel |
| `iot_ap_txpower` | `1300` | mBm, 13 dBm: the flat, not the street |
| `iot_ap_dhcp_range` | `iot_dhcp_range` | first and last DHCP address (network.yml) |
| `iot_ap_dhcp_lease` | `12h` | lease time |
<!-- settings:end -->

## Notes

- Test: `iw dev` in the CT shows `type AP` and the SSID, `journalctl -u hostapd -u dnsmasq` shows associations and leases
- The ufw rules for the WiFi (`iot_net_ports` and DHCP, only `on wlan0`) are in the playbook, with the rest of the CT's ufw

## Related

- [ADR 0029: the IoT WiFi card moves into the gateway LXC](../../../docs/adr/0029-wifi-card-in-the-gateway.md)
- [ADR 0028: IoT gateway LXC](../../../docs/adr/0028-iot-gateway-lxc.md)
- `iot_node` role (the card), `playbooks/deploy-iot.yml`
