# 28. IoT gateway LXC: MQTT hub, firmware pulled from the gateway, one shared user without TLS

Status: Accepted

## Context

- The sensors sit on their own WiFi (`iot_cidr`, bridge `vmbr1` on pve-1), hostapd runs on pve-1 itself
- A broker on docker-1 needs a second network card there on that bridge, which puts the IoT net one hop from Traefik, Authentik and Vaultwarden on the same VM
- I want MQTT as the hub: the devices run ESPHome (YAML) or my own C code, Home Assistant and Prometheus subscribe, more consumers can come later
- I want nothing to connect into the IoT net: the devices open every connection, and only to the gateway. That also covers firmware updates
- ESPHome's native API and its push OTA both need Home Assistant to connect to the device
- A rootless Podman app can't run in an unprivileged LXC: `roles/podman_app` gives each app a subuid range at `uid*65536`, the CT only maps 65536 ids

- Alternatives:
  - Broker on docker-1 with an IoT leg (why not: a broken broker sits next to the vault and SSO, later pod-1)
  - Broker on the edge VM (why not: same problem, next to the proxy)
  - Own VM (why not: a whole kernel and 1 GB+ RAM on pve-1 for one daemon)
  - ESPHome with its native API and push OTA (why not: Home Assistant connects into the IoT net, so the LAN needs a route there)
  - Per-device users with ACLs and TLS (why not: certificates on ESP32s and an ACL per device, for a few sensors in my own flat)
- Why: a small LXC is cheap, a broken broker there only exposes the broker, and with the firmware on the gateway too every connection starts in the IoT net

## Decision

The gateway (`iot`, CT 302, `tofu/lxc.tf`):
- Debian 13 LXC, unprivileged, on `iot_node` (pve-1), the only guest on `vmbr1`
- Two legs: `iot_ip` (`.50.10`) on the IoT net without a gateway, `iot_lan_ip` (`.152`) on the LAN for the consumers. Nothing routes through it
- `iot_node` and the inventory group `iot_ap` (hostapd) name the node; `deploy-iot.yml` checks they match

What runs there (`playbooks/deploy-iot.yml`):
- Mosquitto from Debian (`roles/mosquitto`): one shared user `mqtt_user`, the password from the vault (`mqtt_password`), no anonymous logins, no TLS, plain `mqtt_port` (1883)
- Debian's `prometheus-mqtt-exporter` (`roles/mqtt_exporter`) on `mqtt_exporter_port` (9641), scraped by Prometheus
- Debian's `nginx` (`roles/ota_server`) on `iot_ip`:`ota_port` (80) only: `/srv/firmware` read-only, no listing, GET/HEAD only. I copy the files there with scp over the LAN leg
- `roles/lxc_base` like every LXC: SSH key-only, fail2ban, unattended security updates, node_exporter

The devices:
- ESPHome compiled in the ESPHome add-on on Home Assistant, or my own C code. Device YAMLs and the C code live in a private repo, `secrets.yaml` comes from the vault
- MQTT only: no `api:`, Home Assistant finds them through MQTT discovery and sends commands over MQTT
- Topics `home/<device>/<measurement>` for every device (ESPHome: `topic_prefix` + a `state_topic` per sensor)
- Firmware updates are pulled: a "Flash from gateway" button in Home Assistant tells the device over MQTT to download `<device>.bin` from the gateway. Nothing updates on its own, the first flash is by USB

Two firewall layers, the same inbound rules from one list (`iot_net_ports`, `mqtt_lan_clients`, `prometheus_ip` in `app_settings.yml`):
- The PVE guest firewall (`roles/pve_firewall`, `iot.fw`), enforced by the host, so a root shell in the CT can't open anything
- ufw inside (`deploy-iot.yml`, [0026](0026-ufw-as-guest-firewall.md)); it drops its own rules that left the list. Its default `before.rules` also answer ping and accept mDNS/UPnP multicast from anywhere, `iot.fw` doesn't
- From the IoT net: only 1883 and 80, and only on the IoT NIC (`-i net1`, `ipfilter` on)
- From the LAN: 1883 from Home Assistant's host, 9641 and node_exporter from Prometheus' host, SSH
- Out, in `iot.fw` only (`policy_out: DROP`): DNS to the router, RELP to the log LXC, HTTP/HTTPS to the internet for apt and ntfy. The rest of the LAN and the IoT net are dropped, ufw's outbound stays open
- Metrics: `iot_temperature_celsius`, `iot_humidity_percent`, the device in the `sensor` label

What may move onto the gateway:
- IoT-facing services: DHCP for the IoT net first (today dnsmasq on pve-1, by hand: static 192.168.50.2 to .49, DHCP .50 to .200), then NTP
- Not apps. Home Assistant, dashboards and anything with a web UI stay on the app hosts

- Enforced by: `iot.fw` and ufw, the `iot_node`/`iot_ap` check in `deploy-iot.yml`, `allow_anonymous false` in the broker config, the IoT leg without a gateway

## Consequences

- Easier: a broken broker only exposes the broker, not the vault and SSO on pod-1 or the proxy on edge
- Easier: no VM has a leg in the IoT net
- Easier: nothing on the LAN needs a route into the IoT net, not even for firmware updates
- Easier: everything there comes from Debian's repo and updates with `update.yml`, no images

- Harder: one more guest to keep running
- Harder: the firmware holds the MQTT password, a new password means reflashing every device
- Harder: Home Assistant's broker address is set in its UI, not in the repo
- Harder: an update is three manual steps: download from the add-on, scp to the gateway, press the button. AIDE reports every new file in `/srv/firmware`

- Accepted: anyone on the IoT WiFi with the password can read and fake every sensor. Per-device users with ACLs and TLS stay possible later
- Accepted: MQTT crosses the LAN in plain text to Home Assistant
- Accepted: firmware goes over plain HTTP; the md5 only catches a broken download, anyone on the IoT WiFi with the password can trigger a flash of what the gateway serves
- Accepted: the gateway is not backed up, its config is in git, the broker state is disposable and the firmware files are rebuilt in the add-on

- Later: moving the WiFi and the gateway to pve-2 (same WiFi card) is `iot_node` + `iot_ap`, plus the hand-made bridge, dnsmasq and hostapd's interface name on the new node

- Related: [0007](0007-group-vars-single-source-of-truth.md) (ips, ports), [0009](0009-aide-with-manual-accept.md) (AIDE excludes), [0016](0016-ansible-vault-for-secrets.md) (the password), [0022](0022-central-logging-relp.md) (logs), [0026](0026-ufw-as-guest-firewall.md) (ufw)
