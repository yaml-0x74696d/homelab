# 35. NixOS for the NetBird VM and edge

Status: Accepted

## Context

- The NetBird control plane is the only VM that takes inbound WAN traffic (443/tcp, 3478/udp and a small TURN relay range). The router's WireGuard is the only other way in
- edge runs Traefik and AdGuard Home, so every route and the LAN DNS depend on it ([0032](0032-edge-vm-traefik-adguard-on-nixos.md))
- Both keep little state: the NetBird SQLite store on one, the certificate and AdGuard's query log on the other. Both are cheap to rebuild
- Everything else runs Debian + Ansible
- [0008](0008-nixos-for-the-dmz-box.md) chose NixOS for the NetBird VM only. edge joined the same flake later, and 0008 never said so

- Alternatives:
  - Debian + Ansible like the rest (why not: not fully declared, no easy rollback)
  - NetBird in a container on a pod VM (why not: no real DMZ)
- Why: the two VMs the WAN and the LAN depend on get atomic upgrades and a rollback to the previous generation

## Decision

The setup:
- One NixOS flake in `nixos/`, with `nixosConfigurations.netbird` and `nixosConfigurations.edge`
- Shared modules in `nixos/base/`: `hardening.nix`, `aide.nix`, `logging.nix`, `time.nix`, `disko.nix`
- nixpkgs unstable, for the `services.netbird.server` module
- NetBird runs natively, no containers: management, signal and dashboard from the nixpkgs module, coturn for STUN/TURN, nginx with ACME DNS-01 ([0034](0034-tls-via-dns-01.md))

Install and updates:
- OpenTofu creates the VM shell on the Debian cloud image
- nixos-anywhere then wipes it and installs the flake (legacy-BIOS GPT + ext4)
- Changes run `nixos/update.sh <netbird|edge>` from the controller:
  1. Update the flake inputs
  2. `build` first, which catches renamed options
  3. `switch --target-host`
  4. Check for failed units
  5. Warn if a new kernel needs a reboot
- `system.autoUpgrade` also runs every night from `main` of the public GitHub repo, with `--update-input nixpkgs` and `--no-write-lock-file`, reboots allowed inside a window (`schedules.yml`):
  - netbird: `netbird_upgrade_time` (03:00), reboots between 03:00 and 04:00
  - edge: `edge_upgrade_time` (04:00), reboots between 04:00 and 04:45

Hardening (`nixos/base/hardening.nix`, both VMs):
- Users only come from the config (immutable users), SSH is key-only, LAN-only and on port `ssh_port`, with modern ciphers/KEX/MACs only
- nftables denies by default, each host opens only its own ports
- Kernel parameters and sysctls (`slab_nomerge`, `init_on_free`, `kptr_restrict=2`, `kexec_load_disabled` and more)
- AppArmor, auditd, and fail2ban for SSH
- AIDE watches the few paths an upgrade never touches ([0009](0009-aide-with-manual-accept.md))

NetBird VM only (`nixos/netbird/netbird.nix`):
- Only 443 and the coturn ports are public, and on 443 the WAN only reaches the gRPC paths
- The dashboard (`/`) and `/api` only answer the LAN (nginx `geo` on `lan_cidr`), everyone else gets `return 444`, a silent close
- VPN peers count as LAN, because their traffic is NATed through the routing peer
- The fail2ban jail `nginx-lan-only` bans after 5 hits on those paths in 10 minutes (`probeMaxRetry` / `probeFindTime`)

Secrets:
- Put on each VM by hand under `/var/lib/secrets/netbird` and `/var/lib/secrets/edge`, never in git

- Enforced by: the whole OS is the flake, `update.sh` builds before it switches, and `just check` runs `nix flake check`

## Consequences

- Easier: the whole OS is in git, a rollback is just the previous generation (`nixos-rebuild switch --rollback`)
- Easier: hardening, AIDE, logging and time are written once for both VMs

- Harder: a second deploy path next to Ansible, with Nix tooling on the controller and its own update script
- Harder: the unstable channel has the newest NetBird module, but upgrades can break options. That's why `update.sh` builds before it switches
- Harder: autoUpgrade builds `main` with its local copy of `private.yml` (`/etc/homelab-private`), so a change on `testing` only sticks once it's merged, and a `private.yml` change needs an `update.sh` run

- Accepted: whoever can merge to `main` is root on both VMs by the next night. What guards `main`: changes only through a PR, CI must pass, signed commits, and two-factor login on my GitHub account
- Accepted: the VMs move to the newest nixos-unstable every night. `flake.lock` in git is not what runs, and `nix flake check` in CI tests a different nixpkgs than the next night's build
- Accepted: a bad upgrade can take LAN DNS and ingress down at 04:00 until I roll back to the previous generation
- Accepted: the NetBird management service only has the module's own sandbox. Extra systemd sandboxing kills netbird-mgmt during the OIDC call
- Accepted: the secrets live outside Nix for now, agenix/sops is still open

- Facts are shared with the rest through group_vars ([0007](0007-group-vars-single-source-of-truth.md))

- Related: [0003](0003-netbird-instead-of-port-forwards.md) (NetBird), [0007](0007-group-vars-single-source-of-truth.md) (shared vars), [0008](0008-nixos-for-the-dmz-box.md) (superseded), [0009](0009-aide-with-manual-accept.md) (AIDE), [0022](0022-central-logging-relp.md) (logging), [0023](0023-chrony-with-nts.md) (time), [0024](0024-ansible-run-os-updates.md) (apt hosts), [0032](0032-edge-vm-traefik-adguard-on-nixos.md) (edge), [0034](0034-tls-via-dns-01.md) (TLS)
