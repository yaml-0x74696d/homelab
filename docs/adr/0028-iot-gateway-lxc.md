# 28. IoT gateway LXC: MQTT hub, own firmware, one shared user without TLS

Status: Accepted

## Context

- The sensors sit on their own WiFi (`iot_cidr`, bridge `vmbr1` on pve-1), hostapd runs on pve-1 itself
- docker-1 had a second network card on that bridge, so the broker could reach the sensors. That put the IoT net one hop from Traefik, Authentik and Vaultwarden on the same VM
- Mosquitto, mqtt-exporter and ESPHome ran as compose apps on docker-1, anonymous MQTT, nothing of it was live
- I want MQTT as the hub: every device runs my own PlatformIO firmware, Home Assistant and Prometheus subscribe, more consumers can come later
- A rootless Podman app can't run in an unprivileged LXC: `roles/podman_app` gives each app a subuid range at `uid*65536`, the CT only maps 65536 ids

- Alternatives:
  - Keep the broker on docker-1 with its IoT leg (why not: a broken broker sits next to the vault and SSO, later pod-1)
  - Broker on the edge VM (why not: same problem, next to the proxy)
  - Own VM (why not: a whole kernel and 1 GB+ RAM on pve-1 for one daemon)
  - ESPHome for the firmware (why not: its native API ties the devices to Home Assistant, I want plain MQTT and my own code)
  - Per-device users with ACLs and TLS (why not: certificates on ESP32s and an ACL per device, for a few sensors in my own flat)
- Why: a small LXC is cheap, and a broken broker there only exposes the broker

## Decision

The gateway (`iot`, CT 302, `tofu/lxc.tf`):
- Debian 13 LXC, unprivileged, on `iot_node` (pve-1), the only guest on `vmbr1`
- Two legs: `iot_ip` (`.50.10`) on the IoT net without a gateway, `iot_lan_ip` (`.152`) on the LAN for the consumers. Nothing routes through it
- `iot_node` and the inventory group `iot_ap` (hostapd) name the node; `deploy-iot.yml` checks they match

What runs there (`playbooks/deploy-iot.yml`):
- Mosquitto from Debian (`roles/mosquitto`): one shared user `mqtt_user`, the password from the vault (`mqtt_password`), no anonymous logins, no TLS, plain `mqtt_port` (1883)
- Debian's `prometheus-mqtt-exporter` (`roles/mqtt_exporter`) on `mqtt_exporter_port` (9641), scraped by Prometheus
- `roles/lxc_base` like every LXC: SSH key-only, fail2ban, unattended security updates, node_exporter

Two firewall layers, the same inbound rules from one list (`mqtt_lan_clients`, `prometheus_ip` in `app_settings.yml`):
- The PVE guest firewall (`roles/pve_firewall`, `iot.fw`), enforced by the host, so a root shell in the CT can't open anything
- ufw inside (`deploy-iot.yml`, [0026](0026-ufw-as-guest-firewall.md)); it drops its own rules that left the list. Its default `before.rules` also answer ping and accept mDNS/UPnP multicast from anywhere, `iot.fw` doesn't
- From the IoT net: only 1883, and only on the IoT NIC (`-i net1`, `ipfilter` on)
- From the LAN: 1883 from Home Assistant's host, 9641 and node_exporter from Prometheus' host, SSH
- Out, in `iot.fw` only (`policy_out: DROP`): DNS to the router, RELP to the log LXC, HTTP/HTTPS to the internet for apt and ntfy. The rest of the LAN and the IoT net are dropped, ufw's outbound stays open
- Metrics: `iot_temperature_celsius`, `iot_humidity_percent`, the device in the `sensor` label

What may move onto the gateway:
- IoT-facing services: DHCP for the IoT net first (today dnsmasq on pve-1, by hand: static 192.168.50.2 to .49, DHCP .50 to .200), then NTP and OTA updates for the firmware
- Not apps. Home Assistant, dashboards and anything with a web UI stay on the app hosts

- Enforced by: `iot.fw` and ufw, the `iot_node`/`iot_ap` check in `deploy-iot.yml`, `allow_anonymous false` in the broker config

## Consequences

- Easier: a broken broker only exposes the broker, not the vault and SSO on pod-1 or the proxy on edge
- Easier: no VM has a leg in the IoT net
- Easier: everything there comes from Debian's repo and updates with `update.yml`, no images

- Harder: one more guest to keep running
- Harder: the firmware holds the MQTT password, a new password means reflashing every device
- Harder: Home Assistant's broker address is set in its UI, not in the repo

- Accepted: anyone on the IoT WiFi with the password can read and fake every sensor. Per-device users with ACLs and TLS stay possible later
- Accepted: MQTT crosses the LAN in plain text to Home Assistant
- Accepted: the gateway is not backed up, its config is in git and the broker state is disposable

- Later: moving the WiFi and the gateway to pve-2 (same WiFi card) is `iot_node` + `iot_ap`, plus the hand-made bridge, dnsmasq and hostapd's interface name on the new node

- Related: [0007](0007-group-vars-single-source-of-truth.md) (ips, ports), [0009](0009-aide-with-manual-accept.md) (AIDE excludes), [0016](0016-ansible-vault-for-secrets.md) (the password), [0022](0022-central-logging-relp.md) (logs), [0026](0026-ufw-as-guest-firewall.md) (ufw)
