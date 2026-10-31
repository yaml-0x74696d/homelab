# homelab

- Overview of my 3-node Proxmox homelab. With this project I am going for full IaC, through Ansible, OpenTofu and NixOS.
- This repo is a showcase copy of my private repo (self-hosted Gitea), renamed and with placeholders.

![System landscape](docs/img/index.png)

- Interactive diagrams: [yaml-0x74696d.github.io/homelab](https://yaml-0x74696d.github.io/homelab/), all 21 views, clickable (built by `.github/workflows/pages.yml`)
- More pictures: [docs/architecture.md](docs/architecture.md) (zones, flows, per-node views)

## Overview

- 3 Proxmox nodes, 4 VMs + 2 LXCs, 22 compose apps + 2 Podman apps + hostapd, 16 Ansible roles, 38 playbooks, 21 C4 views
- 3 tools, 1 set of facts: provisioning through OpenTofu, configuration through Ansible, the WAN-facing VM declared in NixOS
- Remote access through NetBird: the router forwards only to the NixOS VM, never directly to an app
- Every check runs the same locally and in CI: 18 pre-commit hooks (`just check`)

## Hardware

| Node | Box | RAM | Role |
|---|---|---|---|
| pve-1 | Dell Wyse 5070 | 8 GB | Running the IoT WiFi AP directly |
| pve-2 | Dell Wyse 5070 | 8 GB | Running the NetBird VM and routing peer |
| pve-3 | Old gaming PC (Gigabyte 970A, GT 710) | 16 GB | ~11 TB HDD in a mergerfs pool, running PBS |

## VM/LXC

| Guest | ID | Node | CPU | RAM (balloon floor) | Disk | IP |
|---|---|---|---|---|---|---|
| docker-1 | VM 201 | pve-1 | 4 | 4 GB (3 GB) | 32 GB | .201 (+ IoT IP on `vmbr1`) |
| docker-2 | VM 202 | pve-2 | 4 | 4 GB (2 GB) | 32 GB | .202 (+ DNS service IP .53) |
| docker-3 | VM 203 | pve-3 | 4 | 12 GB (8 GB) | 32 GB | .203 |
| netbird | VM 250 | pve-2 | 2 | 2 GB (1 GB) | 20 GB | .250 |
| storage | CT 300 | pve-3 | 2 | 2 GB + 512 MB swap | 24 GB | .150 |
| log | CT 301 | pve-3 | 1 | 512 MB + 256 MB swap | 32 GB | .151 |

- Specs can be found in `tofu/locals.tf`; IDs + IPs are in `ansible/group_vars/all/network.yml`

## Stack

- Proxmox (3 nodes) · OpenTofu (bpg/proxmox) · Ansible · Docker Compose · NixOS (NetBird VM) · PBS · NetBird · Traefik · Pi-hole · Authentik

## What runs

| Group | App | Host | Purpose |
|---|---|---|---|
| Ingress | Traefik (`proxy`) | docker-1 | Reverse proxy, TLS via Cloudflare DNS |
| Ingress | Pi-hole (`dns`) | docker-2 | DNS + ad blocking, split-horizon records |
| Ingress | cloudflare-ddns (`utilities`) | docker-1 | Keeps the public record current |
| Identity | Authentik | docker-1 | SSO, OIDC + forward-auth |
| Identity | Vaultwarden | docker-1 | Passwords |
| Media | Immich | docker-3 | Photos |
| Media | Jellyfin | docker-3 | Video |
| Media | Nextcloud | docker-3 | Files |
| Media | Paperless | docker-3 | Documents |
| Home | Home Assistant | docker-1 | Home automation |
| Home | ESPHome | docker-1 | ESP32 sensor firmware |
| Home | Mosquitto | docker-1 | MQTT broker |
| Home | mqtt-exporter | docker-1 | MQTT → Prometheus |
| Home | hostapd | pve-1 | IoT WiFi bridge |
| Monitoring | Prometheus | docker-2 | Metrics |
| Monitoring | Grafana | docker-2 | Dashboards |
| Monitoring | InfluxDB | docker-2 | Time series database |
| Monitoring | Gatus | docker-2 | Uptime checks, generated from the apps map |
| Monitoring | Diun | All Docker hosts | Image update notices |
| Tools | Homepage (`dashboard`) | docker-1 | Landing page |
| Tools | Gitea | docker-1 | git server |
| Tools | SearXNG | docker-1 | Search engine |
| Tools | pdfcraft | docker-1 | PDF tools |
| Tools | nginx | docker-2 | Website |
| Tools | docker-socket-proxy (`docker-proxy`) | All Docker hosts | Read-only Docker API for Homepage |

## File layout

```
tofu/            VMs + LXCs on Proxmox (bpg/proxmox, Debian cloud image, cloud-init)
ansible/
  group_vars/all/  Variables: network, ports, storage, hosts, apps, base (+ vault.yml.example, private/private.yml.example)
  inventory.yml    docker_hosts, proxmox, lxc_containers, netbird_agent
  roles/           aide, chrony, cronie, docker_app, journald, login_notify, mergerfs, netbird_agent, pbs, podman_app, podman_base, pve_firewall, rsyslog, samba, update, vm_base
  apps/<name>/     Compose file + templates per app (25), hostapd config
  playbooks/       deploy-<app>.yml, deploy-app.yml (podman), site.yml, vm-preparation, update, aide, push-keys, ...
nixos/           Flake for the NetBird VM (+ update.sh, aide-accept.sh)
architecture/    LikeC4 model: landscape, containers, deployment, 8 flows
docs/            Architecture, ADRs, exported diagrams
justfile         setup · lint · check · deploy · deploy-app · c4 · diagrams
```

## Single source of truth

- Ansible group_vars get read by OpenTofu (yamldecode) and Nix (facts.nix), so an IP only has to change in one place ([ADR 0007](docs/adr/0007-group-vars-single-source-of-truth.md))
- `tofu/locals.tf` reads `network.yml`, `ports.yml`, `hosts.yml`, `storage.yml`, `private/private.yml` with `yamldecode`
- `nixos/facts.nix` turns `network`, `ports`, `hosts`, `apps`, `base`, `private/private.yml` YAML into JSON with yq-go
- `nixos/update.sh` + `aide-accept.sh` read the NetBird IP from the same file
- Ports: one `app_ports` map → compose, Traefik routes, Homepage tiles, Prometheus targets, firewall
- Secrets: one `vault.yml` (Ansible Vault), every app gets them via its `.env.j2` → `${VAR}` in compose
- No magic numbers: every timeout, schedule, size and port is a named variable (role defaults, playbook `vars:`, Nix `let`)

## Deployment

- Copy `vault.yml.example` → `vault.yml`, create `ansible/.vault_pass`
- Copy `private/private.yml.example` → `private/private.yml` and fill in your domain, macs, disk uuids, keys (gitignored, nothing secret)
- `just setup` · `just check` · `just deploy <app>` · `just c4`
- Needs: just, pre-commit, Ansible, OpenTofu, Nix, Node, d2 (only for `just diagrams`) (the hooks install ansible-lint, yamllint, shellcheck, gitleaks)
- OpenTofu: tfvars from the example, `tofu apply`
- Ansible: `vm-preparation.yml`, then `site.yml` or one `deploy-<app>.yml`
- Plain `ansible-playbook` is the main path; `ansible-navigator.yml` = optional EE run
- NixOS: nixos-anywhere once, then `nixos/update.sh`. `nix flake check` needs builds (facts.nix), `--no-build` fails

## Security

- WAN: only the NetBird VM is forwarded (443/tcp, 3478/udp, narrow TURN relay range); apps are LAN / VPN only
- PVE firewall (`roles/pve_firewall`): cluster policy drop, NetBird VM fenced (inbound = what NetBird serves, egress to the LAN limited to routing peer + DNS/HTTPS + RELP to the log LXC); host lockdown layer written, off by default (lockout risk)
- Docker VMs (`vm-preparation.yml` = `roles/vm_base` + ufw + Docker): ufw default deny, SSH key-only + rate-limited, no root login, auditd, AppArmor, fail2ban, sysctl hardening, unattended security updates
- Published container ports bypass ufw → filtered in `DOCKER-USER` by source (only Traefik / Prometheus hosts reach backends)
- Docker daemon: `no-new-privileges`, `live-restore`, capped JSON logs; Homepage reads Docker only through a read-only socket proxy
- NetBird VM (NixOS): nftables default-deny, SSH LAN-only, AppArmor, fail2ban, kernel sysctls, auto-upgrade with reboot window
- NetBird dashboard + API LAN/VPN only: the WAN sees just the gRPC endpoints peers need; probes get a silent close (444) and a fail2ban ban
- Identity: Authentik OIDC for the apps (local admin kept as break-glass, except Vaultwarden), forward-auth for apps without SSO
- TLS everywhere via Let's Encrypt DNS-01 (Cloudflare), no port 80 forwarded from the WAN
- AIDE on every host + the NetBird VM: daily check, ntfy alert with counts only, accept by hand, DB hash kept on the controller
- login-notify: ntfy push on every SSH / Proxmox web login (PVE hosts)
- Backups: PBS, scoped token that can only write, DB dumps before each run
- Secrets: Ansible Vault; gitleaks on every commit and over the full history in CI

## Decisions

- [docs/adr/](docs/adr/README.md): 27 records
- 0001 OpenTofu + cloud-init · 0002 generic app role · 0003 NetBird · 0004 mergerfs · 0005 prevent_destroy
- 0006 `:latest` + Diun · 0007 group_vars as source of truth · 0008 NixOS DMZ · 0009 AIDE · 0010 Pi-hole service IP
- 0011 Proxmox as hypervisor · 0012 no Kubernetes · 0013 PBS file-level backups · 0014 Authentik · 0015 TLS via DNS-01
- 0016 Ansible Vault · 0017 SMB to the Docker VMs · 0018 DOCKER-USER filtering · 0019 ntfy alerts · 0020 same checks locally + CI · 0021 Podman quadlets (proposed)
- 0022 central logging over RELP · 0023 chrony with NTS · 0024 OS updates through Ansible · 0025 Debian guests until x86-64-v3 · 0026 ufw as the guest firewall · 0027 Gatus from the apps map

## Future plans

- Phase 1: `podman_base` + `podman_app` roles, quadlet conventions (pinned image + auto-update, CIFS automount + `findmnt` start gate), restore rehearsal runbook, CI quadlet dry-run
- Phase 2: edge = NixOS VM on pve-1 (1 GB) running Traefik + AdGuard Home natively (replaces the Traefik + Pi-hole containers)
- Phase 3–4: docker-2 / docker-3 rebuilt as Podman hosts, rootless per app, same VMID/IP/MAC; gated by a restore rehearsal
- Phase 5: Home Assistant moves to HAOS (VM on pve-3)
- Phase 6: docker-1 → Podman (Authentik, SearXNG)
- Podman auto-update with rollback replaces `:latest` + Diun (ADR 0006)
- Later: guest OS Debian → EL10 once the hardware has x86-64-v3 / AVX2 ([ADR 0025](docs/adr/0025-debian-guests-until-x86-64-v3.md)); Proxmox hosts stay Debian
- From then on: real commits on this repo

## License

MIT, see [LICENSE](LICENSE).
