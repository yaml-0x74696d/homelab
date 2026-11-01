# 30. Home Assistant as a HAOS VM on pve-3

Status: Accepted

## Context

- Home Assistant ran as a container on docker-1, so no add-ons (ESPHome compiles the device firmware there) and no Supervisor
- pve-1 and pve-2 carry the vital services and have about 1 GB of RAM left, pve-3 has the RAM

- Alternatives:
  - A Podman app in pod-1 on pve-1 (why not: still no add-ons)
  - HAOS on pve-1 (why not: pve-1 runs full, no headroom left for edge)
- Why pve-3: room for 3 GB, firmware compiles included. HA being off while pve-3 is off is accepted

## Decision

- HAOS VM 210 on pve-3 (`haos_ip`), built by OpenTofu from the HAOS image, 3 GB without a balloon floor
- An appliance: HA updates and configures itself, Ansible never logs in. `haos` is in the inventory group `appliances` only so `apps.yml` can name it (`runtime: vm`)
- No cloud-init in HAOS: the IP is a FRITZ!Box DHCP reservation on the MAC OpenTofu pins
- The PVE guest firewall (`haos.fw`) only lets Traefik and Homepage reach HA's port, the admin hosts also reach it and the Observer directly
- Behind Traefik: the trusted proxies are set in HA's UI (Settings → Network), HA keeps them in `.storage/http` and ignores an `http:` block in the YAML

## Consequences

- Easier: add-ons and HA's own updates, pve-1 has room for edge
- Harder: HA's config isn't in git, a rebuild means a restore
- Harder: the trusted proxies change by hand when Traefik moves (edge)
- Accepted: HA and its automations are off while pve-3 is off

- Related: [0028](0028-iot-gateway-lxc.md) (the MQTT broker HA uses), [0001](0001-tofu-and-cloud-init-for-vms.md) (OpenTofu)
