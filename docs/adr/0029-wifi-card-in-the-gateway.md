# 29. The IoT WiFi card moves into the gateway LXC

Status: Accepted

## Context

- hostapd and DHCP ran on pve-1, bridged into the IoT net, so the node itself had an address there
- The card (Intel AC 9560, CNVi) can move into another network namespace; tested, hostapd runs in the unprivileged CT

- Alternatives:
  - Keep the AP on pve-1, only DHCP onto the gateway (why not: pve-1 stays in the IoT net)
  - A VM with the card passed through, e.g. OpenWrt (why not: CNVi has no clean reset, a whole VM for an AP)
  - A separate AP device (why not: one more box with its own firmware)
- Why: pve-1 drops out of the IoT net completely, WiFi and gateway become one box

## Decision

- `deploy-iot.yml` moves the card into CT 302 with raw `lxc.net` lines (the API can't set them), hostapd and DHCP run in the CT (`roles/iot_ap`)
- pve-1 only keeps the regulatory domain, the CT isn't allowed to set it
- A hook on pve-1 hands the card back when the CT stops, otherwise it returns minutes later under the wrong name and the next start fails

## Consequences

- Easier: no node in the IoT net, nothing set up by hand on pve-1
- Easier: moving to pve-2 is `iot_node` and the card's name
- Harder: the IoT side has one firewall layer, ufw in the CT
- Harder: CT down means no IoT WiFi
- Accepted: the CT depends on node settings (regulatory domain, the hook) that tofu doesn't know about

- Related: [0028](0028-iot-gateway-lxc.md) (the gateway), [0026](0026-ufw-as-guest-firewall.md) (ufw)
