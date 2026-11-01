# 28. IoT gateway LXC: MQTT hub, firmware pulled from the gateway, one shared user without TLS

Status: Accepted, the WiFi side amended by [0029](0029-wifi-card-in-the-gateway.md)

## Context

- The sensors (ESPHome or my own C) sit on their own WiFi. The broker ran on docker-1 with a leg in that net, one hop from the vault and SSO
- I want MQTT as the hub, and nothing connecting into the IoT net: the devices open every connection, firmware updates included

- Alternatives:
  - Broker on docker-1 or the edge VM (why not: a broken broker sits next to the vault, SSO or the proxy)
  - Own VM (why not: a kernel and 1 GB+ RAM for one daemon)
  - ESPHome's native API and push OTA (why not: Home Assistant would connect into the IoT net)
  - Per-device users, ACLs and TLS (why not: certificates on ESP32s for a few sensors in my flat)
- Why: a small LXC is cheap, and a broken broker there only exposes the broker

## Decision

- A Debian LXC (`iot`, CT 302) with a leg in the IoT net and one on the LAN, nothing routes through it
- Mosquitto, the MQTT exporter and an nginx for firmware files, all from Debian (`deploy-iot.yml`)
- One shared MQTT user, password in the vault, no TLS
- Devices talk MQTT only and pull their firmware from the gateway when Home Assistant tells them to
- Two firewall layers on the LAN leg: the PVE guest firewall and ufw, from the same lists
- Only IoT-facing services go there, no apps

## Consequences

- Easier: no VM is in the IoT net, nothing on the LAN needs a route into it
- Easier: everything is a Debian package and updates with `update.yml`
- Harder: a new MQTT password means reflashing every device
- Harder: a firmware update is three manual steps (build, scp, button)
- Accepted: anyone on the IoT WiFi with the password can read and fake every sensor, and trigger a flash of what the gateway serves
- Accepted: MQTT crosses the LAN in plain text to Home Assistant
- Accepted: no backup, config is in git and the broker state is disposable

- Related: [0016](0016-ansible-vault-for-secrets.md) (the password), [0026](0026-ufw-as-guest-firewall.md) (ufw), [0029](0029-wifi-card-in-the-gateway.md) (the WiFi card)
